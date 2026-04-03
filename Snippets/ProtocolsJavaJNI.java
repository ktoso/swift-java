// snippet.protocolUsageJava
@Test
void test() {
    try (var arena = SwiftArena.ofConfined()) {
        ConcreteProtocolAB proto1 = ConcreteProtocolAB.init(10, 5, arena);
        ConcreteProtocolAB proto2 = ConcreteProtocolAB.init(20, 1, arena);

        // Pass concrete Swift types to protocol-typed parameters
        assertEquals(30, MySwiftLibrary.takeProtocol(proto1, proto2));
        assertEquals(15, MySwiftLibrary.takeCombinedProtocol(proto1));

        // Use protocol interface directly
        ProtocolA proto = proto1;
        assertEquals(10, proto.getConstantA());
        assertEquals("ConcreteProtocolAB", proto.name());
    }
}
// snippet.end
