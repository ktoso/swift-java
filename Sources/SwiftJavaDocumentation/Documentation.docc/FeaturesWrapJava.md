# Features: wrap-java (jni)

Detailed feature documentation for calling Java from Swift using `wrap-java` and JNI macros.

## Overview

SwiftJava macros and the `wrap-java` command simplify implementing Java `native` functions
and calling Java APIs from Swift.

For the full feature matrix, see <doc:FeaturesOverview>.

### Java -> Swift

It is possible to use SwiftJava macros and the `wrap-java` command to simplify implementing
Java `native` functions. SwiftJava simplifies the type conversions.

> tip: This direction of interoperability is covered in the WWDC2025 session 'Explore Swift and Java interoperability'
> around the [7-minute mark](https://youtu.be/QSHO-GUGidA?si=vUXxphTeO-CHVZ3L&t=448).

| Feature                                          | Macro support           |
|--------------------------------------------------|-------------------------|
| Java `static native` method implemented by Swift | yes `@JavaImplementation` |
| **This list is very work in progress**           |                         |

### Swift -> Java

> tip: This direction of interoperability is covered in the WWDC2025 session 'Explore Swift and Java interoperability'
> around the [10-minute mark](https://youtu.be/QSHO-GUGidA?si=QyYP5-p2FL_BH7aD&t=616).

| Java Feature                           | Macro support |
|----------------------------------------|---------------|
| Java `class`                           | yes             |
| Java class inheritance                 | yes             |
| Java `abstract class`                  | TODO          |
| Java `enum`                            | no             |
| Java methods: `static`, member           | yes `@JavaMethod` |
| **This list is very work in progress** |               |
