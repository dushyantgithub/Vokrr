import os
import time

import httpx
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

BACKEND_URL = os.getenv("VOICE_BACKEND_URL", "http://backend:8080").rstrip("/")
APP_USERNAME = os.getenv("APP_USERNAME", "admin")
APP_PASSWORD = os.getenv("APP_PASSWORD", "")

app = FastAPI(title="Quantum Home Voice Intent Bridge", version="0.1.0")
_token: str | None = None
_token_time = 0.0


class CommandRequest(BaseModel):
    text: str


@app.get("/health")
async def health() -> dict:
    return {"ok": True, "backend_url": BACKEND_URL}


@app.post("/command")
async def command(request: CommandRequest) -> dict:
    token = await get_token()
    async with httpx.AsyncClient(timeout=15) as client:
        response = await client.post(
            f"{BACKEND_URL}/api/voice/command",
            headers={"Authorization": f"Bearer {token}"},
            json={"text": request.text},
        )
    if response.status_code >= 400:
        raise HTTPException(status_code=response.status_code, detail=response.text)
    return response.json()


async def get_token() -> str:
    global _token, _token_time
    if _token and time.time() - _token_time < 60 * 60:
        return _token
    async with httpx.AsyncClient(timeout=10) as client:
        response = await client.post(
            f"{BACKEND_URL}/api/auth/login",
            json={"username": APP_USERNAME, "password": APP_PASSWORD},
        )
    if response.status_code >= 400:
        raise HTTPException(status_code=503, detail="Voice bridge could not authenticate")
    _token = response.json()["token"]
    _token_time = time.time()
    return _token
