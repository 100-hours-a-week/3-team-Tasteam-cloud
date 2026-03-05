import os
import random
import time
from locust import HttpUser, task, between

BASE_URL = os.getenv("BASE_URL", "https://dev.tasteam.kr")
USER_ID_MAX = int(os.getenv("USER_ID_MAX", "1000"))

SEARCH_KEYWORDS = ["파스타", "치킨", "피자", "카페", "강남", "성수", "점심", "회식", "가성비"]


class TasteamUser(HttpUser):
    host = BASE_URL
    wait_time = between(1, 5)

    def on_start(self):
        self.token = None
        self.group_id = None
        self.subgroup_id = None
        self.chat_room_id = None
        self.restaurant_id = 6001

        uid = random.randint(1, USER_ID_MAX)
        login_body = {
            "identifier": f"test-user-{uid:03d}",
            "nickname": f"부하테스트계정{uid}",
        }

        with self.client.post("/api/v1/auth/token/test", json=login_body, name="auth/token/test", catch_response=True) as res:
            if res.status_code == 200:
                try:
                    self.token = res.json().get("data", {}).get("accessToken")
                    if self.token:
                        res.success()
                    else:
                        res.failure("accessToken missing")
                except Exception as exc:
                    res.failure(f"token parse failed: {exc}")
            else:
                res.failure(f"login failed: {res.status_code}")

        if not self.token:
            return

        headers = self._auth_headers()
        self._ensure_group_context(headers)

    def _auth_headers(self):
        return {
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json",
        }

    def _ensure_group_context(self, headers):
        r = self.client.get("/api/v1/members/me/groups", headers=headers, name="members/me/groups")
        if r.status_code == 200:
            try:
                items = r.json().get("data", {}).get("items", [])
                if items:
                    self.group_id = items[0].get("id")
            except Exception:
                pass

        if not self.group_id:
            join_body = {"code": "LOCAL-1234"}
            j = self.client.post("/api/v1/groups/2002/password-authentications", json=join_body, headers=headers, name="groups/join")
            if j.status_code == 201:
                self.group_id = 2002

        if not self.group_id:
            return

        sg = self.client.get(f"/api/v1/groups/{self.group_id}/subgroups?size=20", headers=headers, name="groups/subgroups")
        if sg.status_code == 200:
            try:
                items = sg.json().get("data", {}).get("items", [])
                if items:
                    self.subgroup_id = items[0].get("subgroupId")
            except Exception:
                pass

        if self.subgroup_id:
            cr = self.client.get(f"/api/v1/subgroups/{self.subgroup_id}/chat-room", headers=headers, name="subgroups/chat-room")
            if cr.status_code == 200:
                try:
                    self.chat_room_id = cr.json().get("data", {}).get("chatRoomId")
                except Exception:
                    pass

    @task(28)
    def browsing_journey(self):
        if not self.token:
            return
        h = self._auth_headers()
        self.client.get("/api/v1/main/home?latitude=37.4979&longitude=127.0276", headers=h, name="journey:browsing/main_home")
        r = self.client.get("/api/v1/restaurants?latitude=37.4979&longitude=127.0276", headers=h, name="journey:browsing/restaurants")
        rid = self.restaurant_id
        if r.status_code == 200:
            try:
                items = r.json().get("data", {}).get("items", [])
                if items:
                    rid = random.choice(items).get("id", rid)
            except Exception:
                pass
        self.client.get(f"/api/v1/restaurants/{rid}", headers=h, name="journey:browsing/restaurant_detail")
        self.client.get(f"/api/v1/restaurants/{rid}/menus", headers=h, name="journey:browsing/restaurant_menus")
        self.client.get(f"/api/v1/restaurants/{rid}/reviews", headers=h, name="journey:browsing/restaurant_reviews")

    @task(18)
    def searching_journey(self):
        if not self.token:
            return
        h = self._auth_headers()
        keyword = random.choice(SEARCH_KEYWORDS)
        self.client.post(f"/api/v1/search?keyword={keyword}", headers=h, name="journey:searching/search")
        self.client.get(f"/api/v1/restaurants/{self.restaurant_id}", headers=h, name="journey:searching/restaurant_detail")

    @task(12)
    def group_journey(self):
        if not self.token or not self.group_id:
            return
        h = self._auth_headers()
        self.client.get(f"/api/v1/groups/{self.group_id}", headers=h, name="journey:group/detail")
        self.client.get(f"/api/v1/groups/{self.group_id}/members", headers=h, name="journey:group/members")
        self.client.get(f"/api/v1/groups/{self.group_id}/reviews", headers=h, name="journey:group/reviews")

    @task(12)
    def subgroup_journey(self):
        if not self.token or not self.subgroup_id:
            return
        h = self._auth_headers()
        self.client.get(f"/api/v1/subgroups/{self.subgroup_id}", headers=h, name="journey:subgroup/detail")
        self.client.get(f"/api/v1/subgroups/{self.subgroup_id}/members", headers=h, name="journey:subgroup/members")
        self.client.get(f"/api/v1/subgroups/{self.subgroup_id}/reviews", headers=h, name="journey:subgroup/reviews")

    @task(12)
    def personal_journey(self):
        if not self.token:
            return
        h = self._auth_headers()
        self.client.get("/api/v1/members/me", headers=h, name="journey:personal/me")
        self.client.get("/api/v1/members/me/groups", headers=h, name="journey:personal/groups")
        self.client.get("/api/v1/members/me/favorites/restaurants", headers=h, name="journey:personal/favorites")
        self.client.get("/api/v1/members/me/notifications", headers=h, name="journey:personal/notifications")

    @task(10)
    def chat_journey(self):
        if not self.token or not self.chat_room_id:
            return
        h = self._auth_headers()
        m = self.client.get(f"/api/v1/chat-rooms/{self.chat_room_id}/messages?size=20", headers=h, name="journey:chat/messages")
        self.client.post(
            f"/api/v1/chat-rooms/{self.chat_room_id}/messages",
            json={"messageType": "TEXT", "content": f"locust-{int(time.time() * 1000)}"},
            headers=h,
            name="journey:chat/send",
        )

        if m.status_code == 200:
            try:
                items = m.json().get("data", {}).get("data", [])
                if items:
                    last_id = items[-1].get("id")
                    if last_id:
                        self.client.patch(
                            f"/api/v1/chat-rooms/{self.chat_room_id}/read-cursor",
                            json={"lastReadMessageId": last_id},
                            headers=h,
                            name="journey:chat/read_cursor",
                        )
            except Exception:
                pass

    @task(8)
    def writing_journey(self):
        if not self.token or not self.group_id:
            return
        h = self._auth_headers()
        self.client.post(
            f"/api/v1/restaurants/{self.restaurant_id}/reviews",
            json={
                "content": f"locust-review-{int(time.time() * 1000)}",
                "groupId": self.group_id,
                "keywordIds": [1],
                "isRecommended": True,
            },
            headers=h,
            name="journey:writing/review",
        )

        self.client.post(
            "/api/v1/members/me/favorites/restaurants",
            json={"restaurantId": self.restaurant_id},
            headers=h,
            name="journey:writing/favorite_add",
        )
        self.client.delete(
            f"/api/v1/members/me/favorites/restaurants/{self.restaurant_id}",
            headers=h,
            name="journey:writing/favorite_del",
        )
