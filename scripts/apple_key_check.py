"""App Store Connect API 키가 실제로 무엇에 접근할 수 있는지 확인한다.

xcodebuild는 무엇이 막혀도 "Authentication failed"라고만 말한다. 키가 틀린 건지,
권한이 모자란 건지, 다른 이유인지 구별할 수 없어서 추측만 쌓이게 된다.

여기서는 자동 서명에 필요한 엔드포인트를 하나씩 두드려 상태 코드를 그대로 보여 준다.
읽기만 하므로 계정에 아무것도 만들지 않는다.

    python3 scripts/apple_key_check.py <key_id> <issuer_id> <p8_path>
"""

from __future__ import annotations

import json
import sys
import urllib.error
import urllib.request

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from apple_team_id import make_jwt  # noqa: E402

BASE = "https://api.appstoreconnect.apple.com/v1"

# 자동 서명이 실제로 쓰는 것들. 하나라도 막히면 프로파일을 못 만든다.
ENDPOINTS = [
    ("certificates", "인증서 (서명에 쓸 인증서 조회·발급)"),
    ("bundleIds", "번들 ID (앱 식별자)"),
    ("profiles", "프로비저닝 프로파일"),
    ("devices", "기기 목록"),
]


def probe(token: str, path: str) -> tuple[int, str]:
    request = urllib.request.Request(
        f"{BASE}/{path}?limit=1", headers={"Authorization": f"Bearer {token}"}
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            body = json.load(response)
            count = len(body.get("data", []))
            return response.status, f"{count}건 이상"
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", "replace")
        try:
            first = json.loads(detail)["errors"][0]
            note = f"{first.get('title')} / {first.get('detail')}"
        except Exception:  # noqa: BLE001
            note = detail[:200]
        return error.code, note
    except Exception as error:  # noqa: BLE001
        return 0, f"{type(error).__name__}: {error}"


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__, file=sys.stderr)
        return 2

    key_id, issuer_id, key_path = sys.argv[1], sys.argv[2], sys.argv[3]
    with open(key_path, encoding="utf-8") as handle:
        token = make_jwt(key_id, issuer_id, handle.read())

    print("자동 서명에 필요한 접근 권한:")
    blocked = []
    for path, label in ENDPOINTS:
        status, note = probe(token, path)
        mark = "OK  " if status == 200 else "막힘"
        print(f"  [{mark}] {status:>3}  {label}")
        if status != 200:
            print(f"         → {note}")
            blocked.append(label)

    if blocked:
        print("")
        print("막힌 것이 있다. 403이면 키의 역할이 모자란 것이고,")
        print("401이면 키 ID·발급자 ID·.p8이 서로 맞는 짝이 아니다.")
        return 1

    print("")
    print("모두 접근 가능하다. 서명 실패의 원인은 권한이 아니다.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
