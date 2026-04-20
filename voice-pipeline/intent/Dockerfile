FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY pyproject.toml ./
COPY service.py ./
RUN pip install --no-cache-dir -e .

EXPOSE 8090
CMD ["uvicorn", "service:app", "--host", "0.0.0.0", "--port", "8090"]
