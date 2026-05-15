cmake_minimum_required(VERSION 3.21)

project(VokrrQt VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Quick Qml WebSockets)

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
        qml/components/SocketOn.qml
        qml/components/SocketOff.qml
)

qt_add_resources(vokrr-qt vokrr_assets
    PREFIX "/"
    FILES
        assets/icons/bulb.svg
        assets/icons/tab-dashboard.svg
        assets/icons/tab-dashboard-active.svg
        assets/icons/tab-devices.svg
        assets/icons/tab-devices-active.svg
        assets/icons/tab-settings.svg
        assets/icons/tab-settings-active.svg
        assets/images/room-1.jpg
        assets/images/room-2.jpg
        assets/images/room-3.jpg
)

target_link_libraries(vokrr-qt
    PRIVATE
        Qt6::Quick
        Qt6::Qml
        Qt6::WebSockets
)

install(TARGETS vokrr-qt
    BUNDLE DESTINATION .
    RUNTIME DESTINATION bin
)
