from app.domain.models import Scene, SceneRunResponse
from app.services.home_assistant import HomeAssistantClient
from app.services.registry import DeviceRegistry


class SceneNotFoundError(KeyError):
    pass


class InvalidSceneActionError(ValueError):
    pass


class SceneService:
    def __init__(self, registry: DeviceRegistry, ha_client: HomeAssistantClient) -> None:
        self.registry = registry
        self.ha_client = ha_client

    def scenes(self) -> list[Scene]:
        return self.registry.all_scenes()

    def scene(self, scene_id: str) -> Scene:
        scene = self.registry.get_scene(scene_id)
        if not scene:
            raise SceneNotFoundError(scene_id)
        return scene

    async def run(self, scene_id: str) -> SceneRunResponse:
        scene = self.scene(scene_id)
        for action in scene.actions:
            if "." not in action.service:
                raise InvalidSceneActionError(f"Invalid service '{action.service}'")
            domain, service = action.service.split(".", 1)
            service_data = {**action.data}
            if action.target:
                service_data.update(action.target)
            await self.ha_client.call_service(domain, service, service_data)

        return SceneRunResponse(
            id=scene.id,
            name=scene.name,
            executed_actions=len(scene.actions),
        )
