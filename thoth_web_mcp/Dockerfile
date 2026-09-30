FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

COPY __init__.py /app/thoth_web_mcp/__init__.py
COPY server.py /app/thoth_web_mcp/server.py

ENV PYTHONPATH=/app
ENV THOTH_WEB_PORT=8810

USER 65532:65532

EXPOSE 8810

CMD ["python", "-m", "thoth_web_mcp.server"]
