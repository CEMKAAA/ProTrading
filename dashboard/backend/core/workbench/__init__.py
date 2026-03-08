"""Trader's Workbench — tool registry and helpers."""

from typing import Any, Dict, List, Optional

from .tool_base import WorkbenchTool
from .fvg_tool import FVGTool
from .liquidity_tool import LiquidityTool
from .mean_rev_tool import MeanRevTool

WORKBENCH_ID = "_workbench"

# Singleton tool instances
WORKBENCH_TOOLS: Dict[str, WorkbenchTool] = {
    "fvg": FVGTool(),
    "liquidity": LiquidityTool(),
    "mean_rev": MeanRevTool(),
}


def get_tool(tool_id: str) -> Optional[WorkbenchTool]:
    """Return a tool instance by ID, or None."""
    return WORKBENCH_TOOLS.get(tool_id)


def list_tools() -> List[Dict[str, Any]]:
    """Return metadata for all registered workbench tools."""
    tools: List[Dict[str, Any]] = []
    for t in WORKBENCH_TOOLS.values():
        default_cfg = t.get_default_config() or {}
        row = {
            "id": t.tool_id,
            "name": t.display_name,
            "icon": t.icon,
            "description": t.description,
            "default_config": default_cfg,
        }
        if "strictness" in default_cfg:
            row["strictness"] = {
                "min": 1,
                "max": 5,
                "default": int(default_cfg.get("strictness") or 3),
                "labels": {
                    "1": "Loose",
                    "2": "Mild Loose",
                    "3": "Normal (Default)",
                    "4": "Strict",
                    "5": "Very Strict",
                },
            }
        tools.append(row)
    return tools
