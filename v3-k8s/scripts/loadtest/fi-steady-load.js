import { sleep } from 'k6';
import http from 'k6/http';
import { Counter, Rate, Trend } from 'k6/metrics';
import {
    createState,
    getReviewKeywords,
    getHomePage,
    getRestaurantDetail,
    search,
    createReview,
    getGroupDetail,
    resolveGroupContext,
    pickKeyword,
    pickRestaurantId,
    randomSearchLocation,
    extractRestaurantIdsFromSectionsResponse,
    pickRandomRestaurantId,
} from './shared/scenarios.js';

// --- 메트릭 ---
const readOps = new Counter('fi_read_ops');
const writeOps = new Counter('fi_write_ops');
const errorRate = new Rate('fi_error_rate');
const latency = new Trend('fi_latency', true);

// --- 설정 ---
const STG_URL = 'https://stg.tasteam.kr';
const PROD_URL = __ENV.BASE_URL || 'https://api.tasteam.kr';

export const options = {
    thresholds: {
        fi_error_rate: ['rate<0.05'],
        fi_latency: ['p(95)<3000'],
    },
};

// --- Setup: stg에서 토큰 1개 발급, prod로 부하 ---
export function setup() {
    console.log(`[FI Steady] token_source=${STG_URL} target=${PROD_URL}`);

    // stg에서 테스트 유저 토큰 발급
    const res = http.post(
        `${STG_URL}/api/v1/test/auth/token`,
        JSON.stringify({ identifier: 'test-user-001', nickname: '부하테스트계정1' }),
        { headers: { 'Content-Type': 'application/json' } },
    );
    if (res.status !== 200) {
        throw new Error(`토큰 발급 실패: status=${res.status} body=${res.body}`);
    }
    const token = JSON.parse(res.body).accessToken;

    const keywordIds = getReviewKeywords(token);
    const groupContext = resolveGroupContext(token);
    const groupId = groupContext.groupId || Number(__ENV.TEST_GROUP_ID || '302');

    console.log(`[FI Steady] setup 완료: groupId=${groupId}`);
    return { token, groupId, keywordIds };
}

// --- 메인 시나리오: read 85% / write 15% (채팅 제외) ---
export default function (data) {
    const token = data.token;
    const state = createState();
    state.token = token;
    state.groupId = data.groupId;
    state.keywordIds = data.keywordIds;

    const pivot = Math.random();

    if (pivot < 0.35) {
        // 홈 + 상세 (35%)
        const loc = { lat: 37.5665, lon: 126.978 };
        const home = getHomePage(token, loc.lat, loc.lon);
        track(home, 'read');
        const rid = pickRandomRestaurantId(extractRestaurantIdsFromSectionsResponse(home));
        if (rid) {
            const detail = getRestaurantDetail(token, rid);
            track(detail, 'read');
        }
    } else if (pivot < 0.65) {
        // 검색 (30%)
        const loc = randomSearchLocation();
        const res = search(token, pickKeyword(state), loc);
        track(res, 'read');
    } else if (pivot < 0.85) {
        // 그룹/서브그룹 조회 (20%)
        const g = getGroupDetail(token, data.groupId);
        track(g, 'read');
    } else {
        // 리뷰 작성 (15%)
        const restaurantId = pickRestaurantId(state);
        const res = createReview(token, data.groupId, data.keywordIds, restaurantId);
        track(res, 'write');
    }

    sleep(1 + Math.random() * 2);
}

function track(res, type) {
    if (!res) return;
    if (type === 'read') readOps.add(1);
    else writeOps.add(1);

    if (res.timings) latency.add(res.timings.duration);

    if (res.status >= 400 || res.status === 0) errorRate.add(1);
    else errorRate.add(0);
}

export function teardown() {
    console.log('[FI Steady] 부하 종료');
}
