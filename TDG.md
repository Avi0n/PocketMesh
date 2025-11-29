# TDG Configuration

## Project Information
- Language: Swift
- Framework: SwiftUI + SwiftData
- Test Framework: XCTest

## Build Command
xcodegen generate && xcodebuild -project PocketMesh.xcodeproj -scheme PocketMesh -destination 'platform=iOS Simulator,name=iPhone 17' build

## Test Command
xcodebuild test -project PocketMesh.xcodeproj -scheme PocketMesh -destination 'platform=iOS Simulator,name=iPhone 17'

## Single Test Command
xcodebuild test -project PocketMesh.xcodeproj -scheme PocketMesh -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PocketMeshTests/CLASS_NAME/METHOD_NAME

## Coverage Command
xcodebuild test -project PocketMesh.xcodeproj -scheme PocketMesh -destination 'platform=iOS Simulator,name=iPhone 17' -enableCodeCoverage YES

## Test File Patterns
- Test files: *Tests.swift, *Test.swift
- Test directory: PocketMeshTests/