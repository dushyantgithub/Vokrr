cmake_minimum_required(VERSION 3.21)

project(VokrrQt VERSION 0.4.1 LANGUAGES CXX)

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
        qml/VokrrGtShell.qml
)

qt_add_resources(vokrr-qt vokrr_assets
    PREFIX "/qt/qml/Vokrr"
    FILES
        assets/fonts/IBMPlexMono-Regular.woff2
        assets/fonts/IBMPlexMono-Medium.woff2
        assets/fonts/Jost-Latin.woff2
        assets/icons/gt/nav-dashboard.svg
        assets/icons/gt/nav-dashboard-active.svg
        assets/icons/gt/nav-rooms.svg
        assets/icons/gt/nav-rooms-active.svg
        assets/icons/gt/nav-health.svg
        assets/icons/gt/nav-health-active.svg
        assets/icons/gt/nav-jarvis.svg
        assets/icons/gt/nav-jarvis-active.svg
        assets/icons/gt/nav-settings.svg
        assets/icons/gt/nav-settings-active.svg
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
