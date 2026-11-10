import SwiftUI

@main
struct WEASHIONApp: App {
    init() {
        EditorialFonts.register()
        #if DEBUG
        // UI tests share one simulator app container; start each test from the system language.
        if ProcessInfo.processInfo.environment["WEASHION_UI_TEST_RESET_LANGUAGE"] != nil {
            UserDefaults.standard.removeObject(forKey: AppLanguage.key)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            LaunchSplashContainer()
        }
    }
}

private struct LaunchSplashContainer: View {
    @State private var contentReady = false
    @State private var minimumDurationElapsed = false

    private var showsSplash: Bool { !contentReady || !minimumDurationElapsed }

    var body: some View {
        ZStack {
            ContentView {
                contentReady = true
            }
            .opacity(showsSplash ? 0 : 1)
            .allowsHitTesting(!showsSplash)
            .accessibilityHidden(showsSplash)

            if showsSplash {
                LaunchSplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            do {
                try await Task.sleep(for: .milliseconds(900))
            } catch is CancellationError {
                return
            } catch {
                assertionFailure("Could not finish the launch splash delay: \(error)")
                return
            }
            withAnimation(.easeOut(duration: 0.45)) {
                minimumDurationElapsed = true
            }
        }
    }
}
