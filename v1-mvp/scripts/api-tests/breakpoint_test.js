/**
 * Breakpoint Test - SLO 기반 한계점 탐색 테스트
 *
 * 목적: 시스템이 SLO를 위반하기 시작하는 부하 수준을 파악
 *
 * SLO 기준:
 *   - 조회 API: p95 < 1초
 *   - 리뷰 작성: p95 < 3초
 *   - 에러율: < 0.1% (가용성 99.9%)
 *
 * 실행 방법:
 *   k6 run breakpoint_test.js
 *
 * Prometheus 출력:
 *   K6_PROMETHEUS_RW_SERVER_URL=<url> k6 run -o experimental-prometheus-rw breakpoint_test.js
 */

import { sleep } from 'k6';
import {
    BASE_URL,
    createState,
    login,
    batchLogin,
    joinGroup,
    getReviewKeywords,
    executeReadScenario,
    executeWriteScenario,
} from './shared/scenarios.js';

// ============ Test Options ============
export const options = {
    scenarios: {
        // 조회 시나리오 (80% 비율)
        read_scenario: {
            executor: 'ramping-arrival-rate',
            startRate: 8,           // 초당 8개 요청으로 시작
            timeUnit: '1s',
            preAllocatedVUs: 2000,
            maxVUs: 30000,
            stages: [
                { target: 200, duration: '1m' },
                { target: 500, duration: '1m' },
                { target: 1000, duration: '1m' },
                { target: 3000, duration: '2m' },
            ],
            exec: 'readScenario',
        },
        // 쓰기 시나리오 (20% 비율)
        write_scenario: {
            executor: 'ramping-arrival-rate',
            startRate: 2,           // 초당 2개 요청으로 시작
            timeUnit: '1s',
            preAllocatedVUs: 500,
            maxVUs: 10000,
            stages: [
                { target: 50, duration: '1m' },
                { target: 100, duration: '1m' },
                { target: 300, duration: '1m' },
                { target: 600, duration: '2m' },
            ],
            exec: 'writeScenario',
        },
    },
    thresholds: {
        // SLO 기반 임계치
        'http_req_duration{scenario:read_scenario}': ['p(95)<1000'],   // 조회: p95 < 1초
        'http_req_duration{scenario:write_scenario}': ['p(95)<3000'], // 쓰기: p95 < 3초
        'http_req_failed': ['rate<0.001'],                             // 에러율 < 0.1%
    },
};

// ============ Setup ============
export function setup() {
    console.log(`🎯 Breakpoint Test 시작`);
    console.log(`   Target: ${BASE_URL}`);
    console.log(`   Read:Write 비율 = 80:20`);
    console.log(`   최대 부하: 조회 3000 RPS, 쓰기 600 RPS (제한 해제 모드)`);

    // 다수 테스트 계정으로 배치 로그인 (50명)
    const tokens = batchLogin(50);
    if (!tokens || tokens.length === 0) {
        console.error('❌ 로그인 실패 - 테스트 중단');
        return null; // 모든 VU 중단
    }

    // 첫 번째 계정으로 그룹 가입 (대표)
    // 실제로는 각 사용자가 가입해야 할 수도 있지만, 
    // 현재 시나리오상 그룹 조회/리뷰 작성에 그룹 가입 여부가 필수라면 
    // 여기서는 대표 그룹 ID만 확보하고 진행하거나, 필요시 반복문으로 가입 처리
    // (기존 코드 유지: 하나의 그룹 ID 사용)
    const baseToken = tokens[0];
    const groupId = joinGroup(baseToken);

    // 리뷰 키워드 조회
    const keywordIds = getReviewKeywords(baseToken);

    console.log(`✅ Setup 완료: tokens=${tokens.length}개 획득, groupId=${groupId}, keywords=${keywordIds.length}개`);

    return {
        tokens, // 배열 전달
        groupId,
        keywordIds,
    };
}


// ============ Scenarios ============

/**
 * 조회 시나리오 (SLO: p95 < 1초)
 */
export function readScenario(data) {
    if (!data || !data.tokens || data.tokens.length === 0) {
        console.error('❌ Setup 데이터 없음');
        return;
    }

    // 랜덤 사용자 토큰 선택
    const randomToken = data.tokens[Math.floor(Math.random() * data.tokens.length)];

    const state = createState();
    state.token = randomToken;

    state.groupId = data.groupId;
    state.keywordIds = data.keywordIds;

    executeReadScenario(state);
}

/**
 * 쓰기 시나리오 (SLO: p95 < 3초)
 */
export function writeScenario(data) {
    if (!data || !data.tokens || data.tokens.length === 0) {
        console.error('❌ Setup 데이터 없음');
        return;
    }

    // 랜덤 사용자 토큰 선택
    const randomToken = data.tokens[Math.floor(Math.random() * data.tokens.length)];

    const state = createState();
    state.token = randomToken;

    state.groupId = data.groupId;
    state.keywordIds = data.keywordIds;

    executeWriteScenario(state);
}

// ============ Teardown ============
export function teardown(data) {
    console.log('🏁 Breakpoint Test 완료');
    console.log('   결과는 k6 summary 및 Grafana 대시보드에서 확인하세요.');
}
