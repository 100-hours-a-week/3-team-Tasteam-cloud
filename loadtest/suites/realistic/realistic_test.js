/**
 * Realistic Load Test - 실제 사용자 행동 패턴 시뮬레이션
 *
 * 목적: 실제 사용자 트래픽 패턴 재현 (저부하 + 전 API 커버)
 *
 * Journey 가중치:
 *   - browsing  28% : 홈 → 음식 카테고리 → 음식점 목록(랜덤 위치) → 상세 → 메뉴 → 리뷰 + 위치조회/즐겨찾기
 *   - searching 18% : 최근 검색어 → 랜덤 키워드 검색(위치 포함) 1~3회 → 결과 음식점 상세 + 즐겨찾기
 *   - group     12% : 그룹 상세 → 그룹 리뷰 → 그룹 멤버 → 그룹 리뷰 음식점 → 서브그룹 목록 + 알림읽음
 *   - subgroup  12% : 서브그룹 목록 → 상세 → 멤버 → 리뷰 → 채팅방 → 메시지 → 읽음커서
 *   - personal  12% : 내 프로필 → 내 리뷰 → 알림 → 즐겨찾기 → 내 그룹 + 알림읽음
 *   - chat      10% : 채팅 페이지네이션 → 메시지 전송 → 읽음커서
 *   - writing    8% : AI추천 → 프로모션 → 키워드 조회 → 리뷰 작성
 *
 * 실행 방법:
 *   ./run-realistic.sh
 *   ./run-realistic.sh --no-prometheus
 *   BASE_URL=https://prod.tasteam.kr ./run-realistic.sh
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
    executeSubgroupJourney,
    executePersonalJourney,
    executeChatJourney,
    executeWritingJourney,
    prepareHotspotPools,
} from '../../shared/scenarios.js';
import { logTestStart, createJourneyMetrics } from '../../shared/test-utils.js';

// ============ Custom Metrics ============
const metrics = createJourneyMetrics();

// ============ Journey 선택 (가중치 기반) ============
const JOURNEYS = [
    { name: 'browsing',  weight: 28, fn: executeBrowsingJourney },
    { name: 'searching', weight: 18, fn: executeSearchingJourney },
    { name: 'group',     weight: 12, fn: executeGroupJourney },
    { name: 'subgroup',  weight: 12, fn: executeSubgroupJourney },
    { name: 'personal',  weight: 12, fn: executePersonalJourney },
    { name: 'chat',      weight: 10, fn: executeChatJourney },
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
        realistic: {
            executor: 'ramping-vus',
            stages: [
                { target: 100,  duration: '2m' },  // 워밍업
                { target: 300,  duration: '5m' },  // 평시
                { target: 500,  duration: '5m' },  // 점심 피크
                { target: 300,  duration: '5m' },  // 오후
                { target: 700,  duration: '5m' },  // 저녁 피크
                { target: 1000, duration: '5m' },  // 최대 피크
                { target: 500,  duration: '5m' },  // 저녁 후
                { target: 200,  duration: '5m' },  // 야간
                { target: 100,  duration: '3m' },  // 램프다운
                { target: 0,    duration: '2m' },  // 종료
            ],
        },
    },
    thresholds: {
        'http_req_duration':             ['p(95)<2000'],  // 전체 p95 < 2초
        'http_req_failed':               ['rate<0.01'],   // 에러율 < 1%
        'http_req_duration{type:read}':  ['p(95)<1000'],  // 읽기 p95 < 1초
        'http_req_duration{type:write}': ['p(95)<3000'],  // 쓰기 p95 < 3초
    },
};

// ============ Setup ============
export function setup() {
    logTestStart('Realistic Load Test', BASE_URL);
    console.log('   Journey 가중치: browsing 28% / searching 18% / group 12% / subgroup 12% / personal 12% / chat 10% / writing 8%');
    console.log('   VU 범위: 100 ~ 1000 (ramping-vus)');
    console.log('   총 실행 시간: ~42분');

    const tokens = batchLogin(100);
    if (!tokens || tokens.length === 0) {
        console.error('❌ 로그인 실패 - 테스트 중단');
        return null;
    }

    const baseToken = tokens[0];
    const keywordIds = getReviewKeywords(baseToken);

    // 1. 기존 그룹 조회 (로컬 DB 상태 무관하게 동작)
    let groupId = null;
    let groupIds = [];
    const myGroupsRes = getMyGroups(baseToken);
    if (myGroupsRes && myGroupsRes.status === 200) {
        try {
            const items = myGroupsRes.json('data.items');
            if (items && items.length > 0) {
                groupId = items[0].id;
                groupIds = items.map((item) => item.id).filter(Boolean);
            }
        } catch (e) { /* ignore */ }
    }

    // 2. 속한 그룹 없으면 joinGroup 시도 (실패해도 null로 진행)
    if (!groupId) {
        groupId = joinGroup(baseToken);
    }

    if (groupIds.length === 0 && groupId) {
        groupIds = [groupId];
    }

    // subgroupId 획득
    const subgroupsRes = getGroupSubgroups(baseToken, groupId);
    const subgroupId = (subgroupsRes && subgroupsRes.items && subgroupsRes.items.length > 0)
        ? subgroupsRes.items[0].subgroupId
        : null;

    // chatRoomId 획득
    let chatRoomId = null;
    if (subgroupId) {
        const chatRoomRes = getSubgroupChatRoom(baseToken, subgroupId);
        chatRoomId = (chatRoomRes && chatRoomRes.chatRoomId) || null;
    }

    const hotspot = prepareHotspotPools(baseToken, groupIds);

    console.log(`✅ Setup 완료: tokens=${tokens.length}개, groupId=${groupId}, subgroupId=${subgroupId}, chatRoomId=${chatRoomId}, keywords=${keywordIds.length}개`);

    return { tokens, groupId, subgroupId, chatRoomId, keywordIds, hotspot };
}

// ============ Main VU Function ============
export default function(data) {
    if (!data || !data.tokens || data.tokens.length === 0) {
        console.error('❌ Setup 데이터 없음');
        return;
    }

    // 랜덤 토큰 선택
    const token = data.tokens[Math.floor(Math.random() * data.tokens.length)];
    const state = createState();
    state.token = token;
    state.groupId = data.groupId;
    state.subgroupId = data.subgroupId;
    state.chatRoomId = data.chatRoomId;
    state.keywordIds = data.keywordIds;
    state.hotspot = data.hotspot || null;

    // Journey 선택 및 실행
    const journey = selectJourney();
    const count = journey.fn(state);
    metrics.add(count, `${journey.name}_count`);

    // Think time: 1~5초 (실제 사용자 행동 간격 시뮬레이션)
    sleep(1 + Math.random() * 4);
}

// ============ Teardown ============
export function teardown(data) {
    console.log('🏁 Realistic Load Test 완료');
    console.log('   결과는 k6 summary 및 Grafana 대시보드에서 확인하세요.');
}
