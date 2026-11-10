import SwiftUI

struct LaunchSplashView: View {
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            Image("LaunchSplashArtwork")
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
                .accessibilityLabel("WEASHION app launch screen")
        }
        .background(Editorial.paper)
        .ignoresSafeArea()
        .preferredColorScheme(.light)
    }
}
