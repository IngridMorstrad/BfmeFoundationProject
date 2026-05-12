import Foundation

#if canImport(AppKit)
import AppKit
#endif

#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Direct port of `SystemDisplayManager.cs`. The Windows version used
/// `System.Windows.Forms.Screen.PrimaryScreen` + `user32!EnumDisplaySettings`.
/// On macOS we use `NSScreen.main` and `CGDisplayCopyAllDisplayModes` to get
/// the equivalent data. The public surface is unchanged so call sites don't
/// need to branch on platform.
public enum SystemDisplayManager {
    public struct Size: Sendable, Equatable, Hashable, Codable {
        public let width: Int
        public let height: Int
        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }
    }

    public struct ScreenSnapshot: Sendable, Equatable, Codable {
        public let primary: Size
        public let supportedResolutions: [Size]
        public init(primary: Size, supportedResolutions: [Size]) {
            self.primary = primary
            self.supportedResolutions = supportedResolutions
        }
    }

    /// Returns a snapshot of the current primary display plus its supported
    /// resolutions. Safe to call from any platform; on Linux it returns a
    /// sensible default so tests and headless CI still have a value.
    public static func snapshot() -> ScreenSnapshot {
        return ScreenSnapshot(
            primary: getPrimaryScreenResolution(),
            supportedResolutions: getAllSupportedResolutions()
        )
    }

    public static func getPrimaryScreenResolution() -> Size {
        #if canImport(AppKit)
        if let screen = NSScreen.main {
            let frame = screen.frame
            return Size(width: Int(frame.size.width), height: Int(frame.size.height))
        }
        #endif
        return Size(width: 1920, height: 1080)
    }

    /// Enumerates every display mode CoreGraphics reports for the main
    /// display. The C# version filtered for 60Hz / 32bpp modes and dropped
    /// the three smallest. We mirror that filter faithfully so the settings
    /// UI sees the same candidate list.
    public static func getAllSupportedResolutions() -> [Size] {
        #if canImport(CoreGraphics)
        let displayID = CGMainDisplayID()
        guard let modes = CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode] else {
            return fallbackResolutions
        }
        var collected: [Size] = []
        for mode in modes {
            let hz = mode.refreshRate
            let pixelEncoding = mode.pixelEncoding as String?
            // 32bpp + 60Hz mirrors the Windows `dmDisplayFrequency == 60 && dmBitsPerPel == 32` filter.
            let is32bpp = pixelEncoding == nil || pixelEncoding == kIO32BitDirectPixels as String
            let hzOk = (hz == 0) || (Int(hz.rounded()) == 60)
            if hzOk && is32bpp {
                let s = Size(width: mode.width, height: mode.height)
                if !collected.contains(s) { collected.append(s) }
            }
        }
        collected.sort { lhs, rhs in
            if lhs.width != rhs.width { return lhs.width < rhs.width }
            return lhs.height < rhs.height
        }
        if collected.count > 3 {
            collected.removeFirst(min(3, collected.count))
        }
        return collected
        #else
        return fallbackResolutions
        #endif
    }

    private static let fallbackResolutions: [Size] = [
        Size(width: 1280, height: 720),
        Size(width: 1920, height: 1080),
        Size(width: 2560, height: 1440),
        Size(width: 3840, height: 2160)
    ]
}

#if canImport(CoreGraphics)
private let kIO32BitDirectPixels = "PPPPPPPPPPPPPPPPRRRRRRRRGGGGGGGGBBBBBBBB"
#endif
