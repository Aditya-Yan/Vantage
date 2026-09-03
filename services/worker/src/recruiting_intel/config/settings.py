"""Application settings.

Loaded from environment variables, whose names match `.env.example` at the
repository root.

Two rules govern this module:

1. **Every field is optional or defaulted.** The worker must import, run its
   test suite, and answer `worker health` with a completely empty environment.
   Phase 1 requires no credentials at all, and tests must never depend on them.

2. **Secrets are `SecretStr`.** They do not appear in `repr()`, and
   `Settings.redacted_dump()` is the only supported way to serialize
   configuration for logging.

Thresholds live here rather than as constants scattered through the codebase
(MASTER_PLAN 0.18).
"""

from __future__ import annotations

from functools import lru_cache
from typing import Any, Literal

from pydantic import AliasChoices, Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict

Environment = Literal["development", "staging", "production", "test"]
LogLevel = Literal["debug", "info", "warning", "error", "critical"]


class Settings(BaseSettings):
    """Worker configuration.

    Field names map to upper-case environment variables. Where the deployed
    variable name differs from a natural Python name, `validation_alias`
    records the mapping explicitly.
    """

    # The process environment is the only source. Reading a `.env` file would
    # mean guessing a path relative to an unpredictable working directory;
    # exporting variables in the shell or the process manager is explicit.
    model_config = SettingsConfigDict(
        env_file=None,
        case_sensitive=False,
        extra="ignore",
    )

    # -- Environment ------------------------------------------------------
    app_env: Environment = "development"
    log_level: LogLevel = "info"

    # -- Supabase ---------------------------------------------------------
    # The worker accepts either name; the web app publishes NEXT_PUBLIC_*.
    supabase_url: str | None = Field(
        default=None,
        validation_alias=AliasChoices("SUPABASE_URL", "NEXT_PUBLIC_SUPABASE_URL"),
    )
    supabase_anon_key: SecretStr | None = Field(
        default=None,
        validation_alias=AliasChoices("SUPABASE_ANON_KEY", "NEXT_PUBLIC_SUPABASE_ANON_KEY"),
    )
    supabase_service_role_key: SecretStr | None = None
    supabase_db_url: SecretStr | None = None

    # -- LLM provider -----------------------------------------------------
    llm_provider: str | None = None
    llm_api_key: SecretStr | None = None
    llm_base_url: str | None = None
    llm_model_classification: str | None = None
    llm_model_research: str | None = None
    llm_model_email_draft: str | None = None
    llm_model_company_scoring: str | None = None

    # -- Embedding provider -----------------------------------------------
    embedding_provider: str | None = None
    embedding_api_key: SecretStr | None = None
    embedding_base_url: str | None = None
    embedding_model: str | None = None

    # -- Search provider --------------------------------------------------
    search_provider: str | None = None
    search_api_key: SecretStr | None = None
    search_base_url: str | None = None

    # -- Notification provider --------------------------------------------
    notification_provider: str = "console"
    notification_api_key: SecretStr | None = None
    notification_from_address: str | None = None
    notification_to_address: str | None = None

    # -- Job sources -------------------------------------------------------
    github_token: SecretStr | None = None
    reddit_client_id: str | None = None
    reddit_client_secret: SecretStr | None = None
    reddit_user_agent: str | None = None

    # -- Feature flags -----------------------------------------------------
    # Reddit stays off until credentials exist; the adapter is fixture-tested
    # regardless (MASTER_PLAN 15).
    enable_reddit_source: bool = False
    enable_linkedin_public_enrichment: bool = False
    enable_llm_classification_fallback: bool = False

    # -- Thresholds --------------------------------------------------------
    company_target_score_threshold: float = 70.0
    # Scores between the reject and accept thresholds are the ambiguous band
    # routed to the LLM fallback (MASTER_PLAN 17, 5F). These are tuning knobs,
    # not calibrated probabilities.
    classification_accept_threshold: float = 0.75
    classification_reject_threshold: float = 0.35
    feed_visibility_days: int = 3
    raw_payload_retention_days: int = 90

    # -- Helpers -----------------------------------------------------------
    @property
    def is_production(self) -> bool:
        return self.app_env == "production"

    def configured_integrations(self) -> dict[str, bool]:
        """Report which optional integrations have enough configuration to use.

        Phase 1 has none of them. This exists so `worker health` can state what
        is and is not wired up without pretending anything works.
        """
        return {
            "supabase": self.supabase_url is not None,
            "llm": self.llm_api_key is not None,
            "embedding": self.embedding_api_key is not None,
            "search": self.search_api_key is not None,
            "github": self.github_token is not None,
            "reddit": self.reddit_client_id is not None and self.reddit_client_secret is not None,
        }

    def redacted_dump(self) -> dict[str, Any]:
        """Serialize settings with every secret replaced.

        Unset secrets render as ``None`` so absent and present are
        distinguishable; set secrets render as ``"***"`` and never leak their
        value. This is the only supported way to log configuration.
        """
        dumped = self.model_dump()
        for name, value in self.__dict__.items():
            if isinstance(value, SecretStr):
                dumped[name] = "***"
        return dumped


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Return the process-wide settings singleton.

    Cached so configuration is read once. Tests that need a different
    environment should construct ``Settings()`` directly or call
    ``get_settings.cache_clear()``.
    """
    return Settings()
