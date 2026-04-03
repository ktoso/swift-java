// snippet.enumUsageJava
@Test
void test() {
    try (var arena = SwiftArena.ofConfined()) {
        Vehicle vehicle = Vehicle.car("BMW", Optional.empty(), arena);
        assertEquals("car", vehicle.getName());

        // Access associated values via getAsX
        Vehicle.Car car = vehicle.getAsCar().orElseThrow();
        assertEquals("BMW", car.arg0());

        // Pattern matching with getCase (Java 21+)
        switch (vehicle.getCase(arena)) {
            case Vehicle.Car c -> assertEquals("BMW", c.arg0());
            default -> fail("Expected car");
        }

        // Discriminator for simple switching
        assertEquals(Vehicle.Discriminator.CAR, vehicle.getDiscriminator());
    }
}
// snippet.end
