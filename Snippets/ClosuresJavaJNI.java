// snippet.closureUsageJava
@Test
void test() {
    // Void closure
    AtomicBoolean called = new AtomicBoolean(false);
    MySwiftLibrary.emptyClosure(() -> called.set(true));
    assertTrue(called.get());

    // Closure with return value
    long result = MySwiftLibrary.closureWithInt(10, (value) -> value * 2);
    assertEquals(20, result);

    // Multi-argument closure
    long sum = MySwiftLibrary.closureMultipleArguments(5, 10, (a, b) -> a + b);
    assertEquals(15, sum);
}
// snippet.end
