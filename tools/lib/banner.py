"""
Shared CLI banner/header rendering.

Several tools in ``tools/security/`` print an ASCII banner and a
legal/scope reminder ("authorized lab use only") when they start up.
This module gives them one implementation instead of N slightly
different copies.
"""

from __future__ import annotations

_DEFAULT_WIDTH = 70


def render_banner(
    title: str,
    subtitle: str = "",
    *,
    authorized_use_notice: bool = True,
    width: int = _DEFAULT_WIDTH,
) -> str:
    """
    Render a plain-text banner suitable for printing at tool startup.

    Args:
        title: Tool name, e.g. "Port Scanner".
        subtitle: Optional short description shown under the title.
        authorized_use_notice: If True, append the standard reminder
            that the tool is for authorized lab/testing use only.
        width: Total width of the banner border, in characters.

    Returns:
        A multi-line string ready to print.
    """
    border = "=" * width
    lines = [border, title.center(width)]
    if subtitle:
        lines.append(subtitle.center(width))
    if authorized_use_notice:
        lines.append("For authorized security testing and educational use only.".center(width))
    lines.append(border)
    return "\n".join(lines)
