from dataclasses import dataclass
from enum import Enum

class Verdict(str, Enum):
    ALLOW = "ALLOW"
    DENY = "DENY"
    ABSTAIN = "ABSTAIN"


@dataclass(frozen=True)
class FilterAssessment:
    setup_id: str
    strategy_id: str
    model_version: str
    verdict: Verdict
    reason_code: str


    def __post_init__(self):
        required = (
            self.setup_id,
            self.strategy_id,
            self.model_version,
            self.reason_code
        )

        if any(not isinstance(value, str) or not value.strip()
            for value in required):
            raise ValueError("Assessment identifiers must be non-empty strings")

        if not isinstance(self.verdict, Verdict):
            raise TypeError("Verdict must be a verdict")

        


