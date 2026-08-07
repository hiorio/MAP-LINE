#!/usr/bin/env python3
"""Inspect, replace, and submit App Store screenshots for a version.

Usage:
    python3 scripts/app_store_review.py <key_id> <issuer_id> <p8_path> [action]

The script intentionally prints only App Store resource IDs and processing
states. It never prints the private key or the generated JWT.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

from apple_team_id import make_jwt
from PIL import Image


BASE = "https://api.appstoreconnect.apple.com/v1"
APP_ID = os.environ.get("APP_ID", "6797682561")
VERSION_STRING = os.environ.get("VERSION_STRING", "1.0")
PLATFORM = os.environ.get("PLATFORM", "IOS")
LOCALE = os.environ.get("LOCALE", "ko")
SCREENSHOT_SOURCE_DIR = Path(
    os.environ.get(
        "SCREENSHOT_SOURCE_DIR",
        "appstore/screenshots/ko-KR/submission-2026-08-07",
    )
)
SCREENSHOT_NAMES = (
    "01-date-course.png",
    "02-midpoint-map.png",
    "03-midpoint-process.png",
    "04-gangwon-trip.png",
    "05-library-folder.png",
)
SCREENSHOT_TARGETS = {
    "APP_IPHONE_61": (1206, 2622),
    "APP_IPHONE_67": (1320, 2868),
}


class APIError(RuntimeError):
    def __init__(self, method: str, url: str, status: int, body: Any):
        super().__init__(f"{method} {url} failed with HTTP {status}")
        self.method = method
        self.url = url
        self.status = status
        self.body = body


def request(
    token: str,
    method: str,
    path_or_url: str,
    payload: dict[str, Any] | None = None,
) -> dict[str, Any]:
    url = path_or_url if path_or_url.startswith("https://") else f"{BASE}/{path_or_url.lstrip('/')}"
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
    }
    if body is not None:
        headers["Content-Type"] = "application/json"

    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=45) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        raw = error.read().decode("utf-8", errors="replace")
        try:
            parsed: Any = json.loads(raw)
        except json.JSONDecodeError:
            parsed = {"raw": raw[:2000]}
        raise APIError(method, url, error.code, parsed) from error


def get_all(token: str, path: str) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    next_url: str | None = path
    while next_url:
        response = request(token, "GET", next_url)
        items.extend(response.get("data", []))
        next_url = response.get("links", {}).get("next")
    return items


def upload_operation(path: Path, operation: dict[str, Any]) -> None:
    offset = int(operation.get("offset", 0))
    length = int(operation.get("length", path.stat().st_size))
    with path.open("rb") as handle:
        handle.seek(offset)
        body = handle.read(length)
    if len(body) != length:
        raise RuntimeError(
            f"Upload slice length mismatch for {path.name}: expected {length}, got {len(body)}"
        )

    headers = {
        item["name"]: item["value"]
        for item in operation.get("requestHeaders", [])
        if item.get("name") and item.get("value") is not None
    }
    req = urllib.request.Request(
        operation["url"],
        data=body,
        headers=headers,
        method=operation.get("method", "PUT"),
    )
    try:
        with urllib.request.urlopen(req, timeout=180) as response:
            response.read()
    except urllib.error.HTTPError as error:
        error.read()
        raise RuntimeError(
            f"Binary upload failed for {path.name} with HTTP {error.code}"
        ) from error


def error_summary(error: APIError) -> dict[str, Any]:
    errors = error.body.get("errors", []) if isinstance(error.body, dict) else []
    return {
        "httpStatus": error.status,
        "errors": [
            {
                "status": item.get("status"),
                "code": item.get("code"),
                "title": item.get("title"),
                "detail": item.get("detail"),
                "source": item.get("source"),
                "associatedErrors": item.get("meta", {}).get("associatedErrors"),
            }
            for item in errors
        ],
    }


def find_version(token: str) -> dict[str, Any]:
    query = urllib.parse.urlencode(
        {
            "filter[platform]": PLATFORM,
            "filter[versionString]": VERSION_STRING,
            "limit": "50",
        }
    )
    versions = get_all(token, f"apps/{APP_ID}/appStoreVersions?{query}")
    if not versions:
        raise RuntimeError(f"No {PLATFORM} App Store version {VERSION_STRING} found for app {APP_ID}")

    preferred_states = {"PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW"}
    return next(
        (version for version in versions if version.get("attributes", {}).get("appStoreState") in preferred_states),
        versions[0],
    )


def find_localization(token: str, version_id: str) -> dict[str, Any]:
    localizations = get_all(
        token,
        f"appStoreVersions/{version_id}/appStoreVersionLocalizations?limit=200",
    )
    exact = next(
        (item for item in localizations if item.get("attributes", {}).get("locale") == LOCALE),
        None,
    )
    if exact is not None:
        return exact
    language = LOCALE.split("-")[0]
    fallback = next(
        (
            item
            for item in localizations
            if item.get("attributes", {}).get("locale", "").split("-")[0] == language
        ),
        None,
    )
    if fallback is None:
        available = [item.get("attributes", {}).get("locale") for item in localizations]
        raise RuntimeError(f"No localization for {LOCALE}; available locales: {available}")
    return fallback


def prepare_screenshots() -> dict[str, list[Path]]:
    source_files = [SCREENSHOT_SOURCE_DIR / name for name in SCREENSHOT_NAMES]
    missing = [str(path) for path in source_files if not path.is_file()]
    if missing:
        raise RuntimeError(f"Missing screenshot files: {missing}")

    for path in source_files:
        with Image.open(path) as image:
            if image.size != SCREENSHOT_TARGETS["APP_IPHONE_61"]:
                raise RuntimeError(
                    f"Unexpected size for {path.name}: {image.size}; expected "
                    f"{SCREENSHOT_TARGETS['APP_IPHONE_61']}"
                )
            if image.mode != "RGB":
                raise RuntimeError(f"{path.name} must be RGB without alpha; got {image.mode}")

    generated_dir = Path(tempfile.mkdtemp(prefix="appstore-6.9-"))
    generated_files: list[Path] = []
    for source in source_files:
        destination = generated_dir / source.name
        with Image.open(source) as image:
            image.convert("RGB").resize(
                SCREENSHOT_TARGETS["APP_IPHONE_67"],
                Image.Resampling.LANCZOS,
            ).save(destination, format="PNG", optimize=True)
        with Image.open(destination) as image:
            if image.size != SCREENSHOT_TARGETS["APP_IPHONE_67"] or image.mode != "RGB":
                raise RuntimeError(f"Generated screenshot validation failed for {source.name}")
        generated_files.append(destination)

    return {
        "APP_IPHONE_61": source_files,
        "APP_IPHONE_67": generated_files,
    }


def screenshot_sets_for_localization(
    token: str,
    localization_id: str,
) -> list[dict[str, Any]]:
    return get_all(
        token,
        f"appStoreVersionLocalizations/{localization_id}/appScreenshotSets?limit=200",
    )


def wait_for_screenshot(token: str, screenshot_id: str, file_name: str) -> dict[str, Any]:
    deadline = time.monotonic() + 300
    while time.monotonic() < deadline:
        screenshot = request(token, "GET", f"appScreenshots/{screenshot_id}").get("data", {})
        delivery = screenshot.get("attributes", {}).get("assetDeliveryState") or {}
        state = delivery.get("state")
        if state == "COMPLETE":
            image = screenshot.get("attributes", {}).get("imageAsset") or {}
            return {
                "id": screenshot_id,
                "fileName": file_name,
                "state": state,
                "width": image.get("width"),
                "height": image.get("height"),
            }
        if state == "FAILED":
            raise RuntimeError(
                f"App Store processing failed for {file_name}: {delivery.get('errors') or []}"
            )
        time.sleep(3)
    raise RuntimeError(f"Timed out waiting for App Store processing of {file_name}")


def upload_screenshot(
    token: str,
    screenshot_set_id: str,
    path: Path,
) -> tuple[str, dict[str, Any]]:
    size = path.stat().st_size
    response = request(
        token,
        "POST",
        "appScreenshots",
        {
            "data": {
                "type": "appScreenshots",
                "attributes": {"fileName": path.name, "fileSize": size},
                "relationships": {
                    "appScreenshotSet": {
                        "data": {"type": "appScreenshotSets", "id": screenshot_set_id}
                    }
                },
            }
        },
    )["data"]
    screenshot_id = response["id"]
    operations = response.get("attributes", {}).get("uploadOperations") or []
    if not operations:
        raise RuntimeError(f"App Store returned no upload operations for {path.name}")
    for operation in operations:
        upload_operation(path, operation)

    checksum = hashlib.md5(path.read_bytes(), usedforsecurity=False).hexdigest()
    request(
        token,
        "PATCH",
        f"appScreenshots/{screenshot_id}",
        {
            "data": {
                "type": "appScreenshots",
                "id": screenshot_id,
                "attributes": {
                    "uploaded": True,
                    "sourceFileChecksum": checksum,
                },
            }
        },
    )
    return screenshot_id, wait_for_screenshot(token, screenshot_id, path.name)


def replace_screenshots(token: str, version_id: str) -> list[dict[str, Any]]:
    files_by_type = prepare_screenshots()
    localization = find_localization(token, version_id)
    localization_id = localization["id"]
    existing_sets = screenshot_sets_for_localization(token, localization_id)
    replaced_types = set(SCREENSHOT_TARGETS)
    for screenshot_set in existing_sets:
        display_type = screenshot_set.get("attributes", {}).get("screenshotDisplayType")
        if display_type in replaced_types:
            request(token, "DELETE", f"appScreenshotSets/{screenshot_set['id']}")

    report: list[dict[str, Any]] = []
    for display_type, paths in files_by_type.items():
        created = request(
            token,
            "POST",
            "appScreenshotSets",
            {
                "data": {
                    "type": "appScreenshotSets",
                    "attributes": {"screenshotDisplayType": display_type},
                    "relationships": {
                        "appStoreVersionLocalization": {
                            "data": {
                                "type": "appStoreVersionLocalizations",
                                "id": localization_id,
                            }
                        }
                    },
                }
            },
        )["data"]
        screenshot_set_id = created["id"]
        screenshot_ids: list[str] = []
        uploaded: list[dict[str, Any]] = []
        for path in paths:
            screenshot_id, result = upload_screenshot(token, screenshot_set_id, path)
            screenshot_ids.append(screenshot_id)
            uploaded.append(result)

        request(
            token,
            "PATCH",
            f"appScreenshotSets/{screenshot_set_id}/relationships/appScreenshots",
            {
                "data": [
                    {"type": "appScreenshots", "id": screenshot_id}
                    for screenshot_id in screenshot_ids
                ]
            },
        )
        report.append(
            {
                "locale": localization.get("attributes", {}).get("locale"),
                "setId": screenshot_set_id,
                "displayType": display_type,
                "screenshots": uploaded,
            }
        )
    return report


def inspect_screenshots(token: str, version_id: str) -> list[dict[str, Any]]:
    localizations = get_all(
        token,
        f"appStoreVersions/{version_id}/appStoreVersionLocalizations?limit=200",
    )
    report: list[dict[str, Any]] = []
    for localization in localizations:
        locale = localization.get("attributes", {}).get("locale")
        localization_id = localization["id"]
        query = urllib.parse.urlencode(
            {
                "include": "appScreenshots",
                "limit": "200",
                "limit[appScreenshots]": "50",
                "fields[appScreenshots]": (
                    "fileSize,fileName,sourceFileChecksum,imageAsset,assetToken,"
                    "assetType,uploadOperations,assetDeliveryState,appScreenshotSet"
                ),
            }
        )
        response = request(
            token,
            "GET",
            f"appStoreVersionLocalizations/{localization_id}/appScreenshotSets?{query}",
        )
        included = {
            item["id"]: item
            for item in response.get("included", [])
            if item.get("type") == "appScreenshots"
        }
        for screenshot_set in response.get("data", []):
            display_type = screenshot_set.get("attributes", {}).get("screenshotDisplayType")
            screenshot_ids = [
                item["id"]
                for item in screenshot_set.get("relationships", {})
                .get("appScreenshots", {})
                .get("data", [])
            ]
            screenshots: list[dict[str, Any]] = []
            for screenshot_id in screenshot_ids:
                screenshot = included.get(screenshot_id)
                if screenshot is None:
                    screenshot = request(token, "GET", f"appScreenshots/{screenshot_id}").get("data", {})
                attributes = screenshot.get("attributes", {})
                delivery = attributes.get("assetDeliveryState") or {}
                image = attributes.get("imageAsset") or {}
                operations = attributes.get("uploadOperations") or []
                screenshots.append(
                    {
                        "id": screenshot_id,
                        "fileName": attributes.get("fileName"),
                        "state": delivery.get("state"),
                        "errors": delivery.get("errors") or [],
                        "warnings": delivery.get("warnings") or [],
                        "width": image.get("width"),
                        "height": image.get("height"),
                        # Upload operations are transfer instructions, not completion flags.
                        # assetDeliveryState is the authoritative processing result.
                        "uploadOperationCount": len(operations),
                    }
                )
            report.append(
                {
                    "locale": locale,
                    "setId": screenshot_set["id"],
                    "displayType": display_type,
                    "screenshots": screenshots,
                }
            )
    return report


def list_review_submissions(token: str) -> list[dict[str, Any]]:
    return get_all(token, f"apps/{APP_ID}/reviewSubmissions?limit=200")


def submission_report(submissions: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        {
            "id": item.get("id"),
            "state": item.get("attributes", {}).get("state"),
            "submittedDate": item.get("attributes", {}).get("submittedDate"),
        }
        for item in submissions
    ]


def submit_for_review(token: str, version: dict[str, Any]) -> dict[str, Any]:
    state = version.get("attributes", {}).get("appStoreState")
    if state in {"WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE"}:
        return {"alreadySubmitted": True, "appStoreState": state}

    submissions = list_review_submissions(token)
    draft_states = {"READY_FOR_REVIEW", "UNRESOLVED_ISSUES"}
    submission = next(
        (item for item in submissions if item.get("attributes", {}).get("state") in draft_states),
        None,
    )
    if submission is None:
        payload = {
            "data": {
                "type": "reviewSubmissions",
                "attributes": {"platform": PLATFORM},
                "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}},
            }
        }
        try:
            submission = request(token, "POST", "reviewSubmissions", payload)["data"]
        except APIError as error:
            if error.status != 409:
                raise
            submissions = list_review_submissions(token)
            submission = next(
                (item for item in submissions if item.get("attributes", {}).get("state") in draft_states),
                None,
            )
            if submission is None:
                raise

    submission_id = submission["id"]
    items = get_all(token, f"reviewSubmissions/{submission_id}/items?limit=200")
    version_id = version["id"]
    has_version = any(
        item.get("relationships", {}).get("appStoreVersion", {}).get("data", {}).get("id") == version_id
        for item in items
    )
    if not has_version:
        request(
            token,
            "POST",
            "reviewSubmissionItems",
            {
                "data": {
                    "type": "reviewSubmissionItems",
                    "relationships": {
                        "reviewSubmission": {
                            "data": {"type": "reviewSubmissions", "id": submission_id}
                        },
                        "appStoreVersion": {
                            "data": {"type": "appStoreVersions", "id": version_id}
                        },
                    },
                }
            },
        )

    response = request(
        token,
        "PATCH",
        f"reviewSubmissions/{submission_id}",
        {
            "data": {
                "type": "reviewSubmissions",
                "id": submission_id,
                "attributes": {"submitted": True},
            }
        },
    )
    return {
        "submissionId": submission_id,
        "state": response.get("data", {}).get("attributes", {}).get("state"),
    }


def main() -> int:
    if len(sys.argv) not in {4, 5}:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    key_id, issuer_id, key_path = sys.argv[1:4]
    action = sys.argv[4] if len(sys.argv) == 5 else "inspect"
    allowed_actions = {"inspect", "replace", "submit", "replace-and-submit"}
    if action not in allowed_actions:
        print(f"action must be one of: {', '.join(sorted(allowed_actions))}", file=sys.stderr)
        return 2

    with open(key_path, encoding="utf-8") as handle:
        token = make_jwt(key_id, issuer_id, handle.read())

    try:
        version = find_version(token)
        version_summary = {
            "id": version["id"],
            "versionString": version.get("attributes", {}).get("versionString"),
            "platform": version.get("attributes", {}).get("platform"),
            "appStoreState": version.get("attributes", {}).get("appStoreState"),
        }
        screenshots = inspect_screenshots(token, version["id"])
        submissions = list_review_submissions(token)
        print(
            json.dumps(
                {
                    "version": version_summary,
                    "screenshotSets": screenshots,
                    "reviewSubmissions": submission_report(submissions),
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        if action in {"replace", "replace-and-submit"}:
            replacement = replace_screenshots(token, version["id"])
            print(json.dumps({"replacementResult": replacement}, ensure_ascii=False, indent=2))
        if action in {"submit", "replace-and-submit"}:
            result = submit_for_review(token, version)
            print(json.dumps({"submitResult": result}, ensure_ascii=False, indent=2))
        return 0
    except APIError as error:
        print(json.dumps(error_summary(error), ensure_ascii=False, indent=2), file=sys.stderr)
        return 1
    except Exception as error:  # noqa: BLE001 - CI must surface a concise reason.
        print(f"{type(error).__name__}: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
