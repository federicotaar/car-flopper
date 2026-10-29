import Foundation

// MARK: - Shared protocol models (must stay in sync with server/worker.js)

struct RoomPlayer: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var color: Int
    var x: Float
    var z: Float
    var ry: Float
    var moving: Bool
    var repairing: String?
}

struct PartState: Codable, Equatable {
    var progress: Float // 0...1
    var fixers: Int
}

struct RoomSnapshot: Codable, Equatable {
    var code: String
    var phase: String // "lobby" | "play" | "complete" | "finished"
    var carIndex: Int
    var hostId: String
    var players: [RoomPlayer]
    var parts: [String: PartState]
}

enum NetError: Error, LocalizedError {
    case badURL, roomNotFound, roomFull, server(String)
    var errorDescription: String? {
        switch self {
        case .badURL: return "Bad server URL"
        case .roomNotFound: return "Room not found - check the code"
        case .roomFull: return "Room is full (4 players)"
        case .server(let m): return m
        }
    }
}

final class RoomClient {
    // Central place for the server address; swapped when the Worker is deployed.
    static let httpBase = "https://garage-squad-api.federicotaranu.site"
    static var wsBase: String { httpBase.replacingOccurrences(of: "https://", with: "wss://") }

    static func createRoom() async throws -> String {
        guard let url = URL(string: "\(httpBase)/rooms") else { throw NetError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let obj = try? JSONDecoder().decode([String: String].self, from: data),
              let code = obj["code"] else { throw NetError.server("Could not create room") }
        return code
    }

    static func roomExists(_ code: String) async throws -> Bool {
        guard let url = URL(string: "\(httpBase)/rooms/\(code.uppercased())") else { throw NetError.badURL }
        let (_, resp) = try await URLSession.shared.data(from: url)
        guard let http = resp as? HTTPURLResponse else { throw NetError.server("No response") }
        if http.statusCode == 404 { return false }
        if http.statusCode == 409 { throw NetError.roomFull }
        return http.statusCode == 200
    }
}

// MARK: - Live websocket session

protocol GameSessionDelegate: AnyObject {
    func session(_ s: GameSession, didReceive snapshot: RoomSnapshot)
    func session(_ s: GameSession, didGetEvent kind: String, payload: [String: String])
    func sessionDidClose(_ s: GameSession, reason: String)
}

final class GameSession: NSObject, URLSessionWebSocketDelegate {
    let code: String
    let name: String
    weak var delegate: GameSessionDelegate?
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var closed = false

    var snapshot: RoomSnapshot?
    private(set) var myId: String?

    init(code: String, name: String) {
        self.code = code.uppercased()
        self.name = name
    }

    func connect() throws {
        guard var c = URLComponents(string: "\(RoomClient.wsBase)/rooms/\(code)/ws") else { throw NetError.badURL }
        c.queryItems = [URLQueryItem(name: "name", value: name)]
        guard let url = c.url else { throw NetError.badURL }
        let s = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        self.session = s
        let t = s.webSocketTask(with: url)
        self.task = t
        t.resume()
        receive()
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self, !self.closed else { return }
            switch result {
            case .success(let msg):
                switch msg {
                case .string(let text): self.handle(text)
                case .data(let d): if let text = String(data: d, encoding: .utf8) { self.handle(text) }
                @unknown default: break
                }
                self.receive()
            case .failure(let err):
                self.delegate?.sessionDidClose(self, reason: err.localizedDescription)
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let t = obj["t"] as? String else { return }
        if t == "welcome", let id = obj["id"] as? String {
            self.myId = id
        } else if t == "state", let payload = obj["room"],
           let pd = try? JSONSerialization.data(withJSONObject: payload),
           let snap = try? JSONDecoder().decode(RoomSnapshot.self, from: pd) {
            self.snapshot = snap
            delegate?.session(self, didReceive: snap)
        } else if t == "event", let kind = obj["kind"] as? String {
            var payload: [String: String] = [:]
            for (k, v) in obj where k != "t" && k != "kind" {
                if let s = v as? String { payload[k] = s }
            }
            delegate?.session(self, didGetEvent: kind, payload: payload)
        } else if t == "error", let m = obj["message"] as? String {
            delegate?.sessionDidClose(self, reason: m)
        }
    }

    private func send(_ dict: [String: Any]) {
        guard !closed, let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { _ in }
    }

    func sendPosition(x: Float, z: Float, ry: Float, moving: Bool) {
        send(["t": "pos", "x": x, "z": z, "ry": ry, "moving": moving])
    }

    func sendRepair(part: String?, on: Bool) {
        send(["t": "repair", "part": part as Any, "on": on])
    }

    func sendStart() { send(["t": "start"]) }
    func sendNextCar() { send(["t": "next"]) }
    func sendPickCar(_ index: Int) { send(["t": "pick", "car": index]) }

    func close() {
        closed = true
        task?.cancel(with: .normalClosure, reason: nil)
        session?.invalidateAndCancel()
    }
}
