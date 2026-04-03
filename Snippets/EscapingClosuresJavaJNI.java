// snippet.escapingClosureUsageJava
@Test
void test() {
    try (var arena = SwiftArena.ofConfined()) {
        CallbackManager manager = CallbackManager.init(arena);

        AtomicBoolean wasCalled = new AtomicBoolean(false);

        CallbackManager.setCallback.callback callback = () -> {
            wasCalled.set(true);
        };

        manager.setCallback(callback);
        manager.triggerCallback();
        assertTrue(wasCalled.get());

        // Closures are stored — can trigger multiple times
        wasCalled.set(false);
        manager.triggerCallback();
        assertTrue(wasCalled.get());

        // Release the closure on Swift side
        manager.clearCallback();
    }
}
// snippet.end
