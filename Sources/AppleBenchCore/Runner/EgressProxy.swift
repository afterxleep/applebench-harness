import Foundation
import Network

/// A local HTTPS `CONNECT` proxy that lets an agent reach its model provider
/// and nothing else.
///
/// The sandbox profile cannot tell the agent CLI's own API calls from a
/// `curl` the model runs in a shell: both are the same process tree. So the
/// profile denies every outbound connection except to localhost, the agent
/// is pointed at this proxy, and the proxy tunnels only to the provider's
/// API hosts. A model that fetches documentation, installs a package or
/// searches the web gets a refusal, and the refusal is logged.
public final class EgressProxy: @unchecked Sendable {
    public let allowedHosts: Set<String>
    public private(set) var port: UInt16 = 0
    private let listener: NWListener
    private let queue = DispatchQueue(label: "applebench.egress-proxy")
    private let lock = NSLock()
    private var log: [String] = []

    /// The API hosts each provider prefix needs. A provider not listed here
    /// gets no outside host at all; a custom endpoint on localhost still works.
    public static func hosts(forModel model: String?) -> Set<String> {
        let provider = model?.split(separator: "/").first.map(String.init) ?? ""
        switch provider {
        case "anthropic": return ["api.anthropic.com"]
        case "openrouter": return ["openrouter.ai"]
        case "openai": return ["api.openai.com", "chatgpt.com", "auth.openai.com"]
        case "minimax": return ["api.minimax.io", "api.minimaxi.com"]
        case "zai", "z-ai", "zai-coding-plan": return ["api.z.ai"]
        default: return []
        }
    }

    public init(allowedHosts: Set<String>) throws {
        self.allowedHosts = Set(allowedHosts.map { $0.lowercased() })
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    /// Starts listening on an ephemeral loopback port and returns it.
    public func start() throws -> UInt16 {
        let ready = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable { var error: Error? }
        let box = Box()
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: ready.signal()
            case .failed(let error): box.error = error; ready.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
        if ready.wait(timeout: .now() + 5) == .timedOut {
            throw BenchmarkFailure.agentLaunchFailure("The egress proxy did not start.")
        }
        if let failure = box.error { throw failure }
        guard let port = listener.port?.rawValue else {
            throw BenchmarkFailure.agentLaunchFailure("The egress proxy has no port.")
        }
        self.port = port
        return port
    }

    public func stop() {
        listener.cancel()
    }

    /// Every decision, in order: `ALLOW host:port` or `DENY host:port`.
    public var decisions: [String] {
        lock.lock(); defer { lock.unlock() }
        return log
    }

    /// The environment that routes an agent's HTTPS through this proxy.
    public var environment: [String: String] {
        let url = "http://127.0.0.1:\(port)"
        return [
            "HTTPS_PROXY": url, "HTTP_PROXY": url, "ALL_PROXY": url,
            "https_proxy": url, "http_proxy": url, "all_proxy": url,
            "NO_PROXY": "localhost,127.0.0.1,::1", "no_proxy": "localhost,127.0.0.1,::1",
        ]
    }

    private func record(_ line: String) {
        lock.lock(); log.append(line); lock.unlock()
    }

    private func accept(_ client: NWConnection) {
        client.start(queue: queue)
        readHeader(client, buffer: Data())
    }

    private func readHeader(_ client: NWConnection, buffer: Data) {
        client.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, done, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let header = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
                let rest = buffer[end.upperBound...]
                self.route(client, header: header, rest: Data(rest))
            } else if done || error != nil || buffer.count > 65536 {
                client.cancel()
            } else {
                self.readHeader(client, buffer: buffer)
            }
        }
    }

    private func route(_ client: NWConnection, header: String, rest: Data) {
        let request = header.split(separator: "\r\n").first.map(String.init) ?? ""
        let parts = request.split(separator: " ").map(String.init)
        guard parts.count >= 2, parts[0].uppercased() == "CONNECT" else {
            record("DENY \(parts.dropFirst().first ?? request) (not CONNECT)")
            refuse(client)
            return
        }
        let target = parts[1]
        guard let colon = target.lastIndex(of: ":"),
              let port = UInt16(target[target.index(after: colon)...]) else {
            record("DENY \(target)")
            refuse(client)
            return
        }
        let host = String(target[..<colon]).trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        guard port == 443, allowedHosts.contains(host) else {
            record("DENY \(host):\(port)")
            refuse(client)
            return
        }
        record("ALLOW \(host):\(port)")
        let upstream = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        upstream.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                client.send(content: Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8), completion: .contentProcessed { _ in
                    if !rest.isEmpty { upstream.send(content: rest, completion: .contentProcessed { _ in }) }
                    self.pipe(from: client, to: upstream)
                    self.pipe(from: upstream, to: client)
                })
            case .failed, .cancelled:
                client.cancel()
            default:
                break
            }
        }
        upstream.start(queue: queue)
    }

    private func refuse(_ client: NWConnection) {
        client.send(
            content: Data("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8),
            completion: .contentProcessed { _ in client.cancel() }
        )
    }

    private func pipe(from source: NWConnection, to destination: NWConnection) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
            if let data, !data.isEmpty {
                destination.send(content: data, completion: .contentProcessed { _ in
                    if done || error != nil {
                        destination.cancel(); source.cancel()
                    } else {
                        self?.pipe(from: source, to: destination)
                    }
                })
            } else if done || error != nil {
                destination.cancel(); source.cancel()
            } else {
                self?.pipe(from: source, to: destination)
            }
        }
    }
}
