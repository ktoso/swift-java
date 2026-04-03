// snippet.rawRepresentableEnumUsageJava
@Test
void test() {
    try (var arena = SwiftArena.ofConfined()) {
        Optional<Alignment> horizontal = Alignment.init("horizontal", arena);
        assertTrue(horizontal.isPresent());
        assertEquals("horizontal", horizontal.get().getRawValue());

        Optional<Alignment> invalid = Alignment.init("invalid", arena);
        assertFalse(invalid.isPresent());
    }
}
// snippet.end
