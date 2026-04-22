import base64
import hashlib
import hmac
import json
import secrets
import sqlite3
import subprocess
import time
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Annotated, Any

from fastapi import Depends, HTTPException, Request, WebSocket, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.config import Settings, get_settings

bearer_scheme = HTTPBearer(auto_error=False)


def _utcnow() -> datetime:
    return datetime.now(UTC)


def _encode_b64url(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).decode().rstrip("=")


def _decode_b64url(value: str) -> bytes:
    padded = value + "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode(padded.encode())


def _password_hash(password: str, salt: bytes) -> str:
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, 310_000)
    return _encode_b64url(digest)


def _token_hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


@dataclass(slots=True)
class AuthenticatedUser:
    id: str
    username: str
    is_admin: bool


class AuthRepository:
    def __init__(self, database_path: str) -> None:
        self.database_path = database_path
        self._initialize()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.database_path, check_same_thread=False)
        connection.row_factory = sqlite3.Row
        return connection

    def _initialize(self) -> None:
        with self._connect() as connection:
            connection.executescript(
                """
                PRAGMA journal_mode=WAL;

                CREATE TABLE IF NOT EXISTS users (
                    id TEXT PRIMARY KEY,
                    username TEXT NOT NULL UNIQUE,
                    password_salt TEXT NOT NULL,
                    password_hash TEXT NOT NULL,
                    is_admin INTEGER NOT NULL DEFAULT 0,
                    is_active INTEGER NOT NULL DEFAULT 1,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    last_login_at TEXT
                );

                CREATE TABLE IF NOT EXISTS refresh_tokens (
                    id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    token_hash TEXT NOT NULL UNIQUE,
                    created_at TEXT NOT NULL,
                    expires_at TEXT NOT NULL,
                    last_used_at TEXT,
                    revoked_at TEXT,
                    client_ip TEXT,
                    user_agent TEXT,
                    FOREIGN KEY(user_id) REFERENCES users(id)
                );

                CREATE TABLE IF NOT EXISTS activity_log (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id TEXT,
                    username TEXT,
                    action TEXT NOT NULL,
                    success INTEGER NOT NULL,
                    client_ip TEXT,
                    user_agent TEXT,
                    details_json TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    FOREIGN KEY(user_id) REFERENCES users(id)
                );
                """
            )

    def count_users(self) -> int:
        with self._connect() as connection:
            row = connection.execute("SELECT COUNT(*) AS count FROM users").fetchone()
        return int(row["count"])

    def get_user_by_username(self, username: str) -> sqlite3.Row | None:
        with self._connect() as connection:
            return connection.execute(
                """
                SELECT id, username, password_salt, password_hash, is_admin, is_active, last_login_at
                FROM users
                WHERE username = ?
                """,
                (username.lower(),),
            ).fetchone()

    def get_user_by_id(self, user_id: str) -> sqlite3.Row | None:
        with self._connect() as connection:
            return connection.execute(
                """
                SELECT id, username, is_admin, is_active, last_login_at
                FROM users
                WHERE id = ?
                """,
                (user_id,),
            ).fetchone()

    def create_user(self, username: str, password: str, is_admin: bool = False) -> sqlite3.Row:
        normalized = username.strip().lower()
        if len(normalized) < 3:
            raise HTTPException(status_code=400, detail="Username must be at least 3 characters")
        if len(password) < 12:
            raise HTTPException(status_code=400, detail="Password must be at least 12 characters")

        user_id = str(uuid.uuid4())
        now = _utcnow().isoformat()
        salt = secrets.token_bytes(16)
        with self._connect() as connection:
            try:
                connection.execute(
                    """
                    INSERT INTO users (
                        id, username, password_salt, password_hash, is_admin, is_active,
                        created_at, updated_at
                    )
                    VALUES (?, ?, ?, ?, ?, 1, ?, ?)
                    """,
                    (
                        user_id,
                        normalized,
                        _encode_b64url(salt),
                        _password_hash(password, salt),
                        int(is_admin),
                        now,
                        now,
                    ),
                )
            except sqlite3.IntegrityError:
                raise HTTPException(status_code=409, detail="Username already exists") from None
        user = self.get_user_by_id(user_id)
        if user is None:
            raise RuntimeError("Failed to create user")
        return user

    def touch_last_login(self, user_id: str) -> None:
        with self._connect() as connection:
            connection.execute(
                "UPDATE users SET last_login_at = ?, updated_at = ? WHERE id = ?",
                (_utcnow().isoformat(), _utcnow().isoformat(), user_id),
            )

    def update_user_password(self, user_id: str, password: str) -> None:
        salt = secrets.token_bytes(16)
        now = _utcnow().isoformat()
        with self._connect() as connection:
            connection.execute(
                """
                UPDATE users
                SET password_salt = ?, password_hash = ?, updated_at = ?
                WHERE id = ?
                """,
                (
                    _encode_b64url(salt),
                    _password_hash(password, salt),
                    now,
                    user_id,
                ),
            )

    def create_refresh_token(
        self,
        user_id: str,
        refresh_token: str,
        expires_at: datetime,
        client_ip: str | None,
        user_agent: str | None,
    ) -> None:
        with self._connect() as connection:
            connection.execute(
                """
                INSERT INTO refresh_tokens (
                    id, user_id, token_hash, created_at, expires_at, client_ip, user_agent
                )
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    str(uuid.uuid4()),
                    user_id,
                    _token_hash(refresh_token),
                    _utcnow().isoformat(),
                    expires_at.isoformat(),
                    client_ip,
                    user_agent,
                ),
            )

    def get_refresh_token(self, refresh_token: str) -> sqlite3.Row | None:
        token_hash = _token_hash(refresh_token)
        with self._connect() as connection:
            return connection.execute(
                """
                SELECT id, user_id, token_hash, expires_at, revoked_at
                FROM refresh_tokens
                WHERE token_hash = ?
                """,
                (token_hash,),
            ).fetchone()

    def touch_refresh_token(self, refresh_token: str) -> None:
        with self._connect() as connection:
            connection.execute(
                "UPDATE refresh_tokens SET last_used_at = ? WHERE token_hash = ?",
                (_utcnow().isoformat(), _token_hash(refresh_token)),
            )

    def revoke_refresh_token(self, refresh_token: str) -> None:
        with self._connect() as connection:
            connection.execute(
                "UPDATE refresh_tokens SET revoked_at = ? WHERE token_hash = ?",
                (_utcnow().isoformat(), _token_hash(refresh_token)),
            )

    def revoke_all_refresh_tokens_for_user(self, user_id: str) -> None:
        with self._connect() as connection:
            connection.execute(
                """
                UPDATE refresh_tokens
                SET revoked_at = COALESCE(revoked_at, ?)
                WHERE user_id = ?
                """,
                (_utcnow().isoformat(), user_id),
            )

    def record_activity(
        self,
        action: str,
        success: bool,
        client_ip: str | None,
        user_agent: str | None,
        user: AuthenticatedUser | None = None,
        details: dict[str, Any] | None = None,
    ) -> None:
        with self._connect() as connection:
            connection.execute(
                """
                INSERT INTO activity_log (
                    user_id, username, action, success, client_ip, user_agent, details_json, created_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    user.id if user else None,
                    user.username if user else None,
                    action,
                    int(success),
                    client_ip,
                    user_agent,
                    json.dumps(details or {}, separators=(",", ":"), sort_keys=True),
                    _utcnow().isoformat(),
                ),
            )

    def recent_activity(self, limit: int = 100) -> list[dict[str, Any]]:
        with self._connect() as connection:
            rows = connection.execute(
                """
                SELECT id, user_id, username, action, success, client_ip, user_agent, details_json, created_at
                FROM activity_log
                ORDER BY id DESC
                LIMIT ?
                """,
                (limit,),
            ).fetchall()
        return [
            {
                "id": row["id"],
                "user_id": row["user_id"],
                "username": row["username"],
                "action": row["action"],
                "success": bool(row["success"]),
                "client_ip": row["client_ip"],
                "user_agent": row["user_agent"],
                "details": json.loads(row["details_json"]),
                "created_at": row["created_at"],
            }
            for row in rows
        ]


class AuthService:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.repo = AuthRepository(settings.auth_database_path)

    def ensure_bootstrap_admin(self) -> None:
        username = self.settings.app_bootstrap_admin_username.strip().lower()
        password = self.settings.app_bootstrap_admin_password
        if len(password) < 12:
            raise RuntimeError(
                "APP_BOOTSTRAP_ADMIN_PASSWORD must be set to a strong value before first startup"
            )
        user_row = self.repo.get_user_by_username(username)
        if user_row is None:
            if self.repo.count_users() > 0:
                return
            self.repo.create_user(username, password, is_admin=True)
            return

        password_salt = _decode_b64url(str(user_row["password_salt"]))
        candidate = _password_hash(password, password_salt)
        if hmac.compare_digest(candidate, str(user_row["password_hash"])):
            return

        self.repo.update_user_password(str(user_row["id"]), password)
        self.repo.revoke_all_refresh_tokens_for_user(str(user_row["id"]))

    def register_user(
        self,
        username: str,
        password: str,
        registration_code: str | None,
        request: Request | None,
    ) -> AuthenticatedUser:
        if not self.settings.app_registration_enabled:
            raise HTTPException(status_code=403, detail="Self-registration is disabled")
        expected_code = self.settings.app_registration_code
        if not expected_code or not registration_code or not hmac.compare_digest(
            registration_code, expected_code
        ):
            self.record_activity(
                "auth.register",
                False,
                request=request,
                details={"username": username, "reason": "invalid_registration_code"},
            )
            raise HTTPException(status_code=403, detail="Invalid registration code")
        user_row = self.repo.create_user(username, password, is_admin=False)
        user = self._to_user(user_row)
        self.record_activity(
            "auth.register",
            True,
            user=user,
            request=request,
            details={"username": user.username},
        )
        return user

    def create_user(
        self, username: str, password: str, is_admin: bool, actor: AuthenticatedUser, request: Request
    ) -> AuthenticatedUser:
        if not actor.is_admin:
            raise HTTPException(status_code=403, detail="Admin access required")
        user_row = self.repo.create_user(username, password, is_admin=is_admin)
        user = self._to_user(user_row)
        self.record_activity(
            "admin.user.create",
            True,
            user=actor,
            request=request,
            details={"created_username": user.username, "is_admin": is_admin},
        )
        return user

    def login(self, username: str, password: str, request: Request | None) -> dict[str, Any]:
        user_row = self.repo.get_user_by_username(username.strip().lower())
        if not user_row or not bool(user_row["is_active"]):
            self.record_activity(
                "auth.login",
                False,
                request=request,
                details={"username": username, "reason": "invalid_credentials"},
            )
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid username or password",
            )

        password_salt = _decode_b64url(str(user_row["password_salt"]))
        candidate = _password_hash(password, password_salt)
        if not hmac.compare_digest(candidate, str(user_row["password_hash"])):
            self.record_activity(
                "auth.login",
                False,
                request=request,
                details={"username": username, "reason": "invalid_credentials"},
            )
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid username or password",
            )

        user = self._to_user(user_row)
        self.repo.touch_last_login(user.id)
        session = self._issue_session(user, request)
        self.record_activity(
            "auth.login",
            True,
            user=user,
            request=request,
            details={"username": user.username},
        )
        return session

    def refresh_session(self, refresh_token: str, request: Request | None) -> dict[str, Any]:
        token_row = self.repo.get_refresh_token(refresh_token)
        if token_row is None or token_row["revoked_at"]:
            self.record_activity(
                "auth.refresh",
                False,
                request=request,
                details={"reason": "invalid_refresh_token"},
            )
            raise_auth_error("Refresh token is invalid")

        if datetime.fromisoformat(str(token_row["expires_at"])) <= _utcnow():
            self.repo.revoke_refresh_token(refresh_token)
            self.record_activity(
                "auth.refresh",
                False,
                request=request,
                details={"reason": "refresh_token_expired"},
            )
            raise_auth_error("Refresh token expired")

        user_row = self.repo.get_user_by_id(str(token_row["user_id"]))
        if user_row is None or not bool(user_row["is_active"]):
            self.repo.revoke_refresh_token(refresh_token)
            raise_auth_error()

        self.repo.touch_refresh_token(refresh_token)
        user = self._to_user(user_row)
        session = self._issue_session(user, request)
        self.repo.revoke_refresh_token(refresh_token)
        self.record_activity(
            "auth.refresh",
            True,
            user=user,
            request=request,
            details={"username": user.username},
        )
        return session

    def logout(self, refresh_token: str, user: AuthenticatedUser, request: Request | None) -> None:
        self.repo.revoke_refresh_token(refresh_token)
        self.record_activity("auth.logout", True, user=user, request=request)

    def restart_system(self, actor: AuthenticatedUser, request: Request | None) -> None:
        if not actor.is_admin:
            raise HTTPException(status_code=403, detail="Admin access required")
        try:
            subprocess.Popen(
                ["/bin/sh", "-lc", self.settings.system_restart_command],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except Exception as exc:
            self.record_activity(
                "system.restart",
                False,
                user=actor,
                request=request,
                details={"error": str(exc)},
            )
            raise HTTPException(status_code=500, detail="Could not trigger Raspberry Pi restart") from exc
        self.record_activity("system.restart", True, user=actor, request=request)

    def create_access_token(self, user: AuthenticatedUser) -> str:
        header = {"alg": "HS256", "typ": "JWT"}
        payload = {
            "sub": user.id,
            "username": user.username,
            "is_admin": user.is_admin,
            "type": "access",
            "jti": str(uuid.uuid4()),
            "iat": int(time.time()),
            "exp": int(time.time()) + self.settings.access_token_ttl_seconds,
        }
        header_segment = _encode_b64url(
            json.dumps(header, separators=(",", ":"), sort_keys=True).encode()
        )
        payload_segment = _encode_b64url(
            json.dumps(payload, separators=(",", ":"), sort_keys=True).encode()
        )
        signing_input = f"{header_segment}.{payload_segment}"
        signature = _encode_b64url(
            hmac.new(
                self.settings.app_auth_secret.encode(),
                signing_input.encode(),
                hashlib.sha256,
            ).digest()
        )
        return f"{signing_input}.{signature}"

    def verify_access_token(self, token: str | None) -> AuthenticatedUser:
        if not token:
            raise_auth_error()
        try:
            header_segment, payload_segment, signature = token.split(".")
        except ValueError:
            raise_auth_error()
        signing_input = f"{header_segment}.{payload_segment}"
        expected = _encode_b64url(
            hmac.new(
                self.settings.app_auth_secret.encode(),
                signing_input.encode(),
                hashlib.sha256,
            ).digest()
        )
        if not hmac.compare_digest(signature, expected):
            raise_auth_error()
        try:
            payload = json.loads(_decode_b64url(payload_segment))
        except Exception:
            raise_auth_error()
        if payload.get("type") != "access":
            raise_auth_error()
        if int(payload.get("exp", 0)) < int(time.time()):
            raise_auth_error("Session expired")
        user_row = self.repo.get_user_by_id(str(payload.get("sub", "")))
        if user_row is None or not bool(user_row["is_active"]):
            raise_auth_error()
        return self._to_user(user_row)

    def recent_activity(self, actor: AuthenticatedUser, limit: int = 100) -> list[dict[str, Any]]:
        if not actor.is_admin:
            raise HTTPException(status_code=403, detail="Admin access required")
        return self.repo.recent_activity(limit=limit)

    def record_activity(
        self,
        action: str,
        success: bool,
        user: AuthenticatedUser | None = None,
        request: Request | None = None,
        details: dict[str, Any] | None = None,
    ) -> None:
        self.repo.record_activity(
            action=action,
            success=success,
            user=user,
            client_ip=_client_ip(request),
            user_agent=_user_agent(request),
            details=details,
        )

    def _issue_session(self, user: AuthenticatedUser, request: Request | None) -> dict[str, Any]:
        access_token = self.create_access_token(user)
        refresh_token = secrets.token_urlsafe(48)
        refresh_expires_at = datetime.fromtimestamp(
            time.time() + self.settings.refresh_token_ttl_seconds, tz=UTC
        )
        self.repo.create_refresh_token(
            user_id=user.id,
            refresh_token=refresh_token,
            expires_at=refresh_expires_at,
            client_ip=_client_ip(request),
            user_agent=_user_agent(request),
        )
        return {
            "access_token": access_token,
            "refresh_token": refresh_token,
            "token_type": "Bearer",
            "expires_in": self.settings.access_token_ttl_seconds,
            "user": {
                "id": user.id,
                "username": user.username,
                "is_admin": user.is_admin,
            },
        }

    def _to_user(self, row: sqlite3.Row) -> AuthenticatedUser:
        return AuthenticatedUser(
            id=str(row["id"]),
            username=str(row["username"]),
            is_admin=bool(row["is_admin"]),
        )


def _client_ip(request: Request | None) -> str | None:
    if request is None:
        return None
    forwarded_for = request.headers.get("x-forwarded-for", "").split(",")[0].strip()
    if forwarded_for:
        return forwarded_for
    return request.client.host if request.client else None


def _user_agent(request: Request | None) -> str | None:
    if request is None:
        return None
    return request.headers.get("user-agent")


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
) -> AuthenticatedUser:
    token = credentials.credentials if credentials else None
    return auth.verify_access_token(token)


def require_admin(user: Annotated[AuthenticatedUser, Depends(require_user)]) -> AuthenticatedUser:
    if not user.is_admin:
        raise HTTPException(status_code=403, detail="Admin access required")
    return user


async def require_websocket_user(websocket: WebSocket, auth: AuthService) -> AuthenticatedUser:
    token = websocket.query_params.get("token")
    try:
        return auth.verify_access_token(token)
    except HTTPException:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        raise
