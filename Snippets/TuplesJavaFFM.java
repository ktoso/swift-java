// snippet.tupleUsageJava
@Test
void test() {
    Tuple2<Integer, Long> result = MySwiftLibrary.ffmTupleReturnPair();
    assertEquals(42, result.$0);
    assertEquals(43L, result.$1);

    long sum = MySwiftLibrary.ffmTupleSumPair(new Tuple2<>(5, 7L));
    assertEquals(12L, sum);
}
// snippet.end
