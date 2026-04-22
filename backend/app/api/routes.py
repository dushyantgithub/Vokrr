import httpx
from fastapi import APIRouter, Depends, HTTPException, Query, Request, WebSocket, WebSocketDisconnect, status

from app.domain.models import (
    ActivityLogEntry,
    AuthSessionResponse,
    AuthUser,
    CreateUserRequest,
    Device,
    DeviceSetRequest,
    LoginRequest,
    LogoutRequest,
    RefreshSessionRequest,
    RegisterRequest,
    Room,
    RoomSetRequest,
    Scene,
    SceneRunResponse,
    VoiceCommandRequest,
    VoiceCommandResponse,
    VoiceEventRequest,
)
from app.main_state import AppState, get_app_state
from app.services.auth import (
    AuthService,
    AuthenticatedUser,
    get_auth_service,
    require_admin,
    require_user,
    require_websocket_user,
)
from app.services.device_service import DeviceNotFoundError, UnsupportedCapabilityError
from app.services.scene_service import InvalidSceneActionError, SceneNotFoundError

router = APIRouter()


def _user_model(user: AuthenticatedUser) -> AuthUser:
    return AuthUser(id=user.id, username=user.username, is_admin=user.is_admin)


@router.post("/api/auth/login", response_model=AuthSessionResponse)
async def login(
    payload: LoginRequest,
    request: Request,
    auth: AuthService = Depends(get_auth_service),
) -> AuthSessionResponse:
    session = auth.login(payload.username, payload.password, request)
    return AuthSessionResponse(**session)


@router.post("/api/auth/refresh", response_model=AuthSessionResponse)
async def refresh_session(
    payload: RefreshSessionRequest,
    request: Request,
    auth: AuthService = Depends(get_auth_service),
) -> AuthSessionResponse:
    session = auth.refresh_session(payload.refresh_token, request)
    return AuthSessionResponse(**session)


@router.post("/api/auth/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(
    payload: LogoutRequest,
    request: Request,
    user: AuthenticatedUser = Depends(require_user),
    auth: AuthService = Depends(get_auth_service),
) -> None:
    auth.logout(payload.refresh_token, user, request)


@router.post("/api/auth/register", response_model=AuthUser)
async def register(
    payload: RegisterRequest,
    request: Request,
    auth: AuthService = Depends(get_auth_service),
) -> AuthUser:
    user = auth.register_user(
        username=payload.username,
        password=payload.password,
        registration_code=payload.registration_code,
        request=request,
    )
    return _user_model(user)


@router.get("/api/auth/me", response_model=AuthUser)
async def auth_me(user: AuthenticatedUser = Depends(require_user)) -> AuthUser:
    return _user_model(user)


@router.post("/api/admin/users", response_model=AuthUser)
async def create_user(
    payload: CreateUserRequest,
    request: Request,
    actor: AuthenticatedUser = Depends(require_admin),
    auth: AuthService = Depends(get_auth_service),
) -> AuthUser:
    user = auth.create_user(payload.username, payload.password, payload.is_admin, actor, request)
    return _user_model(user)


@router.get("/api/admin/activity", response_model=list[ActivityLogEntry])
async def admin_activity(
    limit: int = Query(default=100, ge=1, le=500),
    actor: AuthenticatedUser = Depends(require_admin),
    auth: AuthService = Depends(get_auth_service),
) -> list[ActivityLogEntry]:
    return [ActivityLogEntry(**entry) for entry in auth.recent_activity(actor, limit=limit)]


@router.post("/api/auth/kiosk", response_model=AuthSessionResponse)
async def kiosk_login(
    request: Request,
    auth: AuthService = Depends(get_auth_service),
) -> AuthSessionResponse:
    client_host = request.client.host if request.client else ""
    allowed_hosts = {"127.0.0.1", "::1", "localhost"}
    if not auth.settings.kiosk_auto_login or client_host not in allowed_hosts:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Kiosk login unavailable")
    session = auth.login(
        auth.settings.app_bootstrap_admin_username,
        auth.settings.app_bootstrap_admin_password,
        request,
    )
    return AuthSessionResponse(**session)


@router.get("/api/system/health")
async def health(state: AppState = Depends(get_app_state)) -> dict:
    ha = {"ok": False}
    try:
        ha = {"ok": True, "response": await state.ha_client.health()}
    except Exception as exc:
        ha = {"ok": False, "error": str(exc)}
    return {"ok": True, "home_assistant": ha}


@router.get("/api/ha/entities", dependencies=[Depends(require_user)])
async def ha_entities(state: AppState = Depends(get_app_state)) -> list[dict]:
    try:
        return await state.ha_client.states()
    except httpx.HTTPStatusError as exc:
        raise HTTPException(
            status_code=exc.response.status_code,
            detail=f"Home Assistant rejected the request: {exc.response.text}",
        ) from None
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=502,
            detail=f"Could not reach Home Assistant at {state.ha_client.base_url}: {exc}",
        ) from None


@router.get("/api/rooms", response_model=list[Room], dependencies=[Depends(require_user)])
async def rooms(state: AppState = Depends(get_app_state)) -> list[Room]:
    return state.device_service.rooms()


@router.get("/api/rooms/{room_id}", response_model=Room, dependencies=[Depends(require_user)])
async def room(room_id: str, state: AppState = Depends(get_app_state)) -> Room:
    try:
        return state.device_service.room(room_id)
    except DeviceNotFoundError:
        raise HTTPException(status_code=404, detail="Room not found") from None


@router.post(
    "/api/rooms/{room_id}/set",
    response_model=Room,
    dependencies=[Depends(require_user)],
)
async def set_room(
    room_id: str,
    payload: RoomSetRequest,
    request: Request,
    state: AppState = Depends(get_app_state),
    user: AuthenticatedUser = Depends(require_user),
) -> Room:
    try:
        room = await state.device_service.set_room(room_id, payload)
        await state.websocket_manager.broadcast(
            "snapshot",
            {"rooms": [current_room.model_dump() for current_room in state.device_service.rooms()]},
        )
        state.auth_service.record_activity(
            "room.set",
            True,
            user=user,
            request=request,
            details={"room_id": room_id, "state": payload.state},
        )
        return room
    except DeviceNotFoundError:
        state.auth_service.record_activity(
            "room.set", False, user=user, request=request, details={"room_id": room_id}
        )
        raise HTTPException(status_code=404, detail="Room not found") from None
    except UnsupportedCapabilityError as exc:
        state.auth_service.record_activity(
            "room.set",
            False,
            user=user,
            request=request,
            details={"room_id": room_id, "reason": str(exc)},
        )
        raise HTTPException(status_code=400, detail=str(exc)) from None


@router.get("/api/devices", response_model=list[Device], dependencies=[Depends(require_user)])
async def devices(state: AppState = Depends(get_app_state)) -> list[Device]:
    return state.device_service.devices()


@router.get("/api/devices/{device_id}", response_model=Device, dependencies=[Depends(require_user)])
async def device(device_id: str, state: AppState = Depends(get_app_state)) -> Device:
    try:
        return state.device_service.device(device_id)
    except DeviceNotFoundError:
        raise HTTPException(status_code=404, detail="Device not found") from None


@router.get("/api/scenes", response_model=list[Scene], dependencies=[Depends(require_user)])
async def scenes(state: AppState = Depends(get_app_state)) -> list[Scene]:
    return state.scene_service.scenes()


@router.get("/api/scenes/{scene_id}", response_model=Scene, dependencies=[Depends(require_user)])
async def scene(scene_id: str, state: AppState = Depends(get_app_state)) -> Scene:
    try:
        return state.scene_service.scene(scene_id)
    except SceneNotFoundError:
        raise HTTPException(status_code=404, detail="Scene not found") from None


@router.post(
    "/api/scenes/{scene_id}/run",
    response_model=SceneRunResponse,
    dependencies=[Depends(require_user)],
)
async def run_scene(
    scene_id: str,
    request: Request,
    state: AppState = Depends(get_app_state),
    user: AuthenticatedUser = Depends(require_user),
) -> SceneRunResponse:
    try:
        response = await state.scene_service.run(scene_id)
        await state.device_service.sync_states()
        await state.websocket_manager.broadcast(
            "snapshot",
            {"rooms": [room.model_dump() for room in state.device_service.rooms()]},
        )
        await state.websocket_manager.broadcast("scene.ran", response.model_dump())
        state.auth_service.record_activity(
            "scene.run", True, user=user, request=request, details={"scene_id": scene_id}
        )
        return response
    except SceneNotFoundError:
        state.auth_service.record_activity(
            "scene.run", False, user=user, request=request, details={"scene_id": scene_id}
        )
        raise HTTPException(status_code=404, detail="Scene not found") from None
    except InvalidSceneActionError as exc:
        state.auth_service.record_activity(
            "scene.run",
            False,
            user=user,
            request=request,
            details={"scene_id": scene_id, "reason": str(exc)},
        )
        raise HTTPException(status_code=400, detail=str(exc)) from None


@router.post(
    "/api/devices/{device_id}/toggle",
    response_model=Device,
    dependencies=[Depends(require_user)],
)
async def toggle(
    device_id: str,
    request: Request,
    state: AppState = Depends(get_app_state),
    user: AuthenticatedUser = Depends(require_user),
) -> Device:
    try:
        device = await state.device_service.toggle(device_id)
        await state.websocket_manager.broadcast("device.updated", device.model_dump())
        state.auth_service.record_activity(
            "device.toggle", True, user=user, request=request, details={"device_id": device_id}
        )
        return device
    except DeviceNotFoundError:
        state.auth_service.record_activity(
            "device.toggle", False, user=user, request=request, details={"device_id": device_id}
        )
        raise HTTPException(status_code=404, detail="Device not found") from None
    except UnsupportedCapabilityError as exc:
        state.auth_service.record_activity(
            "device.toggle",
            False,
            user=user,
            request=request,
            details={"device_id": device_id, "reason": str(exc)},
        )
        raise HTTPException(status_code=400, detail=str(exc)) from None


@router.post("/api/devices/{device_id}/set", response_model=Device)
async def set_device(
    device_id: str,
    payload: DeviceSetRequest,
    request: Request,
    state: AppState = Depends(get_app_state),
    user: AuthenticatedUser = Depends(require_user),
) -> Device:
    try:
        device = await state.device_service.set_device(device_id, payload)
        await state.websocket_manager.broadcast("device.updated", device.model_dump())
        state.auth_service.record_activity(
            "device.set",
            True,
            user=user,
            request=request,
            details={"device_id": device_id, "payload": payload.model_dump(exclude_none=True)},
        )
        return device
    except DeviceNotFoundError:
        state.auth_service.record_activity(
            "device.set", False, user=user, request=request, details={"device_id": device_id}
        )
        raise HTTPException(status_code=404, detail="Device not found") from None
    except UnsupportedCapabilityError as exc:
        state.auth_service.record_activity(
            "device.set",
            False,
            user=user,
            request=request,
            details={"device_id": device_id, "reason": str(exc)},
        )
        raise HTTPException(status_code=400, detail=str(exc)) from None


@router.post("/api/voice/command", response_model=VoiceCommandResponse)
async def voice_command(
    payload: VoiceCommandRequest,
    request: Request,
    state: AppState = Depends(get_app_state),
    user: AuthenticatedUser = Depends(require_user),
) -> VoiceCommandResponse:
    response = await state.intent_service.handle(payload.text)
    await state.websocket_manager.broadcast("voice.command", response.model_dump())
    state.auth_service.record_activity(
        "voice.command",
        response.understood,
        user=user,
        request=request,
        details={"text": payload.text, "matched_device_ids": response.matched_device_ids},
    )
    return response


@router.post("/api/voice/event", dependencies=[Depends(require_user)])
async def voice_event(
    payload: VoiceEventRequest,
    state: AppState = Depends(get_app_state),
) -> dict:
    await state.websocket_manager.broadcast(
        "voice.status",
        {"status": payload.status, "message": payload.message},
    )
    return {"ok": True}


@router.get("/api/voice/commands", dependencies=[Depends(require_user)])
async def voice_commands(state: AppState = Depends(get_app_state)) -> dict:
    return {
        "targets": {
            "rooms": [room.name for room in state.device_service.rooms()],
            "devices": [
                f"{device.room_name} {device.name}" for device in state.device_service.devices()
            ],
            "global": ["all", "everything", "home"],
        },
        "templates": state.command_catalog.commands(),
    }


@router.websocket("/ws")
async def websocket_endpoint(
    websocket: WebSocket,
    state: AppState = Depends(get_app_state),
    auth: AuthService = Depends(get_auth_service),
) -> None:
    await require_websocket_user(websocket, auth)
    await state.websocket_manager.connect(websocket)
    await websocket.send_json(
        {
            "event": "snapshot",
            "payload": {
                "rooms": [room.model_dump() for room in state.device_service.rooms()],
            },
        }
    )
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        state.websocket_manager.disconnect(websocket)
