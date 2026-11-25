"""Small retrieval-augmented generation (RAG) pipeline with two policies.

One engine, two behaviors:
  secure  tenant filtering in the query, ingestion validation and quarantine,
          retrieval-time scanning, grounded answers with checked citations.
  lab     the deliberately weak version: a global index, no validation, raw
          context concatenation. Mounted only in LLM_LAB_MODE=lab.

The store is embedded SQLite with a feature-hashing embedder, so the lab needs
no extra services and tests run offline. A production system would use a real
vector database (pgvector, Qdrant) and a trained embedding model; the access
control and ingestion lessons are the same.
"""
