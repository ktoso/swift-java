#===----------------------------------------------------------------------===#
#
# This source file is part of the Swift.org open source project
#
# Copyright (c) 2024 Apple Inc. and the Swift.org project authors
# Licensed under Apache License v2.0
#
# See LICENSE.txt for license information
# See CONTRIBUTORS.txt for the list of Swift project authors
#
# SPDX-License-Identifier: Apache-2.0
#
#===----------------------------------------------------------------------===#

.PHONY: run clean all

ARCH := $(shell arch)
UNAME := $(shell uname)

ifeq ($(UNAME), Linux)
ifeq ($(ARCH), 'i386')
  ARCH_SUBDIR := x86_64
else
  ARCH_SUBDIR := aarch64
endif
BUILD_DIR := .build/$(ARCH_SUBDIR)-unknown-linux-gnu
LIB_SUFFIX := so
endif

ifeq ($(UNAME), Darwin)
ifeq ($(ARCH), 'i386')
  ARCH_SUBDIR := x86_64
else
  ARCH_SUBDIR := arm64
endif
BUILD_DIR := .build/$(ARCH_SUBDIR)-apple-macosx
LIB_SUFFIX := dylib
endif


all: require-graal libenvmap.dylib
	swift build

require-graal:
	if [$(java -version | grep GraalVM | wc -l) = 0]; then "Build requires Graal JDK"; exit 1; fi

Sources/JEnvMap/LibEnvMap.class: Sources/JEnvMap/LibEnvMap.java
	cd Sources/JEnvMap/
	javac LibEnvMap.java

libenvmap.dylib: Sources/JEnvMap/LibEnvMap.class
	native-image -cp Sources/JEnvMap -o libenvmap --shared

clean:
	rm -rf .build
	Sources/JEnvMap/*.class
	rm libenvmap.dylib

format:
	swift format --recursive . -i
