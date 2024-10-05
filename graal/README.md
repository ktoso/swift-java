# Swift + Graal native-image interop example

This is a small PoC that shows how to build a Java class into a native dynamic library (i.e. `.dylib` on macOS) and call it directly from Swift.

This example utilizes native-image and its generated C/C++ headers, so in that sense,
this is using Swift's native C/C++ interop rather than any Java specific functionality.

This also means that there is no JVM involved, however the Java code still has a 
GC which is embedded in the dylib. 

Further exploration of this idea may lead us to making calls with JEP-454 directly 
into the native library and reuse existing jextract-swift concepts to do so.

## Example

Build the java code and swift library:

```
make
```

Run the Swift app that calls directly into the Java native-image compiled dynamic library:

```
> DYLD_LIBRARY_PATH=.build/arm64-apple-macosx/debug swift run
Building for debugging...
Build complete! (0.40s)

Graal native-image demo: libenvmap.dylib (Java native-image compiled library)
Calling into JEnvMap...
[java] JAVA_HOME=/Users/ktoso/.sdkman/candidates/java/23-graalce
[swift] Number env variables with [JAVA] in the name: 1
```