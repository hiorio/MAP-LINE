"""CI가 만든 임시 Apple 개발 인증서만 정리한다.

GitHub의 macOS 러너는 실행마다 새 컴퓨터라 이전 실행의 개인키를 갖고 있지 않다.
`xcodebuild -allowProvisioningUpdates`는 그래서 `Created via API` 개발 인증서를 새로
발급한다. 인증서만 Apple 계정에 남겨 두면 결국 활성 인증서 한도를 채운다.

이 스크립트는 이름과 종류를 모두 확인해 CI가 만든 통합 개발 인증서만 폐기한다.
사람 이름으로 만든 인증서와 배포 인증서는 절대 대상에 넣지 않는다.

    python3 scripts/apple_certificate_cleanup.py \
      <key_id> <issuer_id> <p8_path> [--dry-run]
"""

from __future__ import annotations

import json
import sys
import urllib.error
import urllib.request

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from apple_team_id import make_jwt  # noqa: E402

BASE = "https://api.appstoreconnect.apple.com/v1"
CI_CERTIFICATE_NAME = "Created via API"
CI_DEVELOPMENT_TYPES = {"DEVELOPMENT", "IOS_DEVELOPMENT", "MAC_APP_DEVELOPMENT"}


class CleanupError(Exception):
    """Apple API가 인증서 정리를 거부했다."""


def api_request(token: str, path: str, method: str = "GET") -> tuple[int, dict | None]:
    request = urllib.request.Request(
        f"{BASE}/{path}",
        method=method,
        headers={"Authorization": f"Bearer {token}"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            body = json.load(response) if response.status != 204 else None
            return response.status, body
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", "replace")[:600]
        raise CleanupError(f"Apple API {method} {path}: HTTP {error.code}: {detail}") from error


def is_ci_development_certificate(item: dict) -> bool:
    attributes = item.get("attributes", {})
    return (
        attributes.get("name") == CI_CERTIFICATE_NAME
        and attributes.get("certificateType") in CI_DEVELOPMENT_TYPES
    )


def cleanup(token: str, dry_run: bool = False) -> tuple[int, int]:
    _, body = api_request(token, "certificates?limit=200")
    certificates = (body or {}).get("data", [])
    targets = [item for item in certificates if is_ci_development_certificate(item)]

    for item in targets:
        certificate_id = item["id"]
        certificate_type = item.get("attributes", {}).get("certificateType", "unknown")
        action = "확인" if dry_run else "폐기"
        print(f"  {action}: {certificate_id} ({certificate_type}, {CI_CERTIFICATE_NAME})")
        if not dry_run:
            status, _ = api_request(token, f"certificates/{certificate_id}", method="DELETE")
            if status != 204:
                raise CleanupError(
                    f"인증서 {certificate_id} 폐기 응답이 예상과 다르다: HTTP {status}"
                )

    protected = len(certificates) - len(targets)
    return len(targets), protected


def main() -> int:
    if len(sys.argv) not in (4, 5) or (len(sys.argv) == 5 and sys.argv[4] != "--dry-run"):
        print(__doc__, file=sys.stderr)
        return 2

    key_id, issuer_id, key_path = sys.argv[1:4]
    dry_run = len(sys.argv) == 5
    with open(key_path, encoding="utf-8") as handle:
        token = make_jwt(key_id, issuer_id, handle.read())

    try:
        removed, protected = cleanup(token, dry_run=dry_run)
    except Exception as error:  # noqa: BLE001 - CI 로그에 Apple 원인을 보존한다
        print(f"인증서 정리 실패: {type(error).__name__}: {error}", file=sys.stderr)
        return 1

    verb = "찾았다" if dry_run else "폐기했다"
    print(f"✅ CI 개발 인증서 {removed}개를 {verb}. 다른 인증서 {protected}개는 건드리지 않았다.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
