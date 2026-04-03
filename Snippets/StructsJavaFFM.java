// snippet.structUsageJava
@Test
void test() {
    try (var arena = AllocatingSwiftArena.ofConfined()) {
        MySwiftStruct s = MySwiftStruct.init(1337, 42, arena);
        assertEquals(1337, s.getCapacity());
        assertEquals(42, s.getLen());
        s.setLen(100);
        assertEquals(100, s.getLen());
        long newCap = s.increaseCap(10);
        assertEquals(1347, newCap);
    }
}
// snippet.end
