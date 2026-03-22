import http from 'k6/http';
import { check } from 'k6';

// ============ Configuration ============
export const BASE_URL = __ENV.BASE_URL || 'https://api.tasteam.kr';

const TEST_GROUP = {
    id: parsePositiveIntEnv('TEST_GROUP_ID', 1),
    code: __ENV.TEST_GROUP_CODE || '9999',
};
const TEST_RESTAURANT_ID = __ENV.TEST_RESTAURANT_ID || '93394631623941'; // 자연산산꼼장어

const GROUP_SEARCH_KEYWORDS = parseCsvEnv('GROUP_SEARCH_KEYWORDS').length > 0
    ? parseCsvEnv('GROUP_SEARCH_KEYWORDS')
    : ['테스트'];
const GROUP_SEARCH_LIMIT = parsePositiveIntEnv('GROUP_SEARCH_LIMIT', 10);

// ============ Env Parsers ============
function parsePositiveIntEnv(name, fallback) {
    const raw = __ENV[name];
    if (!raw) return fallback;
    const parsed = Number(raw);
    return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback;
}

function parsePositiveNumberListEnv(name, fallback) {
    const raw = __ENV[name];
    if (!raw) return fallback;
    const parsed = raw
        .split(',')
        .map((v) => Number(v.trim()))
        .filter((v) => Number.isFinite(v) && v > 0);
    return parsed.length > 0 ? parsed : fallback;
}

function parseCsvEnv(name) {
    const raw = __ENV[name];
    if (!raw) return [];
    return raw
        .split(',')
        .map((v) => v.trim())
        .filter((v) => v.length > 0)
        .map((v) => (String(Number(v)) === v ? Number(v) : v));
}

// ============ Common ============
function getHeaders(token = null) {
    const headers = { 'Content-Type': 'application/json' };
    if (token) headers['Authorization'] = `Bearer ${token}`;
    return headers;
}

function uniqueList(list) {
    return Array.from(new Set((list || []).filter((v) => v !== null && v !== undefined)));
}

function extractListFromResponse(res, paths = ['data.items', 'data']) {
    if (!res || res.status !== 200) return [];
    for (const path of paths) {
        try {
            const value = res.json(path);
            if (Array.isArray(value)) return value;
        } catch (e) { /* ignore */ }
    }
    return [];
}

export function createState() {
    return {
        token: null,
        groupId: null,
        subgroupId: null,
        chatRoomId: null,
        restaurantId: null,
        reviewId: null,
        keywordIds: [],
        hotspot: null,
    };
}

// ============ Auth ============
export function getTestUser(index) {
    return {
        identifier: `test-user-${String(index).padStart(3, '0')}`,
        nickname: `부하테스트계정${index}`,
    };
}

// ============ Read Scenarios ============
export function getReviewKeywords(token) {
    const res = http.get(
        `${BASE_URL}/api/v1/reviews/keywords`,
        { headers: getHeaders(token) },
    );
    check(res, { '리뷰 키워드 조회 성공 (200)': (r) => r.status === 200 });
    if (res.status === 200) {
        try {
            const data = res.json('data');
            if (data && data.length > 0) return data.map((k) => k.id);
        } catch (e) { /* ignore */ }
    }
    return [1];
}

export function getHomePage(token, lat = null, lon = null) {
    const loc = (lat !== null && lon !== null) ? { lat, lon } : randomLocation();
    const res = http.get(
        `${BASE_URL}/api/v1/main/home?latitude=${loc.lat}&longitude=${loc.lon}`,
        { headers: getHeaders(token), tags: { name: 'home_page', type: 'read' } },
    );
    check(res, { '홈 페이지 조회 성공 (200)': (r) => r.status === 200 });
    return res;
}

export function getRestaurantDetail(token, restaurantId) {
    if (!restaurantId) return null;
    const res = http.get(
        `${BASE_URL}/api/v1/restaurants/${restaurantId}`,
        { headers: getHeaders(token), tags: { name: 'restaurant_detail', type: 'read' } },
    );
    check(res, { '음식점 상세 조회 성공 (200)': (r) => r.status === 200 });
    return res;
}

export function getGroupDetail(token, groupId) {
    if (!groupId) return null;
    const res = http.get(
        `${BASE_URL}/api/v1/groups/${groupId}`,
        { headers: getHeaders(token), tags: { name: 'group_detail', type: 'read' } },
    );
    check(res, { '그룹 상세 조회 성공 (200)': (r) => r.status === 200 });
    return res;
}

export function search(token, keyword = 'test', loc = null, radiusKm = null) {
    let url = `${BASE_URL}/api/v1/search?keyword=${encodeURIComponent(keyword)}`;
    if (loc) {
        const resolvedRadiusKm = radiusKm || randomSearchRadiusKm();
        url += `&latitude=${loc.lat}&longitude=${loc.lon}&radiusKm=${resolvedRadiusKm}`;
    }
    const res = http.post(url, null, {
        headers: getHeaders(token),
        tags: { name: 'search', type: 'read' },
    });
    check(res, { '통합 검색 성공 (200)': (r) => r.status === 200 });
    return res;
}

function getMyGroups(token) {
    const res = http.get(
        `${BASE_URL}/api/v1/members/me/groups`,
        { headers: getHeaders(token), tags: { name: 'my_groups', type: 'read' } },
    );
    check(res, { '내 그룹 목록 조회 성공 (200)': (r) => r.status === 200 });
    return res;
}

function searchGroups(token, keyword) {
    const res = http.post(
        `${BASE_URL}/api/v1/search?keyword=${encodeURIComponent(keyword)}`,
        null,
        { headers: getHeaders(token), tags: { name: 'group_search', type: 'read' } },
    );
    check(res, { '그룹 검색 성공 (200)': (r) => r.status === 200 });
    return res;
}

// ============ Write Scenarios ============
export function createReview(token, groupId, keywordIds, restaurantId = null) {
    if (!groupId || !restaurantId) return null;
    const selectedKeywordIds = keywordIds && keywordIds.length > 0 ? [keywordIds[0]] : [1];
    const payload = JSON.stringify({
        content: `브레이크포인트 테스트 리뷰 - ${Date.now()}`,
        groupId,
        keywordIds: selectedKeywordIds,
        isRecommended: true,
    });
    const res = http.post(
        `${BASE_URL}/api/v1/restaurants/${restaurantId}/reviews`,
        payload,
        { headers: getHeaders(token), tags: { name: 'create_review', type: 'write' } },
    );
    check(res, { '리뷰 작성 성공 (201 or 200)': (r) => r.status === 201 || r.status === 200 });
    return res;
}

// ============ Group Context ============
function joinGroupById(token, groupId, code = TEST_GROUP.code) {
    if (!groupId) return null;
    const res = http.post(
        `${BASE_URL}/api/v1/groups/${groupId}/password-authentications`,
        JSON.stringify({ code }),
        { headers: getHeaders(token), responseCallback: http.expectedStatuses({ min: 200, max: 499 }) },
    );
    return res.status === 201 ? groupId : null;
}

function extractSearchGroupIds(res) {
    if (!res || res.status !== 200) return [];
    try {
        const groups = res.json('data.groups');
        if (!Array.isArray(groups)) return [];
        return groups.map((item) => item && (item.groupId || item.id)).filter(Boolean);
    } catch (e) { return []; }
}

function findGroupCandidates(token) {
    const candidates = [];
    const keywords = uniqueList(GROUP_SEARCH_KEYWORDS).slice(0, GROUP_SEARCH_LIMIT);
    keywords.forEach((keyword) => {
        extractSearchGroupIds(searchGroups(token, keyword)).forEach((groupId) => {
            if (!candidates.includes(groupId)) candidates.push(groupId);
        });
    });
    return candidates.slice(0, GROUP_SEARCH_LIMIT);
}

export function resolveGroupContext(token, { allowJoin = true } = {}) {
    const res = getMyGroups(token);
    const items = extractListFromResponse(res);
    const groupIds = items.map((item) => item && (item.id || item.groupId)).filter(Boolean);

    if (groupIds.length > 0) {
        return { response: res, items, groupId: groupIds[0], groupIds, source: 'my-groups' };
    }
    if (!allowJoin) {
        return { response: res, items, groupId: null, groupIds: [], source: 'none' };
    }
    const fixedGroupId = joinGroupById(token, TEST_GROUP.id, TEST_GROUP.code);
    if (fixedGroupId) {
        return { response: res, items, groupId: fixedGroupId, groupIds: [fixedGroupId], source: 'fixed-group' };
    }
    const candidateGroupIds = findGroupCandidates(token);
    for (const cid of candidateGroupIds) {
        const joined = joinGroupById(token, cid, TEST_GROUP.code);
        if (joined) {
            return { response: res, items, groupId: joined, groupIds: [joined], source: 'group-search' };
        }
    }
    return { response: res, items, groupId: null, groupIds: [], source: 'none' };
}

// ============ Restaurant ID Extraction ============
function collectRestaurantIdsFromItems(items, collector) {
    if (!Array.isArray(items)) return;
    items.forEach((item) => {
        const restaurantId = item && (item.restaurantId || item.id);
        if (restaurantId) collector.add(restaurantId);
    });
}

export function extractRestaurantIdsFromSectionsResponse(res) {
    if (!res || res.status !== 200) return [];
    const collector = new Set();
    try {
        const sections = res.json('data.sections') || [];
        sections.forEach((section) => collectRestaurantIdsFromItems(section && section.items, collector));
    } catch (e) { /* ignore */ }
    return Array.from(collector);
}

export function pickRandomRestaurantId(ids) {
    if (!ids || ids.length === 0) return null;
    return ids[Math.floor(Math.random() * ids.length)];
}

export function pickRestaurantId(state, fallbackId = null) {
    if (fallbackId) return fallbackId;
    if (state && state.restaurantId) return state.restaurantId;
    return TEST_RESTAURANT_ID || null;
}

// ============ Search Data ============
const LOCATIONS = [
    { lat: 37.5665, lon: 126.9780 },
    { lat: 37.4979, lon: 127.0276 },
    { lat: 37.5563, lon: 126.9723 },
    { lat: 37.5519, lon: 126.9918 },
    { lat: 37.5172, lon: 127.0473 },
    { lat: 37.5144, lon: 127.1050 },
    { lat: 37.5796, lon: 126.9770 },
    { lat: 37.5443, lon: 127.0557 },
    { lat: 37.5600, lon: 127.0369 },
    { lat: 37.5172, lon: 127.0391 },
    { lat: 37.5326, lon: 126.9003 },
    { lat: 37.5400, lon: 127.0695 },
    { lat: 37.5779, lon: 126.9849 },
    { lat: 37.5174, lon: 127.0272 },
    { lat: 37.5229, lon: 127.0247 },
    { lat: 37.5483, lon: 126.9164 },
    { lat: 37.5838, lon: 127.0021 },
    { lat: 37.5506, lon: 126.9217 },
    { lat: 37.5591, lon: 126.9264 },
    { lat: 37.5670, lon: 126.9852 },
];

const SEARCH_KEYWORDS = [
    '파스타', '피자', '치킨', '초밥', '스시', '버거', '카페', '디저트',
    '삼겹살', '쌀국수', '라멘', '곱창', '갈비', '샐러드', '브런치', '한식',
    '비건', '스테이크', '떡볶이', '칼국수', '냉면', '짜장면', '짬뽕', '마라탕',
    '훠궈', '돈까스', '우동', '규카츠', '오마카세', '족발', '보쌈', '순대국',
    '감자탕', '닭갈비', '김치찌개', '부대찌개', '순두부', '비빔밥', '덮밥', '돈부리',
    '강남맛집', '홍대맛집', '성수맛집', '여의도맛집', '종로맛집', '명동맛집', '잠실맛집',
    '점심맛집', '저녁맛집', '회식장소', '데이트맛집', '혼밥맛집', '가성비맛집',
];

const SEARCH_VARIATION_CONFIG = {
    radiusKm: parsePositiveNumberListEnv('SEARCH_RADIUS_KM', [0.4, 0.8, 1.5, 3.0]),
    locationOffsets: parsePositiveNumberListEnv('SEARCH_LOCATION_OFFSETS', [0.004, 0.012])
        .flatMap((offset) => [-offset, offset]),
};

function buildSearchLocationCatalog() {
    const catalog = [];
    LOCATIONS.forEach((base) => {
        SEARCH_VARIATION_CONFIG.locationOffsets.forEach((latOffset) => {
            SEARCH_VARIATION_CONFIG.locationOffsets.forEach((lonOffset) => {
                catalog.push({
                    lat: Number((base.lat + latOffset).toFixed(4)),
                    lon: Number((base.lon + lonOffset).toFixed(4)),
                });
            });
        });
    });
    return catalog;
}

const SEARCH_LOCATIONS = buildSearchLocationCatalog();

export function randomLocation() {
    const base = LOCATIONS[Math.floor(Math.random() * LOCATIONS.length)];
    return {
        lat: base.lat + (Math.random() - 0.5) * 0.02,
        lon: base.lon + (Math.random() - 0.5) * 0.02,
    };
}

export function randomSearchLocation() {
    return SEARCH_LOCATIONS[Math.floor(Math.random() * SEARCH_LOCATIONS.length)];
}

export function randomSearchRadiusKm() {
    return SEARCH_VARIATION_CONFIG.radiusKm[Math.floor(Math.random() * SEARCH_VARIATION_CONFIG.radiusKm.length)];
}

export function pickKeyword() {
    return SEARCH_KEYWORDS[Math.floor(Math.random() * SEARCH_KEYWORDS.length)];
}
