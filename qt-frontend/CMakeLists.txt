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
