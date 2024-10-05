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

run: all
	DYLD_LIBRARY_PATH=$(BUILD_DIR)/debug swift run

require-graal:
	@if ! java -version 2>&1 | grep -q "Graal"; then \
		echo "Java distribution is not GraalVM."; \
		exit 1; \
	else \
	  java -version; \
	fi


Sources/JEnvMap/LibEnvMap.class: Sources/JEnvMap/LibEnvMap.java
	cd Sources/JEnvMap/; \
	javac LibEnvMap.java

libenvmap.dylib: Sources/JEnvMap/LibEnvMap.class
	cd Sources/JEnvMap; \
	native-image -o libenvmap --shared; \
	mv *.h include/; \
	rm *.class; \
	mkdir -p ../../$(BUILD_DIR)/debug; \
	mv *.dylib ../../$(BUILD_DIR)/debug

clean:
	rm -rf .build
	rm Sources/JEnvMap/*.class
	rm Sources/JEnvMap/include/graal_isolate.h
	rm Sources/JEnvMap/include/graal_isolate_dynamic.h
	rm Sources/JEnvMap/include/libenvmap.h
	rm Sources/JEnvMap/include/libenvmap_dynamic.h
	rm libenvmap.dylib

format:
	swift format --recursive . -i
