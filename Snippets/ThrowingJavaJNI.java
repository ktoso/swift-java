// snippet.throwUsageJava
@Test
void test() throws Exception {
    String result = MySwiftLibrary.throwString("hey");
    assertEquals("hey", result);
}
// snippet.end
