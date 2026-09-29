FROM python:3.12-slim
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY bridge.py bridge_crypto.py bridge_mcp_client.py ./
USER 65532:65532
CMD ["uvicorn", "bridge:app", "--host", "0.0.0.0", "--port", "8800", "--log-level", "info"]
