import base64
import hashlib
import hmac
import json
import time
from typing import Annotated

from fastapi import Depends, HTTPException, WebSocket, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.config import Settings, get_settings

bearer_scheme = HTTPBearer(auto_error=False)


class AuthService:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    def login(self, username: str, password: str) -> str:
        username_ok = hmac.compare_digest(username, self.settings.app_username)
        password_ok = hmac.compare_digest(password, self.settings.app_password)
        if not username_ok or not password_ok:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid username or password",
            )
        return self.create_token(username)

    def create_token(self, username: str) -> str:
        payload = {
            "sub": username,
            "exp": int(time.time()) + 60 * 60 * 24 * 30,
        }
        payload_bytes = json.dumps(payload, separators=(",", ":")).encode()
        payload_b64 = base64.urlsafe_b64encode(payload_bytes).decode().rstrip("=")
        signature = self._sign(payload_b64)
        return f"{payload_b64}.{signature}"

    def verify_token(self, token: str | None) -> str:
        if not token or "." not in token:
            raise_auth_error()
        payload_b64, signature = token.rsplit(".", 1)
        expected = self._sign(payload_b64)
        if not hmac.compare_digest(signature, expected):
            raise_auth_error()
        try:
            padded = payload_b64 + "=" * (-len(payload_b64) % 4)
            payload = json.loads(base64.urlsafe_b64decode(padded.encode()))
        except Exception:
            raise_auth_error()
        if int(payload.get("exp", 0)) < int(time.time()):
            raise_auth_error("Session expired")
        return str(payload.get("sub", ""))

    def _sign(self, payload_b64: str) -> str:
        digest = hmac.new(
            self.settings.app_auth_secret.encode(),
            payload_b64.encode(),
            hashlib.sha256,
        ).digest()
        return base64.urlsafe_b64encode(digest).decode().rstrip("=")


def raise_auth_error(detail: str = "Authentication required") -> None:
    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=detail,
        headers={"WWW-Authenticate": "Bearer"},
    )


def get_auth_service(settings: Annotated[Settings, Depends(get_settings)]) -> AuthService:
    return AuthService(settings)


def require_user(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
    auth: Annotated[AuthService, Depends(get_auth_service)],
) -> str:
    token = credentials.credentials if credentials else None
    return auth.verify_token(token)


async def require_websocket_user(websocket: WebSocket, auth: AuthService) -> str:
    token = websocket.query_params.get("token")
    try:
        return auth.verify_token(token)
    except HTTPException:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        raise
