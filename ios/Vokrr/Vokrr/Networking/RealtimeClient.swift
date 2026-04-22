import Foundation

final class RealtimeClient: NSObject {
    var onEnvelope: ((String, Data) -> Void)?
    var onConnectionChanged: ((Bool) -> Void)?

    private lazy var session: URLSession = {
        URLSession(configuration: .default, delegate: nil, delegateQueue: nil)
    }()

    private var webSocketTask: URLSessionWebSocketTask?
    private var reconnectWorkItem: DispatchWorkItem?
    private var endpoint: URL?
    private var retryAttempt = 0

    func connect(to url: URL) {
        endpoint = url
        reconnectWorkItem?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)

        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()
        onConnectionChanged?(true)
        listen()
    }

    func disconnect() {
        reconnectWorkItem?.cancel()
        endpoint = nil
        retryAttempt = 0
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        onConnectionChanged?(false)
    }

    private func listen() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                self.onConnectionChanged?(false)
                self.scheduleReconnect()
            case .success(let message):
                self.retryAttempt = 0
                switch message {
                case .string(let text):
                    self.handle(text: text)
                case .data(let data):
                    self.handle(data: data)
                @unknown default:
                    break
                }
                self.listen()
            }
        }
    }

    private func handle(text: String) {
        guard let data = text.data(using: .utf8) else { return }
        handle(data: data)
    }

    private func handle(data: Data) {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let event = object["event"] as? String,
            let payload = object["payload"]
        else {
            return
        }

        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload) else {
            return
        }
        onEnvelope?(event, payloadData)
    }

    private func scheduleReconnect() {
        guard let endpoint else { return }
        retryAttempt += 1
        let delay = min(pow(2.0, Double(retryAttempt)), 30.0)
        let workItem = DispatchWorkItem { [weak self] in
            self?.connect(to: endpoint)
        }
        reconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}
