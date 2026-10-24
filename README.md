# iOS SDK (Swift package)

The SwiftPM distribution of the SDK, generated for each release from the SDK's source repository. It holds the Swift
sources and `Package.swift`; the XCFramework is a release asset that `Package.swift` names with its checksum.
iOS 16 or later. Licensed under PolyForm Noncommercial 1.0.0.

This XCFramework is unsigned. Its integrity is pinned by the SHA-256 checksum in Package.swift.

```swift
.package(url: "https://github.com/EgyGeeks/karnak-swift", from: "0.1.0-alpha.3")
```

Products:

- Karnak (modules: Karnak)
- KarnakNavigation (modules: KarnakNavigation)
