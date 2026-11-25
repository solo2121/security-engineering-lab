"""
OWASP Top 10 for LLM Applications — Training Lab
====================================================

WARNING: In LLM_LAB_MODE=lab this application intentionally contains
vulnerable code paths for educational purposes. It must run only on the
isolated llm01 VM inside this lab's private network, never on the public
internet or a production host. The default mode ("secure") mounts only the
authenticated /secure baseline API.
Every "vulnerable" response uses synthetic data only — no real secrets,
credentials, or personal information appear anywhere in this app.

Run directly:
    uvicorn app.main:app --host 0.0.0.0 --port 8000

Docs:
    http://<host>:8000/docs   (Swagger UI)
    http://<host>:8000/redoc  (ReDoc)
"""
from __future__ import annotations

import logging
import time

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from app import config
from app.rag import routes as rag_routes
from app.secure import routes as secure_routes
from app.secure import taxonomy
from app.scenarios import (
    legacy_supplemental,
    llm01_prompt_injection,
    llm02_sensitive_information,
    llm03_supply_chain,
    llm04_data_poisoning,
    llm05_improper_output,
    llm06_excessive_agency,
    llm07_prompt_leakage,
    llm08_vector_embedding,
    llm09_misinformation,
    llm10_unbounded_consumption,
)

logging.basicConfig(
    level=logging.INFO,
    format='{"time":"%(asctime)s","level":"%(levelname)s","logger":"%(name)s","msg":"%(message)s"}',
)
logger = logging.getLogger("llm_lab")

_LAB_ROUTERS = [
    llm01_prompt_injection.router,
    llm02_sensitive_information.router,
    llm03_supply_chain.router,
    llm04_data_poisoning.router,
    llm05_improper_output.router,
    llm06_excessive_agency.router,
    llm07_prompt_leakage.router,
    llm08_vector_embedding.router,
    llm09_misinformation.router,
    llm10_unbounded_consumption.router,
    legacy_supplemental.router,
]

_CURRENT_CATEGORIES = [
    {"id": "LLM01", "name": "Prompt Injection", "endpoint_prefix": "/llm01"},
    {"id": "LLM02", "name": "Sensitive Information Disclosure", "endpoint_prefix": "/llm02"},
    {"id": "LLM03", "name": "Supply Chain", "endpoint_prefix": "/llm03"},
    {"id": "LLM04", "name": "Data and Model Poisoning", "endpoint_prefix": "/llm04"},
    {"id": "LLM05", "name": "Improper Output Handling", "endpoint_prefix": "/llm05"},
    {"id": "LLM06", "name": "Excessive Agency", "endpoint_prefix": "/llm06"},
    {"id": "LLM07", "name": "System Prompt Leakage", "endpoint_prefix": "/llm07"},
    {"id": "LLM08", "name": "Vector and Embedding Weaknesses", "endpoint_prefix": "/llm08"},
    {"id": "LLM09", "name": "Misinformation", "endpoint_prefix": "/llm09"},
    {"id": "LLM10", "name": "Unbounded Consumption", "endpoint_prefix": "/llm10"},
]


def _mount_routers(app: FastAPI, mode: str) -> None:
    app.include_router(secure_routes.router)
    app.include_router(rag_routes.router)
    if mode == "lab":
        app.include_router(rag_routes.lab_router)
        for router in _LAB_ROUTERS:
            app.include_router(router)


def create_app(mode: str = config.LAB_MODE) -> FastAPI:
    app = FastAPI(
        title=config.LAB_NAME,
        description=(
            "An intentionally vulnerable, safety-sandboxed training lab covering the "
            f"{config.LAB_TAXONOMY_VERSION} ({config.LAB_TAXONOMY_SOURCE}). "
            "All data is synthetic. All dangerous actions are simulated. "
            "Isolated to the llm01 VM's private lab network only."
        ),
        version="1.1.0",
    )

    # CORS is intentionally NOT wildcard-open here: this API is only ever
    # reached from inside the isolated lab subnet (Kali, the lab operator's
    # browser via the private network), so no cross-origin access is required.

    _mount_routers(app, mode)

    @app.middleware("http")
    async def request_size_limit_and_timing(request: Request, call_next):
        content_length = request.headers.get("content-length")
        if content_length is not None and int(content_length) > config.MAX_REQUEST_BYTES:
            logger.info('{"event":"request_too_large","content_length":%s}' % content_length)
            return JSONResponse(
                status_code=413,
                content={"detail": f"Request body exceeds the {config.MAX_REQUEST_BYTES}-byte lab limit."},
            )
        start = time.monotonic()
        response = await call_next(request)
        duration_ms = round((time.monotonic() - start) * 1000, 2)
        response.headers["X-Lab-Duration-ms"] = str(duration_ms)
        return response

    @app.get("/")
    async def root():
        return {
            "lab": config.LAB_NAME,
            "taxonomy": config.LAB_TAXONOMY_VERSION,
            "taxonomy_source": config.LAB_TAXONOMY_SOURCE,
            "mode": mode,
            "status": (
                "INTENTIONALLY VULNERABLE scenarios enabled — isolated lab VM only"
                if mode == "lab"
                else "SECURE MODE — vulnerable scenarios are disabled"
            ),
            "secure_api": "/secure",
            "docs": "/docs",
            "categories_endpoint": "/owasp/categories",
            "warning": (
                "Do not expose this service outside the lab's private network. "
                "All secrets, PII, and credentials returned by this API are synthetic."
            ),
        }

    @app.get("/health")
    async def health():
        return {"status": "ok", "lab": config.LAB_NAME}


    @app.get("/owasp/categories")
    async def owasp_categories():
        return {
            "taxonomy": config.LAB_TAXONOMY_VERSION,
            "source": config.LAB_TAXONOMY_SOURCE,
            "current_categories": _CURRENT_CATEGORIES,
            "taxonomy_2026": taxonomy.TAXONOMY_2026_NAME,
            "source_2026": taxonomy.TAXONOMY_2026_SOURCE,
            "categories_2026": taxonomy.categories_2026(),
            "legacy_supplemental_prefix": "/legacy",
            "note": (
                "current_categories keeps the 2025 numbering that the /llmNN endpoint "
                "prefixes were written against. categories_2026 maps each 2026 "
                "identifier onto those endpoints. Everything under /legacy is "
                "historical/supplemental context and is not a current category."
            ),
        }

    return app


app = create_app()
