"""Shared Pydantic request/response models for the LLM lab API."""

from __future__ import annotations

from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field

from app import config


class ChatRequest(BaseModel):
    prompt: str = Field(..., max_length=config.MAX_TEXT_LENGTH)
    defensive_mode: bool = Field(
        default=False,
        description="If true, run the request through instruction separation "
        "and output validation before responding (see LLM01 mitigation).",
    )


class ChatResponse(BaseModel):
    vulnerability: str
    mode: str
    response: str
    detail: Optional[Dict[str, Any]] = None


class ScenarioInfo(BaseModel):
    id: str
    title: str
    status: str = "current"  # "current" | "legacy" | "supplemental"
    description: str
    educational_objective: str
    example_request: Dict[str, Any]
    mitigation: str
    logging_point: str
    test_reference: str
    endpoints: List[str]


class RagQuery(BaseModel):
    query: str = Field(..., max_length=config.MAX_TEXT_LENGTH)
    tenant: str = Field(default="tenant-a", max_length=64)
    enforce_authorization: bool = Field(default=False)


class DocumentIngest(BaseModel):
    doc_id: str = Field(..., max_length=64)
    content: str = Field(..., max_length=config.MAX_TEXT_LENGTH)
    trusted: bool = Field(default=False, description="Whether the ingesting client asserts this source is trusted.")
