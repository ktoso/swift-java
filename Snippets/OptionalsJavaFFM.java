// snippet.optionalUsageJava
@Test
void test() {
    try (var arena = AllocatingSwiftArena.ofConfined()) {
        // Optional primitives use OptionalLong
        assertEquals(0, MySwiftLibrary.globalReceiveOptional(
            OptionalLong.empty(), Optional.empty()));

        var bytes = arena.allocateFrom("hello");
        var data = Data.init(bytes, bytes.byteSize(), arena);
        assertEquals(3, MySwiftLibrary.globalReceiveOptional(
            OptionalLong.of(12), Optional.of(data)));
    }
}
// snippet.end
