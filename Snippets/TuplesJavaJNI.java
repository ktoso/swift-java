// snippet.tupleUsageJava
@Test
void test() {
    Tuple2<Long, String> result = MySwiftLibrary.returnPair();
    assertEquals(42L, result.$0);
    assertEquals("hello", result.$1);

    String taken = MySwiftLibrary.takePair(new Tuple2<>(99L, "world"));
    assertEquals("99:world", taken);

    // Labeled tuples get named accessors
    var labeled = MySwiftLibrary.labeledTuple();
    assertEquals(10, labeled.x());
    assertEquals(20, labeled.y());
    // Positional access still works
    assertEquals(10, labeled.$0);
}
// snippet.end
