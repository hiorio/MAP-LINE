from __future__ import annotations

import unittest

from apple_certificate_cleanup import is_ci_development_certificate


def certificate(
    name: str | None,
    certificate_type: str,
    display_name: str | None = None,
) -> dict:
    return {
        "id": "TEST",
        "attributes": {
            "name": name,
            "displayName": display_name,
            "certificateType": certificate_type,
        },
    }


class CertificateFilterTests(unittest.TestCase):
    def test_selects_only_api_created_development_certificates(self) -> None:
        self.assertTrue(is_ci_development_certificate(certificate("Created via API", "DEVELOPMENT")))
        self.assertTrue(
            is_ci_development_certificate(certificate("Created via API", "IOS_DEVELOPMENT"))
        )
        self.assertTrue(
            is_ci_development_certificate(
                certificate(None, "DEVELOPMENT", "Apple Development: Created via API")
            )
        )

    def test_never_selects_distribution_certificates(self) -> None:
        self.assertFalse(
            is_ci_development_certificate(certificate("Created via API", "DISTRIBUTION"))
        )
        self.assertFalse(
            is_ci_development_certificate(certificate("Created via API", "IOS_DISTRIBUTION"))
        )

    def test_never_selects_personal_development_certificates(self) -> None:
        self.assertFalse(is_ci_development_certificate(certificate("hiorio", "DEVELOPMENT")))


if __name__ == "__main__":
    unittest.main()
