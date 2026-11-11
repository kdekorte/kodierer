import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct KodiererRoot: App {
    #if os(macOS)
    init() {
        // `swift run Kodierer` starts us without an app bundle; become a regular
        // frontmost app so the window gets focus and a dock icon.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    #endif

    var body: some Scene {
        WindowGroup {
            MainTabs()
                .frame(minWidth: 780, minHeight: 560)
        }
    }
}

/// Three screens: connect & read, decode & change, CAFD browser.
struct MainTabs: View {
    @StateObject private var model = AppModel()

    var body: some View {
        TabView {
            CarView()
                .tabItem { Label("Car", systemImage: "car.fill") }
            CodingView()
                .tabItem { Label("Coding", systemImage: "slider.horizontal.3") }
            CAFDView()
                .tabItem { Label("CAFD", systemImage: "doc.text.magnifyingglass") }
        }
        .environmentObject(model)
    }
}
