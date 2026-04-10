//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift.org project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift.org project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

package com.example.swift;

import com.example.swift.SampleLocalSwiftLibrary.*;
import org.swift.swiftkit.ffm.AllocatingSwiftArena;

public class JavaAppSampleMain {
    public static void main(String[] args) {
        System.out.println("Java -> Swift interop via SwiftPM Import Plugin");
        System.out.println("================================================");

        // Call a Swift global function from the local package
        String hello = SampleLocalSwiftLibrary.callMeSwifty();
        System.out.println("callMeSwifty() = " + hello);

        // Create and use a Swift class from the local package
        try (var arena = AllocatingSwiftArena.ofConfined()) {
            var greeter = SwiftyGreeter.init("Duke", arena);
            System.out.println("SwiftyGreeter.name = " + greeter.getName());
            System.out.println("SwiftyGreeter.greet() = " + greeter.greet());
        }

        System.out.println("Done.");
    }
}
