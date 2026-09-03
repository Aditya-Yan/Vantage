"""Settings tests.

The critical property is that the worker is fully functional with an empty
environment. Phase 1 requires no credentials, and the test suite must never
depend on any (docs/TESTING.md).
"""

from __future__ import annotations

import pytest
from pydantic import SecretStr, ValidationError

from recruiting_intel.config.settings import Settings, get_settings

# Every environment variable the settings object reads. Cleared before each
# test so a developer's real shell environment cannot influence results.
_ENV_VARS = (
    "APP_ENV",
    "LOG_LEVEL",
    "SUPABASE_URL",
    "NEXT_PUBLIC_SUPABASE_URL",
    "SUPABASE_ANON_KEY",
    "NEXT_PUBLIC_SUPABASE_ANON_KEY",
    "SUPABASE_SERVICE_ROLE_KEY",
    "SUPABASE_DB_URL",
    "LLM_PROVIDER",
    "LLM_API_KEY",
    "LLM_MODEL_CLASSIFICATION",
    "EMBEDDING_API_KEY",
    "SEARCH_API_KEY",
    "NOTIFICATION_PROVIDER",
    "GITHUB_TOKEN",
    "REDDIT_CLIENT_ID",
    "REDDIT_CLIENT_SECRET",
    "ENABLE_REDDIT_SOURCE",
    "FEED_VISIBILITY_DAYS",
    "CLASSIFICATION_ACCEPT_THRESHOLD",
)


@pytest.fixture(autouse=True)
def clean_env(monkeypatch: pytest.MonkeyPatch) -> None:
    for var in _ENV_VARS:
        monkeypatch.delenv(var, raising=False)
    get_settings.cache_clear()


def test_loads_with_completely_empty_environment() -> None:
    settings = Settings()

    assert settings.app_env == "development"
    assert settings.log_level == "info"
    assert settings.supabase_url is None
    assert settings.llm_api_key is None


def test_defaults_match_specification() -> None:
    settings = Settings()

    # Three-day feed policy (MASTER_PLAN 29).
    assert settings.feed_visibility_days == 3
    # Reddit is off until credentials exist (MASTER_PLAN 15).
    assert settings.enable_reddit_source is False
    # LinkedIn enrichment is opt-in.
    assert settings.enable_linkedin_public_enrichment is False
    # The ambiguous band that routes to the LLM must be non-empty and ordered.
    assert settings.classification_reject_threshold < settings.classification_accept_threshold


def test_environment_overrides_defaults(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("LOG_LEVEL", "warning")
    monkeypatch.setenv("FEED_VISIBILITY_DAYS", "7")

    settings = Settings()

    assert settings.app_env == "production"
    assert settings.log_level == "warning"
    assert settings.feed_visibility_days == 7
    assert settings.is_production is True


def test_supabase_url_accepts_either_variable_name(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("NEXT_PUBLIC_SUPABASE_URL", "https://example.supabase.co")

    assert Settings().supabase_url == "https://example.supabase.co"


def test_invalid_enum_value_is_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("APP_ENV", "not-a-real-environment")

    with pytest.raises(ValidationError):
        Settings()


def test_secrets_are_secretstr(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("LLM_API_KEY", "sk-super-secret")

    settings = Settings()

    assert isinstance(settings.llm_api_key, SecretStr)
    # A SecretStr must not expose its value through repr/str.
    assert "sk-super-secret" not in repr(settings.llm_api_key)
    assert "sk-super-secret" not in str(settings)
    assert settings.llm_api_key.get_secret_value() == "sk-super-secret"


def test_redacted_dump_hides_set_secrets(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("LLM_API_KEY", "sk-super-secret")
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", "service-role-value")

    dumped = Settings().redacted_dump()

    assert dumped["llm_api_key"] == "***"
    assert dumped["supabase_service_role_key"] == "***"
    assert "sk-super-secret" not in str(dumped)
    assert "service-role-value" not in str(dumped)


def test_redacted_dump_distinguishes_unset_from_set() -> None:
    dumped = Settings().redacted_dump()

    # Absent secrets stay None so "not configured" is distinguishable from
    # "configured but hidden".
    assert dumped["llm_api_key"] is None
    assert dumped["app_env"] == "development"


def test_configured_integrations_all_false_when_empty() -> None:
    integrations = Settings().configured_integrations()

    assert integrations["supabase"] is False
    assert integrations["llm"] is False
    assert integrations["reddit"] is False


def test_reddit_requires_both_credentials(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("REDDIT_CLIENT_ID", "an-id")

    # An ID without a secret is not usable configuration.
    assert Settings().configured_integrations()["reddit"] is False

    monkeypatch.setenv("REDDIT_CLIENT_SECRET", "a-secret")
    assert Settings().configured_integrations()["reddit"] is True


def test_get_settings_is_cached() -> None:
    assert get_settings() is get_settings()
