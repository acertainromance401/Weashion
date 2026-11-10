import SwiftUI

struct EditorialWelcomeView: View {
    let onFinish: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    @Namespace private var pageIndicator

    private let titles = ["Wear your\nown weather.", "A size is just\na beginning.", "Your body.\nYour point of view."]
    private let subtitles = [L("오늘의 날씨를, 나만의 옷차림으로."), L("숫자 너머의 실루엣을 만나세요."), L("유행보다 먼저, 나를 기준으로.")]
    private let descriptions = [
        L("오늘의 공기와 나의 체형이 만나는 곳.\nWEASHION에서 하루의 옷차림을 그려보세요."),
        L("마음에 든 반팔의 사이즈표를 입력하고,\n내 마네킹 위에서 길이와 여유를 살펴보세요."),
        L("직접 입력한 치수로 만드는 단 하나의 마네킹.\n사진 스캔 없이, 이 기기에 나의 비율을 담아요.")
    ]

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 700 && !dynamicTypeSize.isAccessibilitySize
            ZStack {
                WeatherBackdrop(mood: page == 1 ? .cloud : .clear, dark: true)
                    .id(page == 1)
                    .transition(.opacity)
                    .ignoresSafeArea()
                    .animation(EditorialMotion.transition(reduceMotion: reduceMotion), value: page)
                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        HStack(spacing: 9) {
                            Image("BrandMark")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 29, height: 29)
                                .accessibilityHidden(true)
                            Text("WEASHION").font(Editorial.serif(25)).tracking(3)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("WEASHION")
                        Spacer()
                        Button("건너뛰기", action: onFinish)
                            .editorialSans(.caption)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("skipWelcome")
                    }
                    .padding(.horizontal, wide ? 48 : 24)
                    Rectangle().fill(.white.opacity(0.4)).frame(height: 0.5)
                        .padding(.horizontal, wide ? 48 : 24)
                    if wide {
                        HStack(spacing: 50) {
                            visual.frame(maxWidth: .infinity)
                                .id(page)
                                .transition(pageTransition)
                            ScrollView {
                                copy
                                    .transition(pageTransition)
                                    .padding(.vertical, 40)
                            }
                            .frame(maxWidth: 470)
                        }
                        .padding(48)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                visual.frame(minHeight: max(180, min(260, geometry.size.height * 0.28)))
                                    .id(page)
                                    .transition(pageTransition)
                                copy
                                    .transition(pageTransition)
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 24)
                        }
                        .defaultScrollAnchor(.bottom)
                    }
                    controls
                        .frame(maxWidth: 510)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, wide ? 48 : 24)
                        .padding(.bottom, 22)
                }
                .foregroundStyle(.white)
                .padding(.top, 10)
            }
        }
        .editorialSans(.body)
        .buttonStyle(EditorialPressStyle())
        .sensoryFeedback(.selection, trigger: page)
        .preferredColorScheme(.dark)
    }

    private var pageTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8))
    }

    private var visual: some View {
        ZStack(alignment: .topLeading) {
            Text(String(format: "%02d", page + 1))
                .font(Editorial.serif(150, italic: true))
                .foregroundStyle(.white.opacity(0.12))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                EditorialEyebrow(text: ["THE WEATHER ISSUE", "THE FITTING ISSUE", "THE PERSONAL ISSUE"][page])
                HStack(spacing: 20) {
                    if page == 1 {
                        GarmentIllustration(tint: Color(red: 0.74, green: 0.76, blue: 0.68))
                            .frame(width: 110, height: 125)
                            .rotationEffect(.degrees(-8))
                    } else if page == 0 {
                        Image("WelcomeSplashArtwork")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 150, height: 125)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "ruler")
                            .font(.system(size: 65, weight: .ultraLight))
                            .frame(width: 100, height: 100)
                            .accessibilityHidden(true)
                    }
                    Text(["THE AIR.\nTHE WAY YOU WEAR.", "THE LABEL.\nYOUR SILHOUETTE.", "YOUR BODY.\nTHE ONLY REFERENCE."][page])
                        .editorialSans(.caption2, weight: .medium)
                        .tracking(1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Rectangle().fill(.white.opacity(0.6)).frame(height: 0.5)
                Text("A PERSONAL FITTING JOURNAL")
                    .editorialSans(.caption2)
                    .tracking(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 20) {
            EditorialTitle(text: titles[page])
            Text(subtitles[page]).editorialSans(.title3)
            Text(descriptions[page])
                .editorialSans(.subheadline)
                .lineSpacing(6)
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            if page == 1 {
                Text("코튼 반팔의 치수 기반 미리보기이며, 실제 상품의 디자인이나 정확한 핏을 복원하지 않습니다.")
                    .editorialSans(.caption)
                    .lineSpacing(4)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(page)
    }

    private var controls: some View {
        VStack(spacing: 22) {
            Button {
                if page == 2 { onFinish() }
                else {
                    withAnimation(EditorialMotion.transition(reduceMotion: reduceMotion)) { page += 1 }
                }
            } label: {
                HStack {
                    Text(page == 2 ? L("내 마네킹으로 돌아가기") : page == 0 ? L("스토리 보기") : L("다음"))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(EditorialButtonStyle(inverted: true))
            .accessibilityIdentifier("welcomeNext")
            HStack(spacing: 10) {
                ForEach(0..<3) { index in
                    Button {
                        withAnimation(EditorialMotion.transition(reduceMotion: reduceMotion)) { page = index }
                    } label: {
                        Rectangle()
                            .fill(.white.opacity(0.25))
                            .frame(height: 2)
                            .overlay {
                                if page == index {
                                    Rectangle()
                                        .fill(.white)
                                        .matchedGeometryEffect(id: "selectedPage", in: pageIndicator)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("소개 \(index + 1) / 3")
                    .accessibilityAddTraits(page == index ? .isSelected : [])
                }
            }
        }
    }
}
