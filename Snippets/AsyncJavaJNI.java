// snippet.asyncUsageJava
@Test
void test() throws Exception {
    // Async functions return Future (or CompletableFuture)
    Future<Long> future = MySwiftLibrary.asyncSum(10, 12);
    assertEquals(22, future.get());

    // Async throwing functions propagate exceptions
    Future<Void> sleepFuture = MySwiftLibrary.asyncSleep();
    sleepFuture.get(); // blocks until complete

    // Async with String
    Future<String> stringFuture = MySwiftLibrary.asyncString("hello");
    assertEquals("hello", stringFuture.get());

    // Async that throws
    Future<Void> throwFuture = MySwiftLibrary.asyncThrows();
    ExecutionException ex = assertThrows(ExecutionException.class, throwFuture::get);
    assertEquals("swiftError", ex.getCause().getMessage());
}
// snippet.end
