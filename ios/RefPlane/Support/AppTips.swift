import SwiftUI
import TipKit

enum AppTips {
    static let imageLoaded = Tips.Event(id: "image-loaded")

    static func configure() {
        do {
            try Tips.configure([
                .displayFrequency(.daily)
            ])
        } catch let error as TipKitError where error == .tipsDatastoreAlreadyConfigured {
            return
        } catch {
            assertionFailure("TipKit configuration failed: \(error)")
        }
    }

#if DEBUG
    static func resetForTesting() {
        try? Tips.resetDatastore()
    }

    static func showAllForTesting() {
        Tips.showAllTipsForTesting()
    }
#endif
}

struct SimplificationTip: Tip {
    static let titleText = "Simplify Your Reference"
    static let messageText = "Reduce detail to see the essential shapes and values - useful for blocking in."

    var id: String { "simplification-tip" }
    var title: Text { Text(Self.titleText) }
    var message: Text? { Text(Self.messageText) }

    var rules: [Rule] {
        #Rule(AppTips.imageLoaded) { event in
            event.donations.count >= 1
        }
    }

    var options: [any TipOption] {
        Tips.MaxDisplayCount(1)
    }
}

struct BackgroundDepthTip: Tip {
    static let titleText = "Separate Foreground & Background"
    static let messageText = "Use AI depth estimation to blur, compress, or remove the background."

    var id: String { "background-depth-tip" }
    var title: Text { Text(Self.titleText) }
    var message: Text? { Text(Self.messageText) }

    var rules: [Rule] {
        #Rule(AppTips.imageLoaded) { event in
            event.donations.count >= 1
        }
    }

    var options: [any TipOption] {
        Tips.MaxDisplayCount(1)
    }
}

struct CompareModeTip: Tip {
    static let titleText = "Compare Before & After"
    static let messageText = "Slide to compare your original image with the current study."

    var id: String { "compare-mode-tip" }
    var title: Text { Text(Self.titleText) }
    var message: Text? { Text(Self.messageText) }

    var rules: [Rule] {
        #Rule(AppTips.imageLoaded) { event in
            event.donations.count >= 1
        }
    }

    var options: [any TipOption] {
        Tips.MaxDisplayCount(1)
    }
}

struct PresetsTip: Tip {
    static let titleText = "Save Your Settings"
    static let messageText = "Save the current mode and settings as a preset you can reapply to any image."

    var id: String { "presets-tip" }
    var title: Text { Text(Self.titleText) }
    var message: Text? { Text(Self.messageText) }

    var rules: [Rule] {
        #Rule(AppTips.imageLoaded) { event in
            event.donations.count >= 1
        }
    }

    var options: [any TipOption] {
        Tips.MaxDisplayCount(1)
    }
}

struct ExportTip: Tip {
    static let titleText = "Export Your Study"
    static let messageText = "Export the processed image with overlays baked in."

    var id: String { "export-tip" }
    var title: Text { Text(Self.titleText) }
    var message: Text? { Text(Self.messageText) }

    var rules: [Rule] {
        #Rule(AppTips.imageLoaded) { event in
            event.donations.count >= 1
        }
    }

    var options: [any TipOption] {
        Tips.MaxDisplayCount(1)
    }
}

struct PaletteSelectionTip: Tip {
    static let titleText = "Match to Real Pigments"
    static let messageText = "Enable palette selection to decompose colors into paintable pigment recipes."

    var id: String { "palette-selection-tip" }
    var title: Text { Text(Self.titleText) }
    var message: Text? { Text(Self.messageText) }

    var rules: [Rule] {
        #Rule(AppTips.imageLoaded) { event in
            event.donations.count >= 1
        }
    }

    var options: [any TipOption] {
        Tips.MaxDisplayCount(1)
    }
}