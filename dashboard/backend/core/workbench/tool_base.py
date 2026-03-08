"""Abstract base class for workbench analysis tools."""

from abc import ABC, abstractmethod
from typing import Any, Dict, List
import pandas as pd


class WorkbenchTool(ABC):
    """Base class for workbench analysis tools.

    Each tool can scan a DataFrame of OHLCV bars and return
    annotated zones/markers for chart rendering.
    """

    @property
    @abstractmethod
    def tool_id(self) -> str:
        ...

    @property
    @abstractmethod
    def display_name(self) -> str:
        ...

    @property
    @abstractmethod
    def icon(self) -> str:
        """Bootstrap icon class (e.g. 'bi-layers-half')."""
        ...

    @property
    @abstractmethod
    def description(self) -> str:
        """Short, user-friendly explanation of what the tool does."""
        ...

    @abstractmethod
    def scan(self, df: pd.DataFrame, config: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Scan visible bars and return a list of zone/annotation dicts."""
        ...

    def get_default_config(self) -> Dict[str, Any]:
        """Default tool settings (user can override per scan)."""
        return {"strictness": 3}

    @staticmethod
    def normalize_strictness(value: Any, default: int = 3) -> int:
        try:
            if value is None:
                return int(default)
            s = int(value)
        except Exception:
            s = int(default)
        return max(1, min(5, s))
