// snippet.dataUsageJava
@Test
void test() {
    try (var arena = AllocatingSwiftArena.ofConfined()) {
        // Create Data from a byte array
        byte[] original = new byte[] { 10, 20, 30, 40 };
        Data data = Data.fromByteArray(original, arena);
        assertEquals(4, data.getCount());

        // Zero-copy access via withUnsafeBytes
        data.withUnsafeBytes((bytes) -> {
            assertEquals(4, bytes.byteSize());
        });

        // Copy to JVM heap when needed
        byte[] copy = data.toByteArray();
        assertArrayEquals(original, copy);
    }
}
// snippet.end
