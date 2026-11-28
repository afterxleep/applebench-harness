import AppleBenchAgents
import Testing

@Suite("Agent catalog")
struct AgentCatalogTests {
    @Test("Default registry exposes one shared real-model harness")
    func defaultRegistryExposesOpenCodeAndFixtureAdapters() {
        #expect(
            AgentCatalog.defaultRegistry().registeredIdentifiers
                == ["fake", "opencode", "solution"]
        )
    }
}
