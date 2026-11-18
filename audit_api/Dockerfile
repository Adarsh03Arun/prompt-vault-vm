FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . /app/audit_api
# Expect to be built from prompt-vault-tch/ with context including package layout,
# or run: docker build -f audit_api/Dockerfile .
ENV PYTHONPATH=/app
EXPOSE 8088
CMD ["python", "-m", "uvicorn", "audit_api.app:app", "--host", "0.0.0.0", "--port", "8088"]
