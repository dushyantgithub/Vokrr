import httpx
from fastapi import APIRouter, Depends, HTTPException, Request, WebSocket, WebSocketDisconnect, status

from app.domain.models import (
    Device,
    DeviceSetRequest,
    LoginRequest,
    LoginResponse,
    Room,
    RoomSetRequest,
    Scene,
    SceneRunResponse,
    VoiceCommandRequest,
    VoiceCommandResponse,
    VoiceEventRequest,
)
from app.main_state import AppState, get_app_state
from app.services.device_service import DeviceNotFoundError, UnsupportedCapabilityError
from app.services.scene_service import (
    InvalidSceneActionError,
    SceneNotFoundError,
)
from app.services.auth import AuthService, get_auth_service, require_user, require_websocket_user

router = APIRouter()


@router.post("/api/auth/login", response_model=LoginResponse)
async def login(
    request: LoginRequest,
    auth: AuthService = Depends(get_auth_service),
) -> LoginResponse:
    token = auth.login(request.username, request.password)
    return LoginResponse(token=token, username=request.username)


@router.post("/api/auth/kiosk", response_model=LoginResponse)
async def kiosk_login(
    request: Request,
    auth: AuthService = Depends(get_auth_service),
) -> LoginResponse:
    client_host = request.client.host if request.client else ""
    allowed_hosts = {"127.0.0.1", "::1", "localhost"}
    if not auth.settings.kiosk_auto_login or client_host not in allowed_hosts:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Kiosk login unavailable")
    username = "kiosk"
    return LoginResponse(token=auth.create_token(username), username=username)


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
    request: RoomSetRequest,
    state: AppState = Depends(get_app_state),
) -> Room:
    try:
        room = await state.device_service.set_room(room_id, request)
        await state.websocket_manager.broadcast(
            "snapshot",
            {"rooms": [current_room.model_dump() for current_room in state.device_service.rooms()]},
        )
        return room
    except DeviceNotFoundError:
        raise HTTPException(status_code=404, detail="Room not found") from None
    except UnsupportedCapabilityError as exc:
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
async def run_scene(scene_id: str, state: AppState = Depends(get_app_state)) -> SceneRunResponse:
    try:
        response = await state.scene_service.run(scene_id)
        await state.device_service.sync_states()
        await state.websocket_manager.broadcast(
            "snapshot",
            {"rooms": [room.model_dump() for room in state.device_service.rooms()]},
        )
        await state.websocket_manager.broadcast("scene.ran", response.model_dump())
        return response
    except SceneNotFoundError:
        raise HTTPException(status_code=404, detail="Scene not found") from None
    except InvalidSceneActionError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from None


@router.post(
    "/api/devices/{device_id}/toggle",
    response_model=Device,
    dependencies=[Depends(require_user)],
)
async def toggle(device_id: str, state: AppState = Depends(get_app_state)) -> Device:
    try:
        device = await state.device_service.toggle(device_id)
        await state.websocket_manager.broadcast("device.updated", device.model_dump())
        return device
    except DeviceNotFoundError:
        raise HTTPException(status_code=404, detail="Device not found") from None
    except UnsupportedCapabilityError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from None


@router.post("/api/devices/{device_id}/set", response_model=Device)
async def set_device(
    device_id: str,
    request: DeviceSetRequest,
    state: AppState = Depends(get_app_state),
    _user: str = Depends(require_user),
) -> Device:
    try:
        device = await state.device_service.set_device(device_id, request)
        await state.websocket_manager.broadcast("device.updated", device.model_dump())
        return device
    except DeviceNotFoundError:
        raise HTTPException(status_code=404, detail="Device not found") from None
    except UnsupportedCapabilityError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from None


@router.post("/api/voice/command", response_model=VoiceCommandResponse)
async def voice_command(
    request: VoiceCommandRequest,
    state: AppState = Depends(get_app_state),
    _user: str = Depends(require_user),
) -> VoiceCommandResponse:
    response = await state.intent_service.handle(request.text)
    await state.websocket_manager.broadcast("voice.command", response.model_dump())
    return response


@router.post("/api/voice/event", dependencies=[Depends(require_user)])
async def voice_event(
    request: VoiceEventRequest,
    state: AppState = Depends(get_app_state),
) -> dict:
    await state.websocket_manager.broadcast(
        "voice.status",
        {"status": request.status, "message": request.message},
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
