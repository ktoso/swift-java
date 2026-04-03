// snippet.genericTypeUsageJava
@Test
void test() {
    try (var arena = SwiftArena.ofConfined()) {
        MyID<String> stringId = MyIDs.makeStringID("Java", arena);
        assertEquals("Java", stringId.getDescription());
        assertEquals("Java", MyIDs.takeStringValue(stringId));

        MyID<Long> intId = MyIDs.makeIntID(42, arena);
        assertEquals("42", intId.getDescription());
        assertEquals(42, MyIDs.takeIntValue(intId));
    }
}
// snippet.end
