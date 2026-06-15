cmake_minimum_required(VERSION 3.21)

project(VokrrQt VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Quick Qml Multimedia WebSockets)

qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(vokrr-qt
    src/main.cpp
)

qt_add_qml_module(vokrr-qt
    URI Vokrr
    VERSION 1.0
    QML_FILES
        qml/App.qml
        qml/Main.qml
        qml/RadarDemoContent.qml
        qml/components/Radar.qml
        qml/components/IconContainer.qml
        qml/components/BulbOn.qml
        qml/components/BulbOff.qml
        qml/components/TubeLightOn.qml
        qml/components/TubeLightOff.qml
        qml/components/CeilingFan.qml
        qml/components/SmartSwitch.qml
        qml/components/SwitchBoard.qml
        qml/components/Button.qml
        qml/components/Card.qml
        qml/components/NeumorphicCard.qml
        qml/components/CPU_animation_bg.qml
        qml/components/app_loader.qml
        qml/components/SocketOn.qml
        qml/components/SocketOff.qml
        qml/roomfinal/CameraLivePanel.qml
        qml/roomfinal/DeviceCard.qml
        qml/roomfinal/DevicePager.qml
        qml/roomfinal/GlassPanel.qml
        qml/roomfinal/MediaPlayerPanel.qml
        qml/roomfinal/RoomDashboard.qml
        qml/roomfinal/RoomHeader.qml
        qml/roomfinal/RoomHeroPanel.qml
        qml/roomfinal/SvgIcon.qml
        qml/roomfinal/ThemeToggle.qml
        qml/roomfinal/ThemeTokens.qml
        qml/roomfinal/WeatherEnvironmentPanel.qml
)

qt_add_resources(vokrr-qt vokrr_assets
    PREFIX "/"
    FILES
        assets/icons/bulb.svg
        assets/icons/Spotify_icon.svg
        assets/icons/lucide/activity.svg
        assets/icons/lucide/air-vent.svg
        assets/icons/lucide/camera.svg
        assets/icons/lucide/chevron-left.svg
        assets/icons/lucide/chevron-right.svg
        assets/icons/lucide/cloud-lightning.svg
        assets/icons/lucide/cloud-rain.svg
        assets/icons/lucide/cloud.svg
        assets/icons/lucide/droplets.svg
        assets/icons/lucide/fan.svg
        assets/icons/lucide/house.svg
        assets/icons/lucide/lightbulb.svg
        assets/icons/lucide/moon.svg
        assets/icons/lucide/music.svg
        assets/icons/lucide/panels-top-left.svg
        assets/icons/lucide/pause.svg
        assets/icons/lucide/play.svg
        assets/icons/lucide/plug.svg
        assets/icons/lucide/power.svg
        assets/icons/lucide/settings.svg
        assets/icons/lucide/skip-back.svg
        assets/icons/lucide/skip-forward.svg
        assets/icons/lucide/snowflake.svg
        assets/icons/lucide/sun.svg
        assets/icons/lucide/thermometer.svg
        assets/icons/lucide/toggle-left.svg
        assets/icons/lucide/tv.svg
        assets/icons/lucide/volume-2.svg
        assets/icons/lucide/wind.svg
        assets/icons/lucide-white/activity.svg
        assets/icons/lucide-white/air-vent.svg
        assets/icons/lucide-white/camera.svg
        assets/icons/lucide-white/chevron-left.svg
        assets/icons/lucide-white/chevron-right.svg
        assets/icons/lucide-white/cloud-lightning.svg
        assets/icons/lucide-white/cloud-rain.svg
        assets/icons/lucide-white/cloud.svg
        assets/icons/lucide-white/droplets.svg
        assets/icons/lucide-white/fan.svg
        assets/icons/lucide-white/house.svg
        assets/icons/lucide-white/lightbulb.svg
        assets/icons/lucide-white/moon.svg
        assets/icons/lucide-white/music.svg
        assets/icons/lucide-white/panels-top-left.svg
        assets/icons/lucide-white/pause.svg
        assets/icons/lucide-white/play.svg
        assets/icons/lucide-white/plug.svg
        assets/icons/lucide-white/power.svg
        assets/icons/lucide-white/settings.svg
        assets/icons/lucide-white/skip-back.svg
        assets/icons/lucide-white/skip-forward.svg
        assets/icons/lucide-white/snowflake.svg
        assets/icons/lucide-white/sun.svg
        assets/icons/lucide-white/thermometer.svg
        assets/icons/lucide-white/toggle-left.svg
        assets/icons/lucide-white/tv.svg
        assets/icons/lucide-white/volume-2.svg
        assets/icons/lucide-white/wind.svg
        assets/icons/back.svg
        assets/icons/back-black.svg
        assets/icons/cpu-architecture-vokrr.svg
        assets/images/room-1.jpg
        assets/images/room-2.jpg
        assets/images/room-3.jpg
        assets/images/bathroom.jpg
        assets/images/bedroom.jpg
        assets/images/dining_room.jpg
        assets/images/gaming_room.jpg
        assets/images/kitchen.jpg
        assets/images/living_room.jpg
)

target_link_libraries(vokrr-qt
    PRIVATE
        Qt6::Quick
        Qt6::Qml
        Qt6::Multimedia
        Qt6::WebSockets
)

install(TARGETS vokrr-qt
    BUNDLE DESTINATION .
    RUNTIME DESTINATION bin
)
