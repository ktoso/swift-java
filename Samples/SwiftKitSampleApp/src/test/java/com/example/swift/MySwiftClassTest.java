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

import org.junit.jupiter.api.Disabled;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

public class MySwiftClassTest {

    @Test
    void test_MySwiftClass_voidMethod() {
        MySwiftClass o = new MySwiftClass(12, 42);
        o.voidMethod();
    }

    @Test
    void test_MySwiftClass_makeIntMethod() {
        MySwiftClass o = new MySwiftClass(12, 42);
        var got = o.makeIntMethod();
        assertEquals(12, got);
    }

    @Test
    @Disabled // TODO: Need var mangled names in interfaces
    void test_MySwiftClass_property_len() {
        MySwiftClass o = new MySwiftClass(12, 42);
        var got = o.getLen();
        assertEquals(12, got);
    }

}
