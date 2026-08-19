#!/usr/bin/env python3
"""WorkBuddy daily check-in via direct API call (bypasses UI clicking).
Reads auth from CodeBuddyExtension Data/Public/auth/workbuddy-desktop.info
"""
import json
import sys
import urllib.request

AUTH_FILE = "/mnt/c/Users/wangy/AppData/Local/CodeBuddyExtension/Data/Public/auth/workbuddy-desktop.info"
ENDPOINT = "https://copilot.tencent.com"
STATUS_URL = ENDPOINT + "/v2/billing/meter/checkin-activity-status"
CLAIM_URL = ENDPOINT + "/v2/billing/meter/daily-checkin"


def load_auth():
    with open(AUTH_FILE, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data["auth"]["accessToken"], data["account"]["uid"]


def call(url, token, uid):
    req = urllib.request.Request(
        url,
        data=b"{}",
        method="POST",
        headers={
            "Accept": "application/json",
            "Content-Type": "application/json",
            "Authorization": "Bearer " + token,
            "X-User-Id": uid,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        return e.code, json.loads(body) if body else {"msg": e.reason}


def main():
    token, uid = load_auth()
    print("Auth loaded: uid=%s token_len=%d" % (uid, len(token)))

    # 1. Query current check-in status
    code, status = call(STATUS_URL, token, uid)
    print("Status HTTP %d" % code)
    if code != 200:
        print("Status body: %s" % str(status)[:300])
        sys.exit(1)

    data = status.get("data") or {}
    print("today_checked_in=%s streak_days=%s today_credit=%s uiState=%s" % (
        data.get("today_checked_in"), data.get("streak_days"),
        data.get("today_credit"), data.get("uiState")))

    if data.get("today_checked_in"):
        print("ALREADY CHECKED IN TODAY - nothing to claim")
        return 0

    # 2. Claim the daily check-in
    print("Claiming...")
    code, result = call(CLAIM_URL, token, uid)
    print("Claim HTTP %d" % code)
    claim_data = result.get("data") or result
    print("Claim result code=%s msg=%s credit=%s streak=%s" % (
        claim_data.get("code"), claim_data.get("msg"),
        claim_data.get("credit"), claim_data.get("streak_days")))
    if result.get("code") == 0:
        print("CHECKIN SUCCESS: +%s credit, %s-day streak" % (
            claim_data.get("credit"), claim_data.get("streak_days")))
        return 0
    print("CHECKIN FAILED: %s" % json.dumps(result, ensure_ascii=False)[:300])
    return 1


if __name__ == "__main__":
    sys.exit(main())