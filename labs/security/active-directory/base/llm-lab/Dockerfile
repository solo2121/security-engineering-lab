# LLM security lab image. Runs as an unprivileged user with no writable root.
FROM python:3.12.8-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    LLM_LAB_ROOT=/app

RUN useradd --system --uid 10001 --no-create-home --shell /usr/sbin/nologin llmlab

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
COPY data ./data
RUN mkdir -p /app/data/sandbox && chown -R llmlab:llmlab /app/data/sandbox

USER llmlab
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2).status == 200 else 1)"

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
