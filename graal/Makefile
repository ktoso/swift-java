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

all: require-graal libenvmap.dylib
	swift build

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
	mv *.dylib ../../

clean:
	rm -rf .build
	rm Sources/JEnvMap/*.class
	rm libenvmap.dylib

format:
	swift format --recursive . -i
