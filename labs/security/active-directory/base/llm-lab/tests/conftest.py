"""Pytest configuration for the LLM lab tests.

The original scenario tests exercise the intentionally vulnerable endpoints,
which are only mounted in lab mode, so lab mode is selected before the app
module is imported. Secure-mode tests build their own app via create_app().
"""
import os

os.environ.setdefault("LLM_LAB_MODE", "lab")
