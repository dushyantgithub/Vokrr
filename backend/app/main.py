import logging
from pathlib import Path
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes import router
from app.core.config import get_settings
from app.main_state import build_app_state, set_app_state

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    state = build_app_state()
    Path(state.settings.auth_database_path).parent.mkdir(parents=True, exist_ok=True)
    Path(state.settings.onboarding_database_path).parent.mkdir(parents=True, exist_ok=True)
    Path(state.settings.spotify_token_path).parent.mkdir(parents=True, exist_ok=True)
    set_app_state(state)
    try:
        await state.device_service.sync_states()
    except Exception:
        logger.exception("Initial Home Assistant state sync failed")
    if state.settings.home_assistant_token:
        state.state_sync.start()
    yield
    await state.state_sync.stop()


app = FastAPI(title="Vokrr Backend", version="0.1.0", lifespan=lifespan)

settings = get_settings()
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(router)
