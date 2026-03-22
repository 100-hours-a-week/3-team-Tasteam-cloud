import { sleep } from 'k6';
import http from 'k6/http';
import { Counter, Rate } from 'k6/metrics';
import {
    BASE_URL,
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
const readSuccess = new Counter('read_success_count');
const writeSuccess = new Counter('write_success_count');
const errorRate = new Rate('bp_error_rate');

// --- 설정 ---
const STG_URL = 'https://stg.tasteam.kr';
const SUITE = (__ENV.TEST_SUITE || 'breakpoint').toLowerCase();

function buildOptions() {
    const breakpoint_read = {
        executor: 'ramping-arrival-rate',
        startRate: 40,
        timeUnit: '1s',
        preAllocatedVUs: 200,
        maxVUs: 2000,
        stages: [
            { target: 100, duration: '1m' },
            { target: 300, duration: '1m' },
            { target: 600, duration: '1m' },
            { target: 1000, duration: '1m' },
            { target: 1500, duration: '1m' },
            { target: 2000, duration: '1m' },
            { target: 3000, duration: '1m' },
            { target: 4500, duration: '1m' },
            { target: 6000, duration: '1m' },
        ],
        exec: 'breakpointRead',
        tags: { phase: 'breakpoint', rw: 'read' },
    };

    const breakpoint_write = {
        executor: 'ramping-arrival-rate',
        startRate: 10,
        timeUnit: '1s',
        preAllocatedVUs: 100,
        maxVUs: 1000,
        stages: [
            { target: 30, duration: '1m' },
            { target: 60, duration: '1m' },
            { target: 120, duration: '1m' },
            { target: 200, duration: '1m' },
            { target: 300, duration: '1m' },
            { target: 450, duration: '1m' },
            { target: 600, duration: '1m' },
            { target: 900, duration: '1m' },
            { target: 1200, duration: '1m' },
        ],
        exec: 'breakpointWrite',
        tags: { phase: 'breakpoint', rw: 'write' },
    };

    if (SUITE === 'breakpoint_read') return { breakpoint_read };
    if (SUITE === 'breakpoint_write') return { breakpoint_write };
    return { breakpoint_read, breakpoint_write };
}

export const options = {
    scenarios: buildOptions(),
    thresholds: {
        'http_req_failed{scenario:breakpoint_read}': [
            { threshold: 'rate<0.30', abortOnFail: true, delayAbortEval: '30s' },
        ],
        'http_req_failed{scenario:breakpoint_write}': [
            { threshold: 'rate<0.30', abortOnFail: true, delayAbortEval: '30s' },
        ],
        'http_req_duration{scenario:breakpoint_read}': [
            { threshold: 'p(99)<15000', abortOnFail: true, delayAbortEval: '30s' },
        ],
        'http_req_duration{scenario:breakpoint_write}': [
            { threshold: 'p(99)<15000', abortOnFail: true, delayAbortEval: '30s' },
        ],
    },
};

// --- Setup: stg에서 토큰 1개 발급 ---
export function setup() {
    console.log(`[Breakpoint] token_source=${STG_URL} target=${BASE_URL} suite=${SUITE}`);

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
    const groupId = groupContext.groupId;

    console.log(`[Breakpoint] setup 완료: groupId=${groupId}`);
    return { token, groupId, keywordIds };
}

function buildState(data) {
    const state = createState();
    state.token = data.token;
    state.groupId = data.groupId;
    state.keywordIds = data.keywordIds;
    return state;
}

// --- Read 시나리오 ---
export function breakpointRead(data) {
    const state = buildState(data);
    const token = state.token;
    let count = 0;

    // 홈 + 상세
    const loc = randomSearchLocation();
    const home = getHomePage(token, loc.lat, loc.lon);
    if (home && home.status === 200) count++;
    const rid = pickRandomRestaurantId(extractRestaurantIdsFromSectionsResponse(home));
    if (rid) {
        const detail = getRestaurantDetail(token, rid);
        if (detail && detail.status === 200) count++;
    }

    // 검색
    const searchRes = search(token, pickKeyword(state), randomSearchLocation());
    if (searchRes && searchRes.status === 200) count++;

    // 그룹 조회
    if (state.groupId) {
        const g = getGroupDetail(token, state.groupId);
        if (g && g.status === 200) count++;
    }

    readSuccess.add(count);
}

// --- Write 시나리오 ---
export function breakpointWrite(data) {
    const state = buildState(data);
    const restaurantId = pickRestaurantId(state);
    const res = createReview(state.token, state.groupId, state.keywordIds, restaurantId);
    if (res && (res.status === 200 || res.status === 201)) {
        writeSuccess.add(1);
    }
}

export function teardown() {
    console.log('[Breakpoint] 테스트 종료');
}
