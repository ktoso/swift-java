@Test
void test() {
    // snippet.throwingInitUsageJava
    try (var arena = SwiftArena.ofConfined()) {
        // Throwing initializer
        MySwiftClass c = MySwiftClass.init(true, arena);
        assertEquals(0, c.getX());

        // Throwing initializer that throws
        Exception exception = assertThrows(Exception.class, () -> {
            MySwiftClass.init(true, arena)
        });
        assertEquals("swiftError", exception.getMessage());

        // Optional initializer returns Optional
        Optional<MySwiftClass> maybe = MySwiftClass.init("valid", arena);
        assertTrue(maybe.isPresent());
    }
    // snippet.end
}
