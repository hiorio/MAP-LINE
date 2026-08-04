"""App Store Connect API 키만으로 팀 ID를 알아낸다.

사람이 developer.apple.com을 뒤져 10자리를 찾아 옮겨 적는 단계를 없애기 위한 것이다.
이미 CI에 넣어 준 자격으로 알 수 있는 값을 사람에게 시킬 이유가 없다.

`altool --list-providers`는 쓸 수 없다. API 키 인증을 지원하지 않고 Apple ID
비밀번호를 요구하는데, 그건 CI에 둘 값이 아니다.

대신 인증서 목록을 조회한다. 인증서의 주체(subject)에 팀 ID가 조직 단위(OU)로
박혀 있다. 앱을 한 번이라도 낸 계정이면 인증서가 있다.

    python3 scripts/apple_team_id.py <key_id> <issuer_id> <p8_path>
"""

from __future__ import annotations

import base64
import json
import sys
import time
import urllib.request
from collections import Counter

AUDIENCE = "appstoreconnect-v1"
API = "https://api.appstoreconnect.apple.com/v1/certificates?limit=200"


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def make_jwt(key_id: str, issuer_id: str, private_key_pem: str) -> str:
    """ES256으로 서명한 토큰.

    ECDSA 서명은 openssl이 DER로 내주지만 JWS는 r||s 원시 형식을 요구한다.
    그대로 넘기면 401이 떨어지고 원인을 찾기 어렵다.
    """
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec, utils

    key = serialization.load_pem_private_key(private_key_pem.encode(), password=None)

    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    now = int(time.time())
    payload = {"iss": issuer_id, "iat": now, "exp": now + 600, "aud": AUDIENCE}

    signing_input = f"{b64url(json.dumps(header).encode())}.{b64url(json.dumps(payload).encode())}"
    der = key.sign(signing_input.encode(), ec.ECDSA(hashes.SHA256()))
    r, s = utils.decode_dss_signature(der)
    raw = r.to_bytes(32, "big") + s.to_bytes(32, "big")
    return f"{signing_input}.{b64url(raw)}"


def team_ids_from_certificates(token: str) -> list[str]:
    request = urllib.request.Request(API, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(request, timeout=30) as response:
        body = json.load(response)

    from cryptography import x509

    found: list[str] = []
    for item in body.get("data", []):
        content = item.get("attributes", {}).get("certificateContent")
        if not content:
            continue
        try:
            cert = x509.load_der_x509_certificate(base64.b64decode(content))
        except Exception:
            continue
        for attribute in cert.subject:
            # 팀 ID는 조직 단위에 들어 있다. 10자리 영숫자다.
            if attribute.oid.dotted_string == "2.5.4.11":
                value = str(attribute.value).strip()
                if len(value) == 10 and value.isalnum():
                    found.append(value)
    return found


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__, file=sys.stderr)
        return 2

    key_id, issuer_id, key_path = sys.argv[1], sys.argv[2], sys.argv[3]
    with open(key_path, encoding="utf-8") as handle:
        private_key = handle.read()

    try:
        token = make_jwt(key_id, issuer_id, private_key)
        teams = team_ids_from_certificates(token)
    except Exception as error:  # noqa: BLE001 - 원인을 그대로 보여 줘야 고칠 수 있다
        print(f"팀 ID 조회 실패: {type(error).__name__}: {error}", file=sys.stderr)
        return 1

    if not teams:
        print(
            "인증서에서 팀 ID를 찾지 못했다. 계정에 인증서가 하나도 없을 수 있다.",
            file=sys.stderr,
        )
        return 1

    ranked = Counter(teams).most_common()
    if len(ranked) > 1:
        print(f"팀이 여럿이다: {[t for t, _ in ranked]}", file=sys.stderr)

    # 가장 많이 쓰인 것을 고른다. 여럿이면 위에 경고를 남겼다.
    print(ranked[0][0])
    return 0


if __name__ == "__main__":
    sys.exit(main())
