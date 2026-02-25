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
        subgroupId: null,
        chatRoomId: null,
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
        { headers: getHeaders(token), tags: { name: 'main_page', type: 'read' } }
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
        { headers: getHeaders(token), tags: { name: 'restaurant_list', type: 'read' } }
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
        { headers: getHeaders(token), tags: { name: 'restaurant_detail', type: 'read' } }
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
        { headers: getHeaders(token), tags: { name: 'restaurant_reviews', type: 'read' } }
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
        { headers: getHeaders(token), tags: { name: 'group_detail', type: 'read' } }
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
        { headers: getHeaders(token), tags: { name: 'group_reviews', type: 'read' } }
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
        { headers: getHeaders(token), tags: { name: 'review_detail', type: 'read' } }
    );

    check(res, {
        '리뷰 상세 조회 성공 (200)': (r) => r.status === 200,
    });

    return res;
}

/**
 * 통합 검색
 */
export function search(token, keyword = 'test', loc = null) {
    let url = `${BASE_URL}/api/v1/search?keyword=${encodeURIComponent(keyword)}`;
    if (loc) {
        url += `&latitude=${loc.lat}&longitude=${loc.lon}&radiusKm=1`;
    }
    const res = http.post(
        url,
        null,
        { headers: getHeaders(token), tags: { name: 'search', type: 'read' } }
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
        { headers: getHeaders(token), tags: { name: 'create_review', type: 'write' } }
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

// ============ Random Data Generators ============

const LOCATIONS = [
    { lat: 37.5665, lon: 126.9780 }, // 시청
    { lat: 37.4979, lon: 127.0276 }, // 강남
    { lat: 37.5563, lon: 126.9723 }, // 홍대
    { lat: 37.5519, lon: 126.9918 }, // 명동
    { lat: 37.5172, lon: 127.0473 }, // 역삼
    { lat: 37.5144, lon: 127.1050 }, // 잠실
    { lat: 37.5796, lon: 126.9770 }, // 경복궁
    { lat: 37.5443, lon: 127.0557 }, // 성수
    { lat: 37.5600, lon: 127.0369 }, // 왕십리
    { lat: 37.5172, lon: 127.0391 }, // 선릉
    { lat: 37.5326, lon: 126.9003 }, // 여의도
    { lat: 37.5400, lon: 127.0695 }, // 건대입구
    { lat: 37.5779, lon: 126.9849 }, // 광화문
    { lat: 37.5174, lon: 127.0272 }, // 논현
    { lat: 37.5229, lon: 127.0247 }, // 신사/가로수길
    { lat: 37.5483, lon: 126.9164 }, // 마포
    { lat: 37.5838, lon: 127.0021 }, // 혜화/대학로
    { lat: 37.5506, lon: 126.9217 }, // 합정
    { lat: 37.5591, lon: 126.9264 }, // 망원
    { lat: 37.5670, lon: 126.9852 }, // 종로
];

const SEARCH_KEYWORDS = [
    // 음식 종류 (30개)
    '파스타', '피자', '삼겹살', '치킨', '초밥', '라멘', '쌀국수', '버거',
    '스테이크', '샐러드', '떡볶이', '김밥', '순대', '곱창', '갈비', '쌈밥',
    '비빔밥', '된장찌개', '순두부', '칼국수', '냉면', '짜장면', '짬뽕',
    '딤섬', '타코', '카레', '리조또', '그라탕', '퐁듀', '스시',
    // 분위기/목적 (20개)
    '데이트', '회식', '가족모임', '혼밥', '점심', '저녁', '브런치',
    '야식', '술집', '맥주', '분위기 좋은', '조용한', '인스타맛집',
    '가성비', '프리미엄', '신선한', '건강식', '비건', '채식', '유기농',
    // 지역명 (20개)
    '강남', '홍대', '이태원', '성수', '신촌', '종로', '명동', '여의도',
    '압구정', '청담', '마포', '용산', '서초', '신사', '가로수길',
    '해방촌', '연남동', '합정', '망원', '을지로',
    // 영문/기타 (10개)
    'burger', 'sushi', 'pasta', 'ramen', 'coffee', 'dessert',
    'steak', 'pizza', 'salad', 'vegan',
];

export const RADII = [500, 1000, 2000, 3000, 5000];

export function randomLocation() {
    const base = LOCATIONS[Math.floor(Math.random() * LOCATIONS.length)];
    return {
        lat: base.lat + (Math.random() - 0.5) * 0.02,
        lon: base.lon + (Math.random() - 0.5) * 0.02,
    };
}

export function randomKeyword() {
    return SEARCH_KEYWORDS[Math.floor(Math.random() * SEARCH_KEYWORDS.length)];
}

const CHAT_MESSAGES = [
    '오늘 점심 어디로 갈까요?', '여기 괜찮을 것 같아요!',
    '저는 파스타 먹고 싶어요', '근처에 새로 생긴 곳 가봤어요?',
    '가성비 좋은 곳 추천해주세요', '다음번엔 여기 꼭 가봐요',
    '메뉴 사진 보니까 맛있겠다', '예약 필요한가요?',
    `부하테스트 메시지 - ${Date.now()}`,
];

export function randomChatMessage() {
    return CHAT_MESSAGES[Math.floor(Math.random() * CHAT_MESSAGES.length)];
}

// ============ Additional API Functions ============

export function getHomePage(token) {
    const loc = randomLocation();
    const res = http.get(
        `${BASE_URL}/api/v1/main/home?latitude=${loc.lat}&longitude=${loc.lon}`,
        { headers: getHeaders(token), tags: { name: 'home_page', type: 'read' } }
    );
    check(res, { '홈 페이지 조회 성공 (200)': (r) => r.status === 200 });
    return res;
}

export function getFoodCategories() {
    const res = http.get(
        `${BASE_URL}/api/v1/food-categories`,
        { headers: getHeaders(), tags: { name: 'food_categories', type: 'read' } }
    );
    check(res, { '음식 카테고리 조회 성공 (200)': (r) => r.status === 200 });
    return res;
}

export function getRestaurantMenus(token, restaurantId) {
    if (!restaurantId) return null;
    const res = http.get(
        `${BASE_URL}/api/v1/restaurants/${restaurantId}/menus`,
        { headers: getHeaders(token), tags: { name: 'restaurant_menus', type: 'read' } }
    );
    check(res, { '음식점 메뉴 조회 성공 (200)': (r) => r.status === 200 });
    return res;
}

export function getRestaurantListByLocation(token, lat, lon, radius, size) {
    const pageSize = size || (Math.floor(Math.random() * 16) + 5);
    const radiusVal = radius || RADII[Math.floor(Math.random() * RADII.length)];
    const res = http.get(
        `${BASE_URL}/api/v1/restaurants?latitude=${lat}&longitude=${lon}&radius=${radiusVal}&size=${pageSize}`,
        { headers: getHeaders(token), tags: { name: 'restaurant_list_loc', type: 'read' } }
    );
    check(res, { '음식점 목록(위치) 조회 성공 (200)': (r) => r.status === 200 });
    let restaurantId = null;
    if (res.status === 200) {
        try {
            const items = res.json('data.items');
            if (items && items.length > 0) {
                restaurantId = items[Math.floor(Math.random() * items.length)].id;
            }
        } catch (e) {
            // ignore
        }
    }
    return { response: res, restaurantId };
}

export function getMyProfile(token) {
    const res = http.get(
        `${BASE_URL}/api/v1/members/me`,
        { headers: getHeaders(token), tags: { name: 'my_profile', type: 'read' } }
    );
    check(res, { '내 프로필 조회 성공 (200)': (r) => r.status === 200 });
    return res;
}

export function getMyGroups(token) {
    const res = http.get(
        `${BASE_URL}/api/v1/members/me/groups`,
        { headers: getHeaders(token), tags: { name: 'my_groups', type: 'read' } }
    );
    check(res, { '내 그룹 목록 조회 성공 (200)': (r) => r.status === 200 });
    return res;
}

export function getMyGroupsSummary(token) {
    const res = http.get(
        `${BASE_URL}/api/v1/members/me/groups/summary`,
        { headers: getHeaders(token), tags: { name: 'my_groups_summary', type: 'read' } }
    );
    check(res, { '내 그룹 요약 조회 성공 (200)': (r) => r.status === 200 });
    return res;
}

export function getMyReviews(token) {
    const res = http.get(
        `${BASE_URL}/api/v1/members/me/reviews`,
        { headers: getHeaders(token), tags: { name: 'my_reviews', type: 'read' } }
    );
    check(res, { '내 리뷰 조회 성공 (200)': (r) => r.status === 200 });
    return res;
}

export function getMyFavoriteRestaurants(token) {
    const res = http.get(
        `${BASE_URL}/api/v1/members/me/favorites/restaurants`,
        { headers: getHeaders(token), tags: { name: 'my_favorites', type: 'read' } }
    );
    check(res, { '즐겨찾기 음식점 조회 성공 (200)': (r) => r.status === 200 });
    return res;
}

export function getNotifications(token) {
    const res = http.get(
        `${BASE_URL}/api/v1/members/me/notifications`,
        { headers: getHeaders(token), tags: { name: 'notifications', type: 'read' } }
    );
    check(res, { '알림 목록 조회 성공 (200)': (r) => r.status === 200 });
    return res;
}

export function getUnreadNotificationsCount(token) {
    const res = http.get(
        `${BASE_URL}/api/v1/members/me/notifications/unread`,
        { headers: getHeaders(token), tags: { name: 'notifications_unread', type: 'read' } }
    );
    check(res, { '미읽 알림 수 조회 성공 (200)': (r) => r.status === 200 });
    return res;
}

export function getGroupMembers(token, groupId) {
    if (!groupId) return null;
    const res = http.get(
        `${BASE_URL}/api/v1/groups/${groupId}/members`,
        { headers: getHeaders(token), tags: { name: 'group_members', type: 'read' } }
    );
    check(res, { '그룹 멤버 조회 성공 (200)': (r) => r.status === 200 });
    return res;
}

export function getGroupReviewedRestaurants(token, groupId, loc) {
    if (!groupId) return null;
    const params = loc ? `?latitude=${loc.lat}&longitude=${loc.lon}` : '';
    const res = http.get(
        `${BASE_URL}/api/v1/groups/${groupId}/reviews/restaurants${params}`,
        { headers: getHeaders(token), tags: { name: 'group_reviewed_restaurants', type: 'read' } }
    );
    check(res, { '그룹 리뷰 음식점 조회 성공 (200)': (r) => r.status === 200 });
    return res;
}

export function getRecentSearches(token) {
    const res = http.get(
        `${BASE_URL}/api/v1/recent-searches`,
        { headers: getHeaders(token), tags: { name: 'recent_searches', type: 'read' } }
    );
    check(res, { '최근 검색어 조회 성공 (200)': (r) => r.status === 200 });
    return res;
}

export function getPromotions() {
    const res = http.get(
        `${BASE_URL}/api/v1/promotions`,
        { headers: getHeaders(), tags: { name: 'promotions', type: 'read' } }
    );
    check(res, { '프로모션 조회 성공 (200)': (r) => r.status === 200 });
    return res;
}

export function getAnnouncements() {
    const res = http.get(
        `${BASE_URL}/api/v1/announcements`,
        { headers: getHeaders(), tags: { name: 'announcements', type: 'read' } }
    );
    check(res, { '공지사항 조회 성공 (200)': (r) => r.status === 200 });
    return res;
}

// ============ Chat Functions ============

export function getChatMessages(token, chatRoomId, cursor = null) {
    if (!chatRoomId) return { response: null, messages: [], nextCursor: null };
    let url = `${BASE_URL}/api/v1/chat-rooms/${chatRoomId}/messages?size=20`;
    if (cursor) url += `&cursor=${cursor}`;
    const res = http.get(url, { headers: getHeaders(token), tags: { name: 'chat_messages', type: 'read' } });
    check(res, { '채팅 메시지 조회 성공 (200)': (r) => r.status === 200 });
    let messages = [];
    let nextCursor = null;
    if (res.status === 200) {
        try {
            messages = res.json('data.data') || [];
            nextCursor = res.json('data.page.nextCursor') || null;
        } catch (e) { /* ignore */ }
    }
    return { response: res, messages, nextCursor };
}

export function sendChatMessage(token, chatRoomId, content) {
    if (!chatRoomId) return null;
    const payload = JSON.stringify({ messageType: 'TEXT', content: content });
    const res = http.post(
        `${BASE_URL}/api/v1/chat-rooms/${chatRoomId}/messages`,
        payload,
        { headers: getHeaders(token), tags: { name: 'send_chat_message', type: 'write' } }
    );
    check(res, { '채팅 메시지 전송 성공 (200 or 201)': (r) => r.status === 200 || r.status === 201 });
    return res;
}

export function updateChatReadCursor(token, chatRoomId, lastReadMessageId) {
    if (!chatRoomId || !lastReadMessageId) return null;
    const payload = JSON.stringify({ lastReadMessageId: lastReadMessageId });
    const res = http.patch(
        `${BASE_URL}/api/v1/chat-rooms/${chatRoomId}/read-cursor`,
        payload,
        { headers: getHeaders(token), tags: { name: 'update_read_cursor', type: 'write' } }
    );
    check(res, { '읽음 커서 업데이트 성공 (200 or 204)': (r) => r.status === 200 || r.status === 204 });
    return res;
}

// ============ Subgroup Functions ============

export function getGroupSubgroups(token, groupId) {
    if (!groupId) return null;
    const res = http.get(
        `${BASE_URL}/api/v1/groups/${groupId}/subgroups?size=20`,
        { headers: getHeaders(token), tags: { name: 'group_subgroups', type: 'read' } }
    );
    check(res, { '서브그룹 목록 조회 성공 (200)': (r) => r.status === 200 });
    let items = [];
    if (res.status === 200) {
        try {
            items = res.json('data.items') || [];
        } catch (e) { /* ignore */ }
    }
    return { response: res, items };
}

export function getSubgroupDetail(token, subgroupId) {
    if (!subgroupId) return null;
    const res = http.get(
        `${BASE_URL}/api/v1/subgroups/${subgroupId}`,
        { headers: getHeaders(token), tags: { name: 'subgroup_detail', type: 'read' } }
    );
    check(res, { '서브그룹 상세 조회 성공 (200)': (r) => r.status === 200 });
    return res;
}

export function getSubgroupReviews(token, subgroupId) {
    if (!subgroupId) return null;
    const res = http.get(
        `${BASE_URL}/api/v1/subgroups/${subgroupId}/reviews`,
        { headers: getHeaders(token), tags: { name: 'subgroup_reviews', type: 'read' } }
    );
    check(res, { '서브그룹 리뷰 조회 성공 (200)': (r) => r.status === 200 });
    return res;
}

export function getSubgroupMembers(token, subgroupId) {
    if (!subgroupId) return null;
    const res = http.get(
        `${BASE_URL}/api/v1/subgroups/${subgroupId}/members`,
        { headers: getHeaders(token), tags: { name: 'subgroup_members', type: 'read' } }
    );
    check(res, { '서브그룹 멤버 조회 성공 (200)': (r) => r.status === 200 });
    return res;
}

export function getSubgroupChatRoom(token, subgroupId) {
    if (!subgroupId) return null;
    const res = http.get(
        `${BASE_URL}/api/v1/subgroups/${subgroupId}/chat-room`,
        { headers: getHeaders(token), tags: { name: 'subgroup_chat_room', type: 'read' } }
    );
    check(res, { '서브그룹 채팅방 조회 성공 (200)': (r) => r.status === 200 });
    let chatRoomId = null;
    if (res.status === 200) {
        try {
            chatRoomId = res.json('data.chatRoomId') || null;
        } catch (e) { /* ignore */ }
    }
    return { response: res, chatRoomId };
}

// ============ User Event / Write Functions ============

export function markNotificationRead(token, notifId) {
    if (!notifId) return null;
    const res = http.patch(
        `${BASE_URL}/api/v1/members/me/notifications/${notifId}`,
        null,
        { headers: getHeaders(token), tags: { name: 'mark_notification_read', type: 'write' } }
    );
    check(res, { '알림 읽음 처리 성공 (204)': (r) => r.status === 204 });
    return res;
}

export function markAllNotificationsRead(token) {
    const res = http.patch(
        `${BASE_URL}/api/v1/members/me/notifications`,
        null,
        { headers: getHeaders(token), tags: { name: 'mark_all_notifications_read', type: 'write' } }
    );
    check(res, { '모든 알림 읽음 처리 성공 (204)': (r) => r.status === 204 });
    return res;
}

export function addFavoriteRestaurant(token, restaurantId) {
    if (!restaurantId) return null;
    const payload = JSON.stringify({ restaurantId: restaurantId });
    const res = http.post(
        `${BASE_URL}/api/v1/members/me/favorites/restaurants`,
        payload,
        { headers: getHeaders(token), tags: { name: 'add_favorite', type: 'write' } }
    );
    check(res, { '즐겨찾기 추가 성공 (200/201) 또는 이미 존재 (409)': (r) => r.status === 200 || r.status === 201 || r.status === 409 });
    return res;
}

export function removeFavoriteRestaurant(token, restaurantId) {
    if (!restaurantId) return null;
    const res = http.del(
        `${BASE_URL}/api/v1/members/me/favorites/restaurants/${restaurantId}`,
        null,
        { headers: getHeaders(token), tags: { name: 'remove_favorite', type: 'write' } }
    );
    check(res, { '즐겨찾기 삭제 성공 (200 or 204)': (r) => r.status === 200 || r.status === 204 });
    return res;
}

// ============ Additional Read Functions ============

export function getNotificationPreferences(token) {
    const res = http.get(
        `${BASE_URL}/api/v1/members/me/notification-preferences`,
        { headers: getHeaders(token), tags: { name: 'notification_preferences', type: 'read' } }
    );
    check(res, { '알림 설정 조회 성공 (200)': (r) => r.status === 200 });
    return res;
}

export function getMainAiRecommend(token, lat, lon) {
    const res = http.get(
        `${BASE_URL}/api/v1/main/ai-recommend?latitude=${lat}&longitude=${lon}`,
        { headers: getHeaders(token), tags: { name: 'ai_recommend', type: 'read' } }
    );
    check(res, { 'AI 추천 조회 성공 (200)': (r) => r.status === 200 });
    return res;
}

export function getAnnouncementDetail(token, id) {
    if (!id) return null;
    const res = http.get(
        `${BASE_URL}/api/v1/announcements/${id}`,
        { headers: getHeaders(token), tags: { name: 'announcement_detail', type: 'read' } }
    );
    check(res, { '공지사항 상세 조회 성공 (200)': (r) => r.status === 200 });
    return res;
}

export function reverseGeocode(lat, lon) {
    const res = http.get(
        `${BASE_URL}/api/v1/geocode/reverse?lat=${lat}&lon=${lon}`,
        { headers: getHeaders(), tags: { name: 'reverse_geocode', type: 'read' } }
    );
    check(res, { '역지오코딩 성공 (200)': (r) => r.status === 200 });
    return res;
}

// ============ Analytics Functions ============

function generateEventId() {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
        const r = Math.random() * 16 | 0;
        return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16);
    });
}

function buildEvent(eventName, properties = {}) {
    return {
        eventId: generateEventId(),
        eventName: eventName,
        occurredAt: new Date().toISOString(),
        properties: properties,
    };
}

export function sendAnalyticsEvents(token, events) {
    if (!events || events.length === 0) return null;
    const payload = JSON.stringify({ events: events });
    const res = http.post(
        `${BASE_URL}/api/v1/analytics/events`,
        payload,
        { headers: getHeaders(token), tags: { name: 'analytics_events', type: 'write' } }
    );
    check(res, { '분석 이벤트 전송 성공 (200)': (r) => r.status === 200 });
    return res;
}

// ============ Journey Functions ============

/**
 * 브라우징 여정: 홈 → 음식 카테고리 → 음식점 목록(랜덤 위치) → 상세 → 메뉴 → 리뷰
 */
export function executeBrowsingJourney(state) {
    let successCount = 0;
    const analyticsEvents = [buildEvent('ui.tab.changed', { tab: 'home' })];

    // 0. 역지오코딩 (앱 실행 시 발생)
    const loc = randomLocation();
    const resGeo = reverseGeocode(loc.lat, loc.lon);
    if (resGeo && resGeo.status === 200) successCount++;

    // 1. 홈 페이지
    const resHome = getHomePage(state.token);
    if (resHome && resHome.status === 200) {
        successCount++;
        analyticsEvents.push(buildEvent('ui.page.viewed', { page: 'home' }));
    }

    // 2. 음식 카테고리
    const resCat = getFoodCategories();
    if (resCat && resCat.status === 200) {
        successCount++;
        analyticsEvents.push(buildEvent('ui.page.viewed', { page: 'restaurant_list' }));
    }

    // 3. 음식점 목록 (랜덤 위치/반경/페이지 크기)
    const radius = RADII[Math.floor(Math.random() * RADII.length)];
    const size = Math.floor(Math.random() * 16) + 5;
    const listResult = getRestaurantListByLocation(state.token, loc.lat, loc.lon, radius, size);
    if (listResult.response && listResult.response.status === 200) successCount++;

    const restaurantId = listResult.restaurantId || state.restaurantId;
    if (restaurantId) {
        // 4. 음식점 상세
        const resDetail = getRestaurantDetail(state.token, restaurantId);
        if (resDetail && resDetail.status === 200) {
            successCount++;
            analyticsEvents.push(buildEvent('ui.restaurant.clicked', { restaurantId }));
            analyticsEvents.push(buildEvent('ui.restaurant.viewed', { restaurantId }));
            analyticsEvents.push(buildEvent('ui.page.dwelled', {
                page: 'restaurant_detail',
                restaurantId,
                durationMs: Math.floor(Math.random() * 12000) + 3000,
            }));
        }

        // 5. 메뉴
        const resMenus = getRestaurantMenus(state.token, restaurantId);
        if (resMenus && resMenus.status === 200) successCount++;

        // 6. 리뷰
        const reviewResult = getRestaurantReviews(state.token, restaurantId);
        if (reviewResult.response && reviewResult.response.status === 200) successCount++;

        // [사용자 이벤트] 40% 확률로 즐겨찾기 toggle
        if (Math.random() < 0.4) {
            const addRes = addFavoriteRestaurant(state.token, restaurantId);
            if (addRes) {
                if (addRes.status === 409) {
                    // 이미 즐겨찾기됨 → toggle off
                    removeFavoriteRestaurant(state.token, restaurantId);
                    analyticsEvents.push(buildEvent('ui.favorite.updated', { restaurantId, action: 'remove' }));
                } else if (addRes.status === 200 || addRes.status === 201) {
                    analyticsEvents.push(buildEvent('ui.favorite.sheet_opened', { restaurantId }));
                    if (Math.random() < 0.5) {
                        removeFavoriteRestaurant(state.token, restaurantId);
                        analyticsEvents.push(buildEvent('ui.favorite.updated', { restaurantId, action: 'remove' }));
                    } else {
                        analyticsEvents.push(buildEvent('ui.favorite.updated', { restaurantId, action: 'add' }));
                    }
                }
            }
        }
    }

    sendAnalyticsEvents(state.token, analyticsEvents);
    return successCount;
}

/**
 * 검색 여정: 최근 검색어 → 랜덤 키워드 검색 1~3회 → 결과 음식점 상세
 */
export function executeSearchingJourney(state) {
    let successCount = 0;
    const analyticsEvents = [buildEvent('ui.tab.changed', { tab: 'search' })];

    // 최근 검색어 조회
    const resRecent = getRecentSearches(state.token);
    if (resRecent && resRecent.status === 200) successCount++;

    // 1~3회 랜덤 키워드 검색 (위치 포함)
    const searchCount = Math.floor(Math.random() * 3) + 1;
    let lastRestaurantId = null;
    for (let i = 0; i < searchCount; i++) {
        const keyword = randomKeyword();
        const loc = randomLocation();
        const res = search(state.token, keyword, loc);
        if (res && res.status === 200) {
            successCount++;
            analyticsEvents.push(buildEvent('ui.search.executed', { keyword, hasLocation: true }));
            if (!lastRestaurantId) {
                try {
                    const items = res.json('data.restaurants.items');
                    if (items && items.length > 0) {
                        lastRestaurantId = items[0].id;
                    }
                } catch (e) {
                    // ignore
                }
            }
        }
        if (i < searchCount - 1) sleep(0.5);
    }

    // 검색 결과 음식점 상세 조회
    if (lastRestaurantId) {
        const resDetail = getRestaurantDetail(state.token, lastRestaurantId);
        if (resDetail && resDetail.status === 200) {
            successCount++;
            analyticsEvents.push(buildEvent('ui.restaurant.clicked', { restaurantId: lastRestaurantId, source: 'search' }));
            analyticsEvents.push(buildEvent('ui.restaurant.viewed', { restaurantId: lastRestaurantId }));
        }

        // [사용자 이벤트] 20% 확률로 즐겨찾기 toggle
        if (Math.random() < 0.2) {
            const addRes = addFavoriteRestaurant(state.token, lastRestaurantId);
            if (addRes) {
                if (addRes.status === 409) {
                    // 이미 즐겨찾기됨 → toggle off
                    removeFavoriteRestaurant(state.token, lastRestaurantId);
                    analyticsEvents.push(buildEvent('ui.favorite.updated', { restaurantId: lastRestaurantId, action: 'remove' }));
                } else if (addRes.status === 200 || addRes.status === 201) {
                    analyticsEvents.push(buildEvent('ui.favorite.sheet_opened', { restaurantId: lastRestaurantId }));
                    if (Math.random() < 0.5) {
                        removeFavoriteRestaurant(state.token, lastRestaurantId);
                        analyticsEvents.push(buildEvent('ui.favorite.updated', { restaurantId: lastRestaurantId, action: 'remove' }));
                    } else {
                        analyticsEvents.push(buildEvent('ui.favorite.updated', { restaurantId: lastRestaurantId, action: 'add' }));
                    }
                }
            }
        }
    }

    sendAnalyticsEvents(state.token, analyticsEvents);
    return successCount;
}

/**
 * 그룹 여정: 그룹 상세 → 그룹 리뷰 → 그룹 멤버 → 그룹 리뷰 음식점(랜덤 위치)
 */
export function executeGroupJourney(state) {
    let successCount = 0;
    if (!state.groupId) return successCount;

    const analyticsEvents = [
        buildEvent('ui.tab.changed', { tab: 'group' }),
        buildEvent('ui.group.clicked', { groupId: state.groupId }),
    ];

    // 1. 그룹 상세
    const resGroup = getGroupDetail(state.token, state.groupId);
    if (resGroup && resGroup.status === 200) {
        successCount++;
        analyticsEvents.push(buildEvent('ui.page.viewed', { page: 'group_detail', groupId: state.groupId }));
    }

    // 2. 그룹 리뷰 목록
    const reviewResult = getGroupReviews(state.token, state.groupId);
    if (reviewResult.response && reviewResult.response.status === 200) successCount++;

    // 3. 그룹 멤버
    const resMembers = getGroupMembers(state.token, state.groupId);
    if (resMembers && resMembers.status === 200) successCount++;

    // 4. 그룹 리뷰 음식점 (랜덤 위치)
    const loc = randomLocation();
    const resReviewed = getGroupReviewedRestaurants(state.token, state.groupId, loc);
    if (resReviewed && resReviewed.status === 200) successCount++;

    // 5. 그룹 내 서브그룹 목록
    const subgroupResult = getGroupSubgroups(state.token, state.groupId);
    if (subgroupResult && subgroupResult.response && subgroupResult.response.status === 200) successCount++;

    // [사용자 이벤트] 모든 알림 읽음 처리
    markAllNotificationsRead(state.token);

    sendAnalyticsEvents(state.token, analyticsEvents);
    return successCount;
}

/**
 * 개인 여정: 내 프로필 → 내 리뷰 → 알림 → 즐겨찾기 → 내 그룹
 */
export function executePersonalJourney(state) {
    let successCount = 0;
    const analyticsEvents = [
        buildEvent('ui.tab.changed', { tab: 'profile' }),
        buildEvent('ui.page.viewed', { page: 'profile' }),
    ];

    // 1. 내 프로필
    const resProfile = getMyProfile(state.token);
    if (resProfile && resProfile.status === 200) successCount++;

    // 2. 내 리뷰
    const resReviews = getMyReviews(state.token);
    if (resReviews && resReviews.status === 200) successCount++;

    // 3. 알림
    const resNotif = getNotifications(state.token);
    let notifId = null;
    if (resNotif && resNotif.status === 200) {
        successCount++;
        analyticsEvents.push(buildEvent('ui.page.viewed', { page: 'notifications' }));
        try {
            const items = resNotif.json('data.items');
            if (items && items.length > 0) {
                notifId = items[0].id;
            }
        } catch (e) { /* ignore */ }
    }

    // 4. 미읽 알림 수
    const resUnread = getUnreadNotificationsCount(state.token);
    if (resUnread && resUnread.status === 200) successCount++;

    // 5. 즐겨찾기 음식점
    const resFavs = getMyFavoriteRestaurants(state.token);
    if (resFavs && resFavs.status === 200) {
        successCount++;
        analyticsEvents.push(buildEvent('ui.page.viewed', { page: 'favorites' }));
    }

    // 6. 내 그룹
    const resGroups = getMyGroups(state.token);
    if (resGroups && resGroups.status === 200) successCount++;

    // 7. 내 그룹 요약
    const resSummary = getMyGroupsSummary(state.token);
    if (resSummary && resSummary.status === 200) successCount++;

    // 8. 알림 설정 조회
    const resNotifPref = getNotificationPreferences(state.token);
    if (resNotifPref && resNotifPref.status === 200) successCount++;

    // [사용자 이벤트] 알림 읽음 처리 (notifId 있으면)
    markNotificationRead(state.token, notifId);

    sendAnalyticsEvents(state.token, analyticsEvents);
    return successCount;
}

/**
 * 쓰기 여정: 프로모션 확인 → 리뷰 키워드 조회 → 리뷰 작성
 */
export function executeWritingJourney(state) {
    let successCount = 0;
    const analyticsEvents = [
        buildEvent('ui.page.viewed', { page: 'review_write' }),
        buildEvent('ui.review.write_started', { restaurantId: TEST_RESTAURANT_ID }),
    ];

    // AI 추천 확인 (리뷰 작성 전)
    const loc = randomLocation();
    const resAiRec = getMainAiRecommend(state.token, loc.lat, loc.lon);
    if (resAiRec && resAiRec.status === 200) successCount++;

    // 프로모션 확인 (쓰기 전 일반적인 앱 탐색)
    const resPromo = getPromotions();
    if (resPromo && resPromo.status === 200) successCount++;

    // 리뷰 키워드 조회
    const keywordIds = (state.keywordIds && state.keywordIds.length > 0)
        ? state.keywordIds
        : getReviewKeywords(state.token);

    // 리뷰 작성
    const res = createReview(state.token, state.groupId, keywordIds);
    if (res && (res.status === 200 || res.status === 201)) {
        successCount++;
        analyticsEvents.push(buildEvent('ui.review.submitted', { restaurantId: TEST_RESTAURANT_ID }));
    }

    sendAnalyticsEvents(state.token, analyticsEvents);
    return successCount;
}

/**
 * 서브그룹 여정: 서브그룹 목록 → 상세 → 멤버 → 리뷰 → 채팅방 → 메시지 → 읽음커서
 */
export function executeSubgroupJourney(state) {
    let successCount = 0;
    if (!state.groupId) return successCount;

    const analyticsEvents = [];

    // 1. 서브그룹 목록
    const subgroupResult = getGroupSubgroups(state.token, state.groupId);
    if (subgroupResult && subgroupResult.response && subgroupResult.response.status === 200) successCount++;

    // subgroupId 추출 (state 우선, 없으면 결과에서)
    let subgroupId = state.subgroupId;
    if (!subgroupId && subgroupResult && subgroupResult.items && subgroupResult.items.length > 0) {
        subgroupId = subgroupResult.items[0].subgroupId;
    }
    if (!subgroupId) return successCount;

    // 2. 서브그룹 상세
    const resDetail = getSubgroupDetail(state.token, subgroupId);
    if (resDetail && resDetail.status === 200) {
        successCount++;
        analyticsEvents.push(buildEvent('ui.page.viewed', { page: 'subgroup_detail', subgroupId }));
    }

    // 3. 서브그룹 멤버
    const resMembers = getSubgroupMembers(state.token, subgroupId);
    if (resMembers && resMembers.status === 200) successCount++;

    // 4. 서브그룹 리뷰
    const resReviews = getSubgroupReviews(state.token, subgroupId);
    if (resReviews && resReviews.status === 200) successCount++;

    // 5. 서브그룹 채팅방
    const chatRoomResult = getSubgroupChatRoom(state.token, subgroupId);
    if (chatRoomResult && chatRoomResult.response && chatRoomResult.response.status === 200) successCount++;

    const chatRoomId = (chatRoomResult && chatRoomResult.chatRoomId) || state.chatRoomId;
    if (!chatRoomId) {
        sendAnalyticsEvents(state.token, analyticsEvents);
        return successCount;
    }

    analyticsEvents.push(buildEvent('ui.page.viewed', { page: 'chat', chatRoomId, subgroupId }));

    // 6. 채팅 메시지
    const msgResult = getChatMessages(state.token, chatRoomId);
    if (msgResult && msgResult.response && msgResult.response.status === 200) successCount++;

    const lastMessageId = (msgResult.messages && msgResult.messages.length > 0)
        ? msgResult.messages[msgResult.messages.length - 1].id
        : null;

    // [사용자 이벤트] 읽음 커서 업데이트
    if (lastMessageId) {
        updateChatReadCursor(state.token, chatRoomId, lastMessageId);
    }

    sendAnalyticsEvents(state.token, analyticsEvents);
    return successCount;
}

/**
 * 채팅 여정: 메시지 조회(페이지네이션) → 메시지 전송 → 읽음커서 업데이트
 */
export function executeChatJourney(state) {
    let successCount = 0;
    const analyticsEvents = [];

    // chatRoomId 확인 (state 우선)
    let chatRoomId = state.chatRoomId;
    if (!chatRoomId && state.subgroupId) {
        const chatRoomResult = getSubgroupChatRoom(state.token, state.subgroupId);
        if (chatRoomResult && chatRoomResult.response && chatRoomResult.response.status === 200) {
            successCount++;
            chatRoomId = chatRoomResult.chatRoomId;
        }
    }
    if (!chatRoomId) return successCount;

    analyticsEvents.push(buildEvent('ui.page.viewed', { page: 'chat', chatRoomId }));

    // 1. 채팅 메시지 조회
    const msgResult = getChatMessages(state.token, chatRoomId);
    if (msgResult && msgResult.response && msgResult.response.status === 200) successCount++;

    let lastMessageId = null;
    if (msgResult.messages && msgResult.messages.length > 0) {
        lastMessageId = msgResult.messages[msgResult.messages.length - 1].id;
    }

    // 2. 다음 페이지 (cursor 있으면)
    if (msgResult.nextCursor) {
        const nextMsgResult = getChatMessages(state.token, chatRoomId, msgResult.nextCursor);
        if (nextMsgResult && nextMsgResult.response && nextMsgResult.response.status === 200) successCount++;
        if (nextMsgResult.messages && nextMsgResult.messages.length > 0) {
            lastMessageId = nextMsgResult.messages[nextMsgResult.messages.length - 1].id;
        }
    }

    analyticsEvents.push(buildEvent('ui.page.dwelled', {
        page: 'chat',
        chatRoomId,
        durationMs: Math.floor(Math.random() * 30000) + 5000,
    }));

    // 3. 메시지 전송 [write]
    const content = randomChatMessage();
    const resSend = sendChatMessage(state.token, chatRoomId, content);
    if (resSend && (resSend.status === 200 || resSend.status === 201)) successCount++;

    // 4. 읽음 커서 업데이트 [write]
    if (lastMessageId) {
        updateChatReadCursor(state.token, chatRoomId, lastMessageId);
    }

    sendAnalyticsEvents(state.token, analyticsEvents);
    return successCount;
}
