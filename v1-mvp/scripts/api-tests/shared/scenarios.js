import http from 'k6/http';
import { check, sleep } from 'k6';

// ============ Configuration ============
export const BASE_URL = __ENV.BASE_URL || 'https://dev.tasteam.kr';

// 테스트 계정 정보
// 테스트 계정 정보
const TEST_USER_PREFIX = 'test-user-';
const TEST_USER_COUNT = 100;

export function getTestUser(index) {
    return {
        identifier: `${TEST_USER_PREFIX}${String(index).padStart(3, '0')}`,
        nickname: `부하테스트계정${index}`,
    };
}


const TEST_GROUP = {
    id: 2002,
    code: 'LOCAL-1234',
};

const TEST_RESTAURANT_ID = 6001;

// ============ Shared State ============
// VU별 상태를 저장하기 위한 객체
export function createState() {
    return {
        token: null,
        groupId: null,
        restaurantId: null,
        reviewId: null,
        keywordIds: [],
    };
}

// ============ Common Headers ============
function getHeaders(token = null) {
    const headers = {
        'Content-Type': 'application/json',
    };
    if (token) {
        headers['Authorization'] = `Bearer ${token}`;
    }
    return headers;
}

// ============ Auth Functions ============

/**
 * 테스트 계정으로 로그인하고 토큰을 반환합니다.
 */
/**
 * 테스트 계정으로 로그인하고 토큰을 반환합니다.
 */
export function login(user) {
    const targetUser = user || getTestUser(1);
    const payload = JSON.stringify({
        identifier: targetUser.identifier,
        nickname: targetUser.nickname,
    });

    const res = http.post(
        `${BASE_URL}/api/v1/auth/token/test`,
        payload,
        { headers: getHeaders() }
    );

    const success = check(res, {
        '로그인 성공 (200)': (r) => r.status === 200,
    });

    if (success) {
        return res.json('data.accessToken');
    }
    return null;
}

/**
 * 다수 계정 배치 로그인
 */
export function batchLogin(count = 50) {
    const requests = [];
    for (let i = 1; i <= count; i++) {
        const user = getTestUser(i);
        requests.push({
            method: 'POST',
            url: `${BASE_URL}/api/v1/auth/token/test`,
            body: JSON.stringify({
                identifier: user.identifier,
                nickname: user.nickname,
            }),
            params: { headers: getHeaders() },
        });
    }

    const responses = http.batch(requests);
    const tokens = [];

    responses.forEach((res, i) => {
        if (res.status === 200) {
            try {
                const token = res.json('data.accessToken');
                if (token) tokens.push(token);
            } catch (e) {
                console.error(`User ${i + 1} login parse error`);
            }
        } else {
            console.error(`User ${i + 1} login failed: ${res.status}`);
        }
    });

    return tokens;
}

/**
 * 그룹에 가입합니다.
 */
export function joinGroup(token) {
    const payload = JSON.stringify({
        code: TEST_GROUP.code,
    });

    const res = http.post(
        `${BASE_URL}/api/v1/groups/${TEST_GROUP.id}/password-authentications`,
        payload,
        { headers: getHeaders(token) }
    );

    check(res, {
        '그룹 가입 성공 (201)': (r) => r.status === 201,
    });

    return res.status === 201 ? TEST_GROUP.id : null;
}

/**
 * 리뷰 키워드 목록을 조회합니다.
 */
export function getReviewKeywords(token) {
    const res = http.get(
        `${BASE_URL}/api/v1/reviews/keywords`,
        { headers: getHeaders(token) }
    );

    check(res, {
        '리뷰 키워드 조회 성공 (200)': (r) => r.status === 200,
    });

    if (res.status === 200) {
        try {
            const data = res.json('data');
            if (data && data.length > 0) {
                return data.map((k) => k.id);
            }
        } catch (e) {
            // ignore
        }
    }
    return [1]; // fallback
}

// ============ Read Scenarios ============

/**
 * 메인 페이지 조회
 */
export function getMainPage(token) {
    const res = http.get(
        `${BASE_URL}/api/v1/main?latitude=37.395&longitude=127.11`,
        { headers: getHeaders(token), tags: { name: 'main_page' } }
    );

    check(res, {
        '메인 페이지 조회 성공 (200)': (r) => r.status === 200,
    });

    return res;
}

/**
 * 음식점 목록 조회
 */
export function getRestaurantList(token) {
    const res = http.get(
        `${BASE_URL}/api/v1/restaurants?latitude=37.395&longitude=127.11`,
        { headers: getHeaders(token), tags: { name: 'restaurant_list' } }
    );

    check(res, {
        '음식점 목록 조회 성공 (200)': (r) => r.status === 200,
    });

    // 첫 번째 음식점 ID 추출
    let restaurantId = null;
    if (res.status === 200) {
        try {
            const items = res.json('data.items');
            if (items && items.length > 0) {
                restaurantId = items[0].id;
            }
        } catch (e) {
            // ignore
        }
    }

    return { response: res, restaurantId };
}

/**
 * 음식점 상세 조회
 */
export function getRestaurantDetail(token, restaurantId) {
    if (!restaurantId) return null;

    const res = http.get(
        `${BASE_URL}/api/v1/restaurants/${restaurantId}`,
        { headers: getHeaders(token), tags: { name: 'restaurant_detail' } }
    );

    check(res, {
        '음식점 상세 조회 성공 (200)': (r) => r.status === 200,
    });

    return res;
}

/**
 * 음식점 리뷰 목록 조회
 */
export function getRestaurantReviews(token, restaurantId) {
    if (!restaurantId) return { response: null, reviewId: null };

    const res = http.get(
        `${BASE_URL}/api/v1/restaurants/${restaurantId}/reviews`,
        { headers: getHeaders(token), tags: { name: 'restaurant_reviews' } }
    );

    check(res, {
        '음식점 리뷰 목록 조회 성공 (200)': (r) => r.status === 200,
    });

    let reviewId = null;
    if (res.status === 200) {
        try {
            const items = res.json('data.items');
            if (items && items.length > 0) {
                reviewId = items[0].id;
            }
        } catch (e) {
            // ignore
        }
    }

    return { response: res, reviewId };
}

/**
 * 그룹 상세 조회
 */
export function getGroupDetail(token, groupId) {
    if (!groupId) return null;

    const res = http.get(
        `${BASE_URL}/api/v1/groups/${groupId}`,
        { headers: getHeaders(token), tags: { name: 'group_detail' } }
    );

    check(res, {
        '그룹 상세 조회 성공 (200)': (r) => r.status === 200,
    });

    return res;
}

/**
 * 그룹 리뷰 목록 조회
 */
export function getGroupReviews(token, groupId) {
    if (!groupId) return { response: null, reviewId: null };

    const res = http.get(
        `${BASE_URL}/api/v1/groups/${groupId}/reviews`,
        { headers: getHeaders(token), tags: { name: 'group_reviews' } }
    );

    check(res, {
        '그룹 리뷰 목록 조회 성공 (200)': (r) => r.status === 200,
    });

    let reviewId = null;
    if (res.status === 200) {
        try {
            const items = res.json('data.items');
            if (items && items.length > 0) {
                reviewId = items[0].id;
            }
        } catch (e) {
            // ignore
        }
    }

    return { response: res, reviewId };
}

/**
 * 리뷰 상세 조회
 */
export function getReviewDetail(token, reviewId) {
    if (!reviewId) return null;

    const res = http.get(
        `${BASE_URL}/api/v1/reviews/${reviewId}`,
        { headers: getHeaders(token), tags: { name: 'review_detail' } }
    );

    check(res, {
        '리뷰 상세 조회 성공 (200)': (r) => r.status === 200,
    });

    return res;
}

/**
 * 통합 검색
 */
export function search(token, keyword = 'test') {
    const res = http.post(
        `${BASE_URL}/api/v1/search?keyword=${encodeURIComponent(keyword)}`,
        null,
        { headers: getHeaders(token), tags: { name: 'search' } }
    );

    check(res, {
        '통합 검색 성공 (200)': (r) => r.status === 200,
    });

    return res;
}

// ============ Write Scenarios ============

/**
 * 리뷰 작성
 */
export function createReview(token, groupId, keywordIds) {
    const targetGroupId = groupId || TEST_GROUP.id;
    const selectedKeywordIds = keywordIds && keywordIds.length > 0 ? [keywordIds[0]] : [1];

    const payload = JSON.stringify({
        content: `브레이크포인트 테스트 리뷰 - ${Date.now()}`,
        groupId: targetGroupId,
        keywordIds: selectedKeywordIds,
        isRecommended: true,
    });

    const res = http.post(
        `${BASE_URL}/api/v1/restaurants/${TEST_RESTAURANT_ID}/reviews`,
        payload,
        { headers: getHeaders(token), tags: { name: 'create_review' } }
    );

    check(res, {
        '리뷰 작성 성공 (201 or 200)': (r) => r.status === 201 || r.status === 200,
    });

    return res;
}

// ============ Composite Scenarios ============

/**
 * 전체 조회 시나리오 실행 (SLO: p95 < 1초)
 */
export function executeReadScenario(state) {
    let successCount = 0;

    // 메인 페이지
    const resMain = getMainPage(state.token);
    if (resMain && resMain.status === 200) successCount++;

    // 음식점 목록 + ID 추출
    const listResult = getRestaurantList(state.token);
    if (listResult.response && listResult.response.status === 200) successCount++;
    const restaurantId = listResult.restaurantId || state.restaurantId;

    // 음식점 상세
    if (restaurantId) {
        const resDetail = getRestaurantDetail(state.token, restaurantId);
        if (resDetail && resDetail.status === 200) successCount++;
    }

    // 음식점 리뷰 목록
    const reviewResult = getRestaurantReviews(state.token, restaurantId);
    if (reviewResult.response && reviewResult.response.status === 200) successCount++;
    const reviewId = reviewResult.reviewId || state.reviewId;

    // 그룹 상세
    if (state.groupId) {
        const resGroup = getGroupDetail(state.token, state.groupId);
        if (resGroup && resGroup.status === 200) successCount++;
    }

    // 그룹 리뷰 목록
    if (state.groupId) {
        const resGroupReview = getGroupReviews(state.token, state.groupId);
        if (resGroupReview && resGroupReview.response && resGroupReview.response.status === 200) successCount++;
    }

    // 리뷰 상세
    if (reviewId) {
        const resReview = getReviewDetail(state.token, reviewId);
        if (resReview && resReview.status === 200) successCount++;
    }

    // 통합 검색
    const resSearch = search(state.token);
    if (resSearch && resSearch.status === 200) successCount++;

    return successCount;
}

/**
 * 전체 쓰기 시나리오 실행 (SLO: p95 < 3초)
 */
export function executeWriteScenario(state) {
    const res = createReview(state.token, state.groupId, state.keywordIds);
    if (res && (res.status === 200 || res.status === 201)) {
        return 1;
    }
    return 0;
}
