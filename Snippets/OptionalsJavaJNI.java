// snippet.optionalUsageJava
@Test
void test() {
    assertEquals(OptionalLong.empty(), MySwiftLibrary.optionalLong(OptionalLong.empty()));
    assertEquals(OptionalLong.of(999), MySwiftLibrary.optionalLong(OptionalLong.of(999)));

    assertEquals(Optional.empty(), MySwiftLibrary.optionalString(Optional.empty()));
    assertEquals(Optional.of("Hello Swift!"),
        MySwiftLibrary.optionalString(Optional.of("Hello Swift!")));

    try (var arena = SwiftArena.ofConfined()) {
        MySwiftClass c = MySwiftClass.init(arena);
        Optional<MySwiftClass> opt = MySwiftLibrary.optionalClass(Optional.of(c), arena);
        assertTrue(opt.isPresent());
    }
}
// snippet.end
