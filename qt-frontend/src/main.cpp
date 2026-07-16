#include <QCursor>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QUrl>

int main(int argc, char *argv[])
{
    QCoreApplication::setAttribute(Qt::AA_SynthesizeMouseForUnhandledTouchEvents, true);
    QCoreApplication::setAttribute(Qt::AA_SynthesizeTouchForUnhandledMouseEvents, true);

    qputenv("QT_QUICK_CONTROLS_STYLE", qgetenv("QT_QUICK_CONTROLS_STYLE").isEmpty()
        ? QByteArray("Basic")
        : qgetenv("QT_QUICK_CONTROLS_STYLE"));

    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName("Vokrr");
    QGuiApplication::setApplicationVersion("0.4.1");
    QGuiApplication::setOrganizationName("Vokrr");

    QFontDatabase::addApplicationFont(QStringLiteral(":/qt/qml/Vokrr/assets/fonts/Jost-Latin.woff2"));
    QFontDatabase::addApplicationFont(QStringLiteral(":/qt/qml/Vokrr/assets/fonts/IBMPlexMono-Regular.woff2"));
    QFontDatabase::addApplicationFont(QStringLiteral(":/qt/qml/Vokrr/assets/fonts/IBMPlexMono-Medium.woff2"));

    QQmlApplicationEngine engine;
    const QString apiBase = qEnvironmentVariable("VOKRR_API_BASE", "http://localhost:8080");
    const bool reducedMotion = qEnvironmentVariableIsSet("VOKRR_REDUCED_MOTION");
    engine.rootContext()->setContextProperty(QStringLiteral("vokrrBackendApiBase"), apiBase);
    engine.rootContext()->setContextProperty(QStringLiteral("vokrrReducedMotion"), reducedMotion);

    const QUrl url(QStringLiteral("qrc:/qt/qml/Vokrr/qml/App.qml"));
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);
    engine.load(url);

    const bool windowed = qEnvironmentVariableIsSet("VOKRR_QT_WINDOWED");
    if (!windowed) {
        QGuiApplication::setOverrideCursor(QCursor(Qt::BlankCursor));
        for (QObject *root : engine.rootObjects()) {
            if (auto *window = qobject_cast<QQuickWindow *>(root)) {
                window->setCursor(Qt::BlankCursor);
                window->showFullScreen();
            }
        }
    }

    return app.exec();
}
