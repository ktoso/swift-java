# Features Overview

Summary of features supported by the swift-java interoperability libraries and tools.

## Overview

SwiftJava supports both directions of interoperability, calling Swift from Java, and calling Java from Swift.
These directions are implemented using different techniques and tools. The table below should help you determine which
you are looking for:

- **Calling Swift from Java:** 
  - `swift-java jextract` source generator -- generates Java code and supporting Swift bridging to call into existing Swift libraries
  - use jextract with `--mode jni` or `--mode ffm` depending on your needs and target JDK 
- **Calling Java from Swift:** 
  - use `@JavaClass` and `@JavaMethod` macros to easily call single one-off methods
  - `swift-java wrap-java` to automatically wrap existing Java libraries for Swift 



### Calling Java from Swift: JavaKit macros

For detailed feature support of the `wrap-java` direction, see <doc:FeaturesJavaKitMacros>.

### Calling Java from Swift: wrap-java

For detailed feature support of the `wrap-java` direction, see <doc:FeaturesWrapJava>.

### jextract – calling Swift from Java

SwiftJava's `swift-java jextract` tool automates generating Java bindings from Swift sources.

> tip: This direction of interoperability is covered in the WWDC2025 session 'Explore Swift and Java interoperability'
> around the [14-minute mark](https://youtu.be/QSHO-GUGidA?si=b9YUwAWDWFGzhRXN&t=842).


| Swift Feature                                                                        | JNI     | FFM     |
|--------------------------------------------------------------------------------------|---------|---------|
| Initializers: `class`, `struct`                                                      | yes     | yes     |
| Optional Initializers / Throwing Initializers                                        | yes     | no      |
| Deinitializers:  `class`, `struct`                                                   | yes     | yes     |
| `enum`                                                                               | yes     | no      |
| `actor`                                                                              | no      | no      |
| Global Swift `func`                                                                  | yes     | yes     |
| Class/struct member `func`                                                           | yes     | yes     |
| Throwing functions: `func x() throws`                                                | yes     | no      |
| Typed throws: `func x() throws(E)`                                                   | no      | no      |
| Stored properties: `var`, `let` (with `willSet`, `didSet`)                           | yes     | yes     |
| Computed properties: `var` (incl. `throws`)                                          | yes     | partial |
| Async functions `func async` and properties: `var { get async {} }`                  | yes     | no      |
| Arrays: `[UInt8]`                                                                    | yes     | yes     |
| Arrays: `[MyType]`, `Array<Int64>` etc                                               | yes     | no      |
| Dictionaries: `[String: Int]`, `[K:V]`                                               | yes     | no      |
| Generic type: `struct S<T>`                                                          | yes     | no      |
| Functions or properties using generic type param: `struct S<T> { func f(_: T) {} }`  | no      | no      |
| Generic parameters over `some DataProtocol` handled with efficient Java type         | yes     | yes     |
| Generic type specialization and conditional extensions: `struct S<T>{} extension S where T == Value {}` | yes | no |
| Static functions or properties in generic type                                       | no      | no      |
| Generic parameters in functions: `func f<T: A & B>(x: T)`                            | yes     | no      |
| Generic return values in functions: `func f<T: A & B>() -> T`                        | no      | no      |
| Tuples: `(Int, String)`, `(A, B, C)`                                                 | yes     | yes     |
| Protocols: `protocol`                                                                | yes     | no      |
| Protocols: `protocol` with associated types                                          | no      | no      |
| Protocols static requirements: `static func`, `init(rawValue:)`                      | no      | no      |
| Existential parameters `f(x: any SomeProtocol)` (excepts `Any`)                      | yes     | no      |
| Existential parameters `f(x: any (A & B)) `                                          | yes     | no      |
| Existential return types `f() -> any Collection`                                     | no      | no      |
| Foundation Data and DataProtocol: `f(x: any DataProtocol) -> Data`                   | yes     | yes     |
| Foundation Date: `f(date: Date) -> Date`                                             | yes     | no      |
| Foundation UUID: `f(uuid: UUID) -> UUID`                                             | yes     | no      |
| Opaque parameters: `func take(worker: some Builder) -> some Builder`                 | yes     | no      |
| Opaque return types: `func get() -> some Builder`                                    | no      | no      |
| Optional parameters: `func f(i: Int?, class: MyClass?)`                              | yes     | yes     |
| Optional return types: `func f() -> Int?`, `func g() -> MyClass?`                    | yes     | no      |
| Primitive types: `Bool`, `Int`, `Int8`, `Int16`, `Int32`, `Int64`, `Float`, `Double` | yes     | yes     |
| Parameters: SwiftJava wrapped types `JavaLong`, `JavaInteger`                          | yes     | no      |
| Return values: SwiftJava wrapped types `JavaLong`, `JavaInteger`                       | no      | no      |
| Unsigned primitive types: `UInt`, `UInt8`, `UInt16`, `UInt32`, `UInt64`              | yes *   | yes *   |
| String (with copying data)                                                           | yes     | yes     |
| Variadic parameters: `T...`                                                          | no      | no      |
| Parameter packs / Variadic generics                                                  | no      | no      |
| Ownership modifiers: `inout`, `borrowing`, `consuming`                               | no      | no      |
| Default parameter values: `func p(name: String = "")`                                | no      | no      |
| Operators: `+`, `-`, user defined                                                    | no      | no      |
| Subscripts: `subscript()`                                                            | yes     | yes     |
| Equatable                                                                            | no      | no      |
| Pointers: `UnsafeRawPointer`                                                         | no      | partial |
| Pointers as parameters: `UnsafeRawBufferPointer` (as `byte[]`)                       | yes     | no      |
| Nested types: `struct Hello { struct World {} }`                                     | yes     | no      |
| Inheritance: `class Caplin: Capybara`                                                | no      | no      |
| Non-escaping `Void` closures: `func callMe(maybe: () -> ())`                                      | yes     | yes     |
| Non-escaping closures with primitive arguments/results: `func callMe(maybe: (Int) -> (Double))`   | yes     | yes     |
| Non-escaping closures with object arguments/results: `func callMe(maybe: (JavaObj) -> (JavaObj))` | no      | no      |
| `@escaping` `Void` closures: `func callMe(_: @escaping () -> ())`                                 | yes     | no      |
| `@escaping` closures with primitive arguments/results: `func callMe(_: @escaping (String) -> (String))`       | yes     | no      |
| `@escaping` closures with custom arguments/results: `func callMe(_: @escaping (Obj) -> (Obj))`       | no      | no      |
| Swift type extensions: `extension String { func uppercased() }`                      | yes     | yes     |
| Swift macros (maybe)                                                                 | no      | no      |
| Result builders                                                                      | no      | no      |
| Automatic Reference Counting of class types / lifetime safety                        | yes     | yes     |
| Value semantic types (e.g. struct copying)                                           | no      | no      |
|                                                                                      |         |         |
|                                                                                      |         |         |

> tip: The list of features may be incomplete, please file an issue if something is unclear or should be clarified in this table.

## Detailed feature documentation by mode

For detailed documentation with code examples for each mode, see:

- <doc:FeaturesJextract>
- <doc:FeaturesWrapJava>
