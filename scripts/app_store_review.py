#!/usr/bin/env python3
"""Inspect App Store screenshot processing and optionally submit a version.

Usage:
    python3 scripts/app_store_review.py <key_id> <issuer_id> <p8_path> [inspect|submit]

The script intentionally prints only App Store resource IDs and processing
states. It never prints the private key or the generated JWT.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

from apple_team_id import make_jwt


BASE = "https://api.appstoreconnect.apple.com/v1"
APP_ID = os.environ.get("APP_ID", "6797682561")
VERSION_STRING = os.environ.get("VERSION_STRING", "1.0")
PLATFORM = os.environ.get("PLATFORM", "IOS")


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
    if action not in {"inspect", "submit"}:
        print("action must be inspect or submit", file=sys.stderr)
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
        if action == "submit":
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
