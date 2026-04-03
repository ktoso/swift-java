// snippet.classUsageJava
@Test
void test() {
    try (var arena = SwiftArena.ofConfined()) {
        MySwiftClass c = MySwiftClass.init(20, 10, arena);
        assertEquals(30, c.sum());
        assertEquals(200, c.xMultiplied(10));
        assertEquals(200, c.getProduct());
        c.setMutable(42);
        assertEquals(42, c.getMutable());

        // Throwing init
        Exception exception = assertThrows(Exception.class,
            () -> MySwiftClass.init(true, arena));
        assertEquals("swiftError", exception.getMessage());
    }
}
// snippet.end
