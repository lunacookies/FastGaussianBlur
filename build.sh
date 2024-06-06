#!/bin/sh

set -e

clang-format -i ./*.m ./*.metal

rm -rf build
mkdir -p build/FastGaussianBlur.app/Contents
mkdir build/FastGaussianBlur.app/Contents/MacOS
mkdir build/FastGaussianBlur.app/Contents/Resources

cp FastGaussianBlur-Info.plist build/FastGaussianBlur.app/Contents/Info.plist
plutil -convert binary1 build/FastGaussianBlur.app/Contents/Info.plist

clang -o build/FastGaussianBlur.app/Contents/MacOS/FastGaussianBlur \
	-fmodules -fobjc-arc \
	-g3 \
	-ftrivial-auto-var-init=zero -fwrapv \
	-W \
	-Wall \
	-Wextra \
	-Wpedantic \
	-Wconversion \
	-Wimplicit-fallthrough \
	-Wmissing-prototypes \
	-Wshadow \
	-Wstrict-prototypes \
	-Wno-unused-parameter \
	entry_point.m

xcrun metal \
	-o build/FastGaussianBlur.app/Contents/Resources/shaders.metallib \
	-gline-tables-only -frecord-sources \
	shaders.metal

cp FastGaussianBlur.entitlements build/FastGaussianBlur.entitlements
/usr/libexec/PlistBuddy -c 'Add :com.apple.security.get-task-allow bool YES' \
	build/FastGaussianBlur.entitlements
codesign \
	--sign - \
	--entitlements build/FastGaussianBlur.entitlements \
	--options runtime build/FastGaussianBlur.app/Contents/MacOS/FastGaussianBlur
