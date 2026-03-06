/**
 * Recovery Test - 스파이크 후 복구 관찰 테스트
 *
 * 목적: 급격한 부하 이후 시스템이 정상 응답 수준으로 복구되는지 검증
 *
 * 단계:
 *   Phase 1 (3분): 50→500 VU (스파이크)
 *   Phase 2 (1분): 500 VU 유지
 *   Phase 3 (2분): 500→50 VU (램프다운)
 *   Phase 4 (10분): 50 VU 저부하 (복구 관찰)
 *
 * 복구 완료 기준 (Phase 4):
 *   - read p95 < 1.5s
 *   - 에러율 < 0.1%
 *
 * 실행 방법:
 *   ./run-recovery.sh
 *   BASE_URL=https://stg.tasteam.kr k6 run recovery_test.js
 */

import { sleep } from 'k6';
import {
    BASE_URL,
    createState,
    batchLogin,
    joinGroup,
    getMyGroups,
    getReviewKeywords,
    getGroupSubgroups,
    getSubgroupChatRoom,
    executeBrowsingJourney,
    executeSearchingJourney,
    executeGroupJourney,
    executePersonalJourney,
    executeWritingJourney,
} from './shared/scenarios.js';
import { logTestStart, createJourneyMetrics } from './shared/test-utils.js';

const metrics = createJourneyMetrics();

// ============ Journey 선택 ============
const JOURNEYS = [
    { name: 'browsing',  weight: 28, fn: executeBrowsingJourney },
    { name: 'searching', weight: 18, fn: executeSearchingJourney },
    { name: 'group',     weight: 12, fn: executeGroupJourney },
    { name: 'personal',  weight: 12, fn: executePersonalJourney },
    { name: 'writing',   weight:  8, fn: executeWritingJourney },
];
const TOTAL_WEIGHT = JOURNEYS.reduce((sum, j) => sum + j.weight, 0);

function selectJourney() {
    let rand = Math.random() * TOTAL_WEIGHT;
    for (const journey of JOURNEYS) {
        rand -= journey.weight;
        if (rand <= 0) return journey;
    }
    return JOURNEYS[0];
}

// ============ Test Options ============
export const options = {
    scenarios: {
        recovery: {
            executor: 'ramping-vus',
            startVUs: 50,
            stages: [
                { target: 500, duration: '3m' },  // Phase 1: 스파이크
                { target: 500, duration: '1m' },  // Phase 2: 유지
                { target: 50,  duration: '2m' },  // Phase 3: 램프다운
                { target: 50,  duration: '10m' }, // Phase 4: 복구 관찰
            ],
        },
    },
    thresholds: {
        // 전체 구간 기준
        'http_req_duration':             ['p(95)<3000'],
        'http_req_failed':               ['rate<0.01'],
        // Phase 4 복구 기준 (전체 임계치로 근사 - 실제 Phase 4 측정은 Grafana에서 확인)
        'http_req_duration{type:read}':  ['p(95)<1500'],
        'http_req_duration{type:write}': ['p(95)<3000'],
    },
};

// ============ Setup ============
export function setup() {
    logTestStart('Recovery Test', BASE_URL);
    console.log('   Phase 1 (3m): 50→500 VU 스파이크');
    console.log('   Phase 2 (1m): 500 VU 유지');
    console.log('   Phase 3 (2m): 500→50 VU 램프다운');
    console.log('   Phase 4 (10m): 50 VU 저부하 복구 관찰');

    const tokens = batchLogin(100);
    if (!tokens || tokens.length === 0) {
        console.error('❌ 로그인 실패 - 테스트 중단');
        return null;
    }

    const baseToken = tokens[0];
    const keywordIds = getReviewKeywords(baseToken);

    let groupId = null;
    const myGroupsRes = getMyGroups(baseToken);
    if (myGroupsRes && myGroupsRes.status === 200) {
        try {
            const items = myGroupsRes.json('data.items');
            if (items && items.length > 0) groupId = items[0].id;
        } catch (e) { /* ignore */ }
    }
    if (!groupId) groupId = joinGroup(baseToken);

    const subgroupsRes = getGroupSubgroups(baseToken, groupId);
    const subgroupId = (subgroupsRes && subgroupsRes.items && subgroupsRes.items.length > 0)
        ? subgroupsRes.items[0].subgroupId : null;

    let chatRoomId = null;
    if (subgroupId) {
        const chatRoomRes = getSubgroupChatRoom(baseToken, subgroupId);
        chatRoomId = (chatRoomRes && chatRoomRes.chatRoomId) || null;
    }

    console.log(`✅ Setup 완료: tokens=${tokens.length}개, groupId=${groupId}, subgroupId=${subgroupId}, chatRoomId=${chatRoomId}`);
    return { tokens, groupId, subgroupId, chatRoomId, keywordIds };
}

// ============ Main VU Function ============
export default function(data) {
    if (!data || !data.tokens || data.tokens.length === 0) {
        console.error('❌ Setup 데이터 없음');
        return;
    }

    const token = data.tokens[Math.floor(Math.random() * data.tokens.length)];
    const state = createState();
    state.token = token;
    state.groupId = data.groupId;
    state.subgroupId = data.subgroupId;
    state.chatRoomId = data.chatRoomId;
    state.keywordIds = data.keywordIds;

    const journey = selectJourney();
    const count = journey.fn(state);
    metrics.add(count, `${journey.name}_count`);

    sleep(1 + Math.random() * 3);
}

// ============ Teardown ============
export function teardown(data) {
    console.log('🏁 Recovery Test 완료');
    console.log('   Phase 4 (저부하 10분) 구간의 p95 추이를 Grafana에서 확인하세요.');
    console.log('   복구 완료 기준: read p95 < 1.5s, 에러율 < 0.1%');
}
