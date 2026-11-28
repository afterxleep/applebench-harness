import Foundation
import Network
import Testing
@testable import AppleBenchCore

@Suite("Egress proxy")
struct EgressProxyTests {
    @Test("Providers map to their API hosts and nothing else")
    func providerHosts() {
        #expect(EgressProxy.hosts(forModel: "anthropic/claude-opus-5-5") == ["api.anthropic.com"])
        #expect(EgressProxy.hosts(forModel: "openrouter/z-ai/glm-5.3-flash") == ["openrouter.ai"])
        #expect(EgressProxy.hosts(forModel: "unknown/model").isEmpty)
    }

    @Test("A tunnel to a host that is not the provider is refused and logged")
    func refusesOtherHosts() async throws {
        let proxy = try EgressProxy(allowedHosts: ["api.anthropic.com"])
        let port = try proxy.start()
        defer { proxy.stop() }
        let reply = try await Self.connect(port: port, request: "CONNECT developer.apple.com:443 HTTP/1.1\r\nHost: developer.apple.com:443\r\n\r\n")
        #expect(reply.hasPrefix("HTTP/1.1 403"))
        #expect(proxy.decisions == ["DENY developer.apple.com:443"])
    }

    @Test("A plain HTTP request through the proxy is refused")
    func refusesPlainHTTP() async throws {
        let proxy = try EgressProxy(allowedHosts: ["api.anthropic.com"])
        let port = try proxy.start()
        defer { proxy.stop() }
        let reply = try await Self.connect(port: port, request: "GET http://example.com/ HTTP/1.1\r\nHost: example.com\r\n\r\n")
        #expect(reply.hasPrefix("HTTP/1.1 403"))
    }

    @Test("A sealed profile allows only localhost and denies the host's listening ports")
    func localOnlyProfile() {
        let box = AgentSandbox(deniedReadPaths: [], workspaceURL: URL(fileURLWithPath: "/w"))
            .restrictingNetworkToLocalhost(exceptPorts: [7000])
        let profile = box.profile()
        #expect(profile.contains("(deny network-outbound)"))
        #expect(profile.contains(#"(allow network-outbound (remote ip "localhost:*"))"#))
        #expect(profile.contains(#"(deny network-outbound (remote ip "localhost:7000"))"#))
        let allow = profile.range(of: #"(allow network-outbound (remote ip "localhost:*"))"#)!
        let deny = profile.range(of: #"(deny network-outbound (remote ip "localhost:7000"))"#)!
        #expect(allow.lowerBound < deny.lowerBound)
    }

    private static func connect(port: UInt16, request: String) async throws -> String {
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        let queue = DispatchQueue(label: "egress-test")
        return try await withCheckedThrowingContinuation { continuation in
            connection.stateUpdateHandler = { state in
                if case .ready = state {
                    connection.send(content: Data(request.utf8), completion: .contentProcessed { _ in
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, error in
                            connection.cancel()
                            if let error { continuation.resume(throwing: error) }
                            else { continuation.resume(returning: String(decoding: data ?? Data(), as: UTF8.self)) }
                        }
                    })
                } else if case .failed(let error) = state {
                    continuation.resume(throwing: error)
                }
            }
            connection.start(queue: queue)
        }
    }
}
