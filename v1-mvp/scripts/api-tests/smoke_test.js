import http from 'k6/http';
import { check, sleep, group } from 'k6';

export const options = {
    vus: 1, // 스모크 테스트를 위한 1명의 가상 유저
    duration: '10s', // 연결성 확인을 위한 짧은 시간
};

const BASE_URL = 'https://tasteam.kr';

export default function () {
    // 공통 헤더 설정
    const params = {
        headers: {
            'Content-Type': 'application/json',
        },
    };

    let authParams = { ...params }; // 인증 토큰이 포함될 헤더

    // 동적으로 추출할 ID들
    let restaurantId = null;
    let groupId = null;

    let reviewId = null;
    let keywordIds = []; // 리뷰 키워드 ID 목록

    // 1. 로그인 (테스트용 백도어 API)
    group('로그인', function () {
        const loginPayload = JSON.stringify({
            identifier: 'test-user-001',
            nickname: '스모크테스트계정1'
        });

        const res = http.post(`${BASE_URL}/api/v1/auth/token/test`, loginPayload, params);

        console.log(`[로그인] Status: ${res.status}, Body: ${res.body}`);

        check(res, {
            '로그인 성공 (200)': (r) => r.status === 200,
        });

        if (res.status === 200) {
            const token = res.json('data.accessToken'); // data 안에 있을 수 있음
            authParams.headers['Authorization'] = `Bearer ${token}`;
            console.log(`[로그인] 토큰 설정됨: ${token ? '성공' : '실패'}`);
        }
    });

    sleep(1);

    // 2. 그룹 가입 (비밀번호 인증)
    group('그룹 가입', function () {
        const targetGroupId = 2002;
        const joinPayload = JSON.stringify({
            code: 'LOCAL-1234'
        });

        const res = http.post(`${BASE_URL}/api/v1/groups/${targetGroupId}/password-authentications`, joinPayload, authParams);

        console.log(`[그룹 가입] Status: ${res.status}, Body: ${res.body}`);

        check(res, {
            '그룹 가입 성공 (201)': (r) => r.status === 201,
        });

        if (res.status === 201) {
            groupId = targetGroupId;
            console.log(`[그룹 가입] 그룹 ${groupId} 가입 완료`);
        }
    });

    sleep(1);

    // 리뷰 키워드 목록 조회
    group('리뷰 키워드 목록 조회', function () {
        const res = http.get(`${BASE_URL}/api/v1/reviews/keywords`, authParams);
        console.log(`[리뷰 키워드 조회] Status: ${res.status}`);
        check(res, {
            '리뷰 키워드 목록 조회 성공 (200)': (r) => r.status === 200,
        });

        if (res.status === 200) {
            try {
                const data = res.json('data');
                if (data && data.length > 0) {
                    keywordIds = data.map(k => k.id);
                    console.log(`[리뷰 키워드 조회] 조회된 키워드 수: ${keywordIds.length}`);
                }
            } catch (e) {
                console.log(`[리뷰 키워드 조회] JSON 파싱 실패: ${e}`);
            }
        }
    });

    sleep(1);

    // 2. 읽기 API 테스트

    // 메인 페이지 진입
    group('메인 페이지', function () {
        const res = http.get(`${BASE_URL}/api/v1/main?latitude=37.395&longitude=127.11`, authParams);
        check(res, {
            '메인 페이지 조회 성공 (200)': (r) => r.status === 200,
        });
    });

    // 음식점 목록 조회 + 첫 번째 ID 추출
    group('음식점 목록 조회', function () {
        const res = http.get(`${BASE_URL}/api/v1/restaurants?latitude=37.395&longitude=127.11`, authParams);
        check(res, {
            '음식점 목록 조회 성공 (200)': (r) => r.status === 200,
        });

        // 목록에서 첫 번째 음식점 ID 추출
        if (res.status === 200) {
            try {
                const items = res.json('data.items');
                if (items && items.length > 0) {
                    restaurantId = items[0].id;
                    console.log(`[음식점 목록] 첫 번째 음식점 ID: ${restaurantId}`);
                } else {
                    console.log('[음식점 목록] 데이터 없음 - 단건 조회 스킵됨');
                }
            } catch (e) {
                console.log(`[음식점 목록] JSON 파싱 실패: ${e}`);
            }
        }
    });

    // 음식점 단건 조회 (동적 ID 사용)
    group('음식점 단건 조회', function () {
        if (!restaurantId) {
            console.log('[음식점 단건 조회] 스킵 - 음식점 ID 없음');
            return;
        }
        const res = http.get(`${BASE_URL}/api/v1/restaurants/${restaurantId}`, authParams);
        console.log(`[음식점 단건 조회] Status: ${res.status}, Body: ${res.body}`);
        check(res, {
            '음식점 단건 조회 성공 (200)': (r) => r.status === 200,
        });
    });

    // 음식점 리뷰 목록 조회 (동적 ID 사용)
    group('음식점 리뷰 목록 조회', function () {
        if (!restaurantId) {
            console.log('[음식점 리뷰 목록 조회] 스킵 - 음식점 ID 없음');
            return;
        }
        const res = http.get(`${BASE_URL}/api/v1/restaurants/${restaurantId}/reviews`, authParams);
        console.log(`[음식점 리뷰 목록 조회] Status: ${res.status}, Body: ${res.body}`);
        check(res, {
            '음식점 리뷰 목록 조회 성공 (200)': (r) => r.status === 200,
        });

        // 리뷰 목록에서 첫 번째 리뷰 ID 추출
        if (res.status === 200) {
            try {
                const items = res.json('data.items');
                if (items && items.length > 0) {
                    reviewId = items[0].id;
                    console.log(`[음식점 리뷰 목록] 첫 번째 리뷰 ID: ${reviewId}`);
                }
            } catch (e) {
                // 리뷰가 없을 수 있음
            }
        }
    });

    // 그룹 상세 조회 (가입한 그룹 사용)
    group('그룹 상세 조회', function () {
        if (!groupId) {
            console.log('[그룹 상세 조회] 스킵 - 그룹 가입 안됨');
            return;
        }
        const res = http.get(`${BASE_URL}/api/v1/groups/${groupId}`, authParams);
        console.log(`[그룹 상세 조회] Status: ${res.status}`);
        check(res, {
            '그룹 상세 조회 성공 (200)': (r) => r.status === 200,
        });


    });

    // 그룹 리뷰 목록 조회 (동적 ID 사용)
    group('그룹 리뷰 목록 조회', function () {
        if (!groupId) {
            console.log('[그룹 리뷰 목록 조회] 스킵 - 그룹 ID 없음');
            return;
        }
        const res = http.get(`${BASE_URL}/api/v1/groups/${groupId}/reviews`, authParams);
        check(res, {
            '그룹 리뷰 목록 조회 성공 (200)': (r) => r.status === 200,
        });

        // 리뷰 ID 추출 (아직 없으면)
        if (res.status === 200 && !reviewId) {
            try {
                const items = res.json('data.items');
                if (items && items.length > 0) {
                    reviewId = items[0].id;
                    console.log(`[그룹 리뷰 목록] 첫 번째 리뷰 ID: ${reviewId}`);
                }
            } catch (e) {
                // 리뷰가 없을 수 있음
            }
        }
    });



    // 리뷰 단건 조회 (동적 ID 사용)
    group('리뷰 단건 조회', function () {
        if (!reviewId) {
            console.log('[리뷰 단건 조회] 스킵 - 리뷰 ID 없음');
            return;
        }
        const res = http.get(`${BASE_URL}/api/v1/reviews/${reviewId}`, authParams);
        console.log(`[리뷰 단건 조회] Status: ${res.status}, Body: ${res.body}`);
        check(res, {
            '리뷰 단건 조회 성공 (200)': (r) => r.status === 200,
        });
    });

    // // 그룹 리뷰된 음식점 거리순 조회 (동적 ID 사용)
    // group('그룹 리뷰된 음식점 거리순 조회', function () {
    //     if (!groupId) {
    //         console.log('[그룹 리뷰된 음식점 거리순 조회] 스킵 - 그룹 ID 없음');
    //         return;
    //     }
    //     const res = http.get(`${BASE_URL}/api/v1/groups/${groupId}/reviews/restaurants?latitude=37.395&longitude=127.11`, authParams);
    //     console.log(`[그룹 리뷰된 음식점 거리순 조회] Status: ${res.status}, Body: ${res.body}`);
    //     check(res, {
    //         '그룹 리뷰된 음식점 거리순 조회 성공 (200)': (r) => r.status === 200,
    //     });
    // });

    // 통합 검색 (POST + query string)
    group('통합 검색', function () {
        const res = http.post(`${BASE_URL}/api/v1/search?keyword=test`, null, authParams);
        console.log(`[통합 검색] Status: ${res.status}, Body: ${res.body}`);
        check(res, {
            '통합 검색 성공 (200)': (r) => r.status === 200,
        });
    });

    sleep(1);

    // 3. 쓰기 API 테스트

    // 음식점 리뷰 작성
    // 주의: 실제 DB에 데이터가 쌓이므로 테스트 DB 등에서 수행 권장
    group('음식점 리뷰 작성', function () {
        // groupId가 필요하므로 앞서 추출한 groupId 사용 (없으면 1 사용)
        const targetRestaurantId = 6001;
        const targetGroupId = groupId || 1;

        // 조회된 키워드 중 첫 번째 사용 (없으면 기본값 1)
        const selectedKeywordIds = keywordIds.length > 0 ? [keywordIds[0]] : [1];
        console.log(`[음식점 리뷰 작성] 선택된 키워드 ID: ${selectedKeywordIds[0]}`);

        const reviewPayload = JSON.stringify({
            content: '스모크 테스트용 리뷰입니다.',
            groupId: targetGroupId,
            keywordIds: selectedKeywordIds,
            isRecommended: true,
        });

        // 400 에러 등을 방지하기 위해 payload 구조 확인 필요
        const res = http.post(`${BASE_URL}/api/v1/restaurants/${targetRestaurantId}/reviews`, reviewPayload, authParams);
        console.log(`[음식점 리뷰 작성] Status: ${res.status}, Body: ${res.body}`);

        check(res, {
            '리뷰 작성 성공 (201 or 200)': (r) => r.status === 201 || r.status === 200,
        });
    });

    sleep(1);
}

