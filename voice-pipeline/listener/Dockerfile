FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends alsa-utils espeak-ng libasound2 libatomic1 libportaudio2 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY voice-pipeline/listener/pyproject.toml ./
COPY voice-pipeline/listener/listener.py ./
COPY services ./services
RUN pip install --no-cache-dir -e .

EXPOSE 8091
CMD ["uvicorn", "listener:app", "--host", "0.0.0.0", "--port", "8091"]
