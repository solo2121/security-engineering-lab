"""OWASP Top 10 for LLM Applications 2026, mapped to this lab's modules.

The scenario modules and URL prefixes under app/scenarios/ were written
against the 2025 numbering and are kept as they are, so existing bookmarks,
scripts and the llm01 VM keep working. This table is the single place that
maps the 2026 identifiers onto them.

Source: https://genai.owasp.org/resource/owasp-genai-llm-top-10-2026/
"""

from __future__ import annotations

from typing import Dict, List

# id_2026, name_2026, id_2025 (None if no 1:1 predecessor), lab prefix, note
_ROWS = [
    ("LLM01", "Prompt Injection", "LLM01", "/llm01", "Unchanged."),
    ("LLM02", "Sensitive Information Disclosure", "LLM02", "/llm02", "Unchanged."),
    ("LLM03", "Excessive Agency", "LLM06", "/llm06", "Moved up from 2025 #6."),
    ("LLM04", "Supply Chain", "LLM03", "/llm03", "Moved down from 2025 #3."),
    ("LLM05", "Data and Model Poisoning", "LLM04", "/llm04", "Moved down from 2025 #4."),
    ("LLM06", "Unbounded Consumption", "LLM10", "/llm10", "Moved up from 2025 #10."),
    ("LLM07", "Misinformation", "LLM09", "/llm09", "Moved up from 2025 #9."),
    ("LLM08", "Hidden Context Exposure", "LLM07", "/llm07", "Renamed from System Prompt Leakage."),
    ("LLM09", "Vector and Embedding Weaknesses", "LLM08", "/llm08", "Moved down from 2025 #8."),
    ("LLM10", "Improper Output Handling", "LLM05", "/llm05", "Moved down from 2025 #5."),
]

TAXONOMY_2026_NAME = "OWASP Top 10 for LLM Applications 2026"
TAXONOMY_2026_SOURCE = "https://genai.owasp.org/resource/owasp-genai-llm-top-10-2026/"


def categories_2026() -> List[Dict[str, str]]:
    return [
        {
            "id": f"{row[0]}:2026",
            "name": row[1],
            "id_2025": row[2],
            "endpoint_prefix": row[3],
            "change_from_2025": row[4],
        }
        for row in _ROWS
    ]
