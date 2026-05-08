.PHONY: generate open xcode

generate:
	xcodegen generate

open:
	open OnlyCue.xcodeproj

xcode: generate open
