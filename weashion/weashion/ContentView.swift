import SwiftUI
import Observation
import UIKit
import CoreLocation

struct ContentView: View {
    var onLaunchReady: () -> Void = {}
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var room = FittingRoom.application()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var weatherManager = WeatherManager()
    @State private var sheet: MainSheet?
    @State private var showGarmentEditor = false
    @State private var pageTransition = EditorialPageTransition()
    @State private var fitSummary: GarmentFitSummary?
    @State private var coverStatus: EditorialSceneStatus?
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var garmentDraft: GarmentMeasurements?
    @State private var showFitDetails = false
    @State private var showWeatherErrorDetails = false
    @State private var errorMessage: String?
    @State private var sceneLink = EditorialSceneLink()
    @State private var previousSize: ProductSize?
    @Namespace private var tabIndicator
    @Namespace private var sizeIndicator
    @ScaledMetric(relativeTo: .largeTitle) private var displayScale: CGFloat = 1
    @AppStorage(WeatherPreview.key) private var previewMoodValue = WeatherMood.cloud.rawValue
    @AppStorage(AppLanguage.key) private var appLanguage = AppLanguage.system.rawValue
    private var tab: MainTab { pageTransition.displayed }
    private var selectedTab: MainTab { pageTransition.requested ?? tab }

    private var weather: WeatherInfo {
        weatherManager.weather ?? .sample(for: WeatherMood(rawValue: previewMoodValue) ?? .cloud)
    }
    /// Rainy editions invert the cover: paper type over a slate sky.
    private var coverInk: Color { weather.mood.prefersInvertedCover ? Editorial.paper : Editorial.ink }
    private var isLiveWeather: Bool { weatherManager.weather != nil }
    private var outfit: Outfit { OutfitRecommendation.recommend(weather: weather) }
    private var previewMeasurements: GarmentMeasurements? { garmentDraft ?? room.selectedSize?.measurements }
    private var usesInspector: Bool { horizontalSizeClass == .regular }
    private var numeralScale: CGFloat { min(displayScale, 1.3) }
    private var feedbackTrigger: EditorialFeedbackTrigger {
        EditorialFeedbackTrigger(saveRevision: room.saveRevision,
                                 selection: [selectedTab.rawValue, room.profile?.id, room.product?.id, room.library.selectedSizeID])
    }

    var body: some View {
        Group {
            if !room.isLoaded {
                ContentUnavailableView {
                    Label("저장 정보를 확인해 주세요", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(room.loadError ?? L("저장 정보를 불러오는 중입니다."))
                } actions: {
                    Button("다시 불러오기") { room.reload() }
                        .buttonStyle(EditorialButtonStyle())
                }
                .background(Editorial.paper)
            } else if let profile = room.profile {
                main(profile: profile)
            } else {
                BodySetupView(room: room, isInitialSetup: true)
            }
        }
        .tint(Editorial.ink)
        .foregroundStyle(Editorial.ink)
        .editorialSans(.body)
        .buttonStyle(EditorialPressStyle())
        .preferredColorScheme(.light)
        .environment(\.locale, L10n.locale)
        .editorialError($errorMessage)
        .editorialError($pageTransition.errorMessage)
        .sensoryFeedback(trigger: feedbackTrigger) { previous, current in
            switch current.kind(since: previous) {
            case .success: .success
            case .selection: .selection
            case nil: nil
            }
        }
        .onChange(of: feedbackTrigger) { previous, current in
            if current.kind(since: previous) == .selection { room.statusMessage = nil }
        }
        .onChange(of: appLanguage) { _, _ in
            // Status copy was resolved in the previous language; drop it rather than show a mixed page.
            room.statusMessage = nil
            pageTransition.cancel()
        }
        .onChange(of: reduceMotion, initial: true) { _, reduced in
            pageTransition.reduceMotion = reduced
        }
        .onChange(of: room.isLoaded, initial: true) { _, loaded in
            if loaded && room.profile == nil { onLaunchReady() }
        }
        .onChange(of: room.loadError, initial: true) { _, error in
            if error != nil { onLaunchReady() }
        }
    }

    private func mainLayout(profile: BodyProfile) -> some View {
        GeometryReader { geometry in
            let wide = EditorialLayout.usesColumns(width: geometry.size.width,
                                                   accessibility: dynamicTypeSize.isAccessibilitySize)
            let margin = EditorialLayout.margin(wide: wide)
            let stageHeight = EditorialLayout.stageHeight(viewportHeight: geometry.size.height, wide: wide)
            let coverHeight = EditorialLayout.coverHeight(viewportHeight: geometry.size.height, wide: wide)
            VStack(spacing: 0) {
                runningHeader(margin: margin)
                ScrollView {
                    VStack(spacing: 0) {
                        Group {
                            switch tab {
                            case .today:
                                today(wide: wide, margin: margin, profile: profile, coverHeight: coverHeight)
                            case .fitting:
                                fitting(wide: wide, margin: margin, profile: profile, stageHeight: stageHeight)
                            case .body:
                                bodyProfile(wide: wide, margin: margin, profile: profile, stageHeight: stageHeight)
                            }
                        }
                        .id(tab)
                        .transition(.identity)
                        .allowsHitTesting(pageTransition.requested == nil)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("page-\(tab.rawValue)")
                        footer
                            .padding(.horizontal, margin)
                            .padding(.top, 56)
                    }
                    .frame(maxWidth: 1180)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 24)
                }
                .scrollPosition($scrollPosition)
                .accessibilityIdentifier("editorialPageScroll")
                .editorialSaveFeedback($room.statusMessage, horizontalInset: margin)
            }
            .overlay(alignment: .bottom) {
                if pageTransition.showsPreview, let next = pageTransition.requested {
                    EditorialTransitionPreview(number: next.number, title: next.runningHead,
                                               extended: pageTransition.showsExtendedStatus)
                        .padding(.horizontal, margin)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { navigationBar }
            .background(Editorial.paper)
            // The sheet host stays put while localized page content is rebuilt.
            .id(appLanguage)
        }
    }

    private func main(profile: BodyProfile) -> some View {
        NavigationStack {
            mainLayout(profile: profile)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $sheet) { destination in
                switch destination {
                case .profiles:
                    BodyLibraryView(room: room)
                case .products:
                    ProductLibraryView(room: room) {
                        show(.fitting)
                        sheet = nil
                    }
                case .settings:
                    FittingSettingsView(room: room)
                case .editBody(let profile):
                    NavigationStack {
                        BodyEditorView(bodyData: profile.body, mannequinBase: profile.base, profileName: profile.name) {
                            body, base, name in
                            var next = profile
                            next.body = body
                            next.base = base
                            next.name = name ?? profile.name
                            try room.updateProfile(next)
                        }
                    }
                }
            }
            .sheet(isPresented: garmentEditorPresentation(inspector: false)) {
                garmentEditor(profile: profile)
            }
            .inspector(isPresented: garmentEditorPresentation(inspector: true)) {
                garmentEditor(profile: profile)
                    .inspectorColumnWidth(min: 340, ideal: 400, max: 460)
            }
            .onChange(of: tab) { _, next in
                scrollPosition.scrollTo(edge: .top)
                showGarmentEditor = false
                showFitDetails = false
                fitSummary = next == .fitting ? sceneLink.fitting.garment.fitSummary : nil
                previousSize = nil
            }
            .onChange(of: showGarmentEditor) { _, presented in
                if presented { pageTransition.cancel() }
                if !presented { garmentDraft = nil }
            }
            .onChange(of: sheet != nil) { _, presented in
                if presented { pageTransition.cancel() }
            }
            .onChange(of: room.outfitDefinitions) { _, _ in
                fitSummary = nil
                restartPendingTransition()
            }
            .onChange(of: sizeSelection) { previous, current in
                updateSizeComparison(previous: previous, current: current)
            }
            .onChange(of: profile.updatedAt) { _, _ in
                fitSummary = nil
                restartPendingTransition()
            }
            .onChange(of: profile.id) { _, _ in
                fitSummary = nil
                restartPendingTransition()
            }
            .onDisappear {
                pageTransition.cancel()
                sceneLink.cancelPreparation()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                pageTransition.cancel()
                sceneLink.releaseInactiveResources(keepingBody: tab == .body)
                Task {
                    await BodyPreviewRenderer.shared.releaseCachedResources()
                    await GarmentDraper.shared.releaseCachedResources()
                }
            }
            .task(id: locationManager.locationRevision) {
                guard let location = locationManager.location else { return }
                await weatherManager.loadWeather(for: location)
            }
            .onChange(of: locationManager.authorizationStatus) { _, status in
                if status != .authorizedWhenInUse && status != .authorizedAlways {
                    weatherManager.clear()
                }
            }
        }
    }

    private func garmentEditorPresentation(inspector: Bool) -> Binding<Bool> {
        Binding(get: { showGarmentEditor && usesInspector == inspector }, set: { presented in
            if usesInspector == inspector { showGarmentEditor = presented }
        })
    }

    @ViewBuilder
    private func garmentEditor(profile: BodyProfile) -> some View {
        if let definition = room.definition, let product = room.product,
           let selectedSize = room.selectedSize, let measurements = selectedSize.measurements,
           measurements.supports(product.kind) {
            switch measurements {
            case .shortSleeve(let input):
                GarmentEditorView(
                    size: input,
                    product: GarmentProductInfo(name: product.name, source: product.source, sizeLabel: selectedSize.label),
                    definition: definition, bodyData: profile.body, mannequinBase: profile.base, weather: weather,
                    sampleDefinitions: room.catalog,
                    showsPreview: !usesInspector, requiresSizeLabel: true,
                    onPreviewChange: { size in
                        if usesInspector { garmentDraft = .shortSleeve(size) }
                    },
                    onClose: { showGarmentEditor = false }
                ) { size, info in
                    var next = selectedSize
                    next.label = info.sizeLabel
                    next.measurements = .shortSleeve(size)
                    try room.saveSize(next, productID: product.id, info: info, select: true)
                }
                .id("\(product.id)/\(selectedSize.id)")
            case .trousers, .footwear:
                WearableMeasurementsEditor(
                    measurements: measurements, sizeLabel: selectedSize.label,
                    definition: definition, bodyData: profile.body, mannequinBase: profile.base, weather: weather,
                    sampleDefinitions: room.catalog,
                    showsPreview: !usesInspector, saveTitle: L("내 마네킹에 적용"),
                    onPreviewChange: { measurements in
                        if usesInspector { garmentDraft = measurements }
                    },
                    onClose: { showGarmentEditor = false }
                ) { measurements, label in
                    var next = selectedSize
                    next.label = label
                    next.measurements = measurements
                    try room.saveSize(next, productID: product.id, select: true)
                }
                .id("\(product.id)/\(selectedSize.id)")
            }
        }
    }

    private func show(_ next: MainTab) {
        pageTransition.show(next, reduceMotion: reduceMotion) {
            guard let profile = room.profile else { throw CancellationError() }
            let request = BodyPreviewRenderer.Request(body: profile.body, base: profile.base)
            let state = next == .body ? sceneLink.body : sceneLink.fitting
            try await state.prepare(request, bodyOnly: next == .body)
            try Task.checkCancellation()
            if next != .body {
                state.garment.update(outfit: room.outfitDefinitions, focused: room.definition, mannequin: state.mannequin)
            }
        }
    }

    private func restartPendingTransition() {
        guard let next = pageTransition.requested else { return }
        pageTransition.cancel()
        show(next)
    }

    private struct SizeSelection: Equatable {
        let productID: String?
        let sizeID: String?
    }

    private var sizeSelection: SizeSelection {
        SizeSelection(productID: room.library.selectedProductID, sizeID: room.library.selectedSizeID)
    }

    private func updateSizeComparison(previous: SizeSelection, current: SizeSelection) {
        guard previous.productID == current.productID, let sizeID = previous.sizeID else {
            previousSize = nil
            return
        }
        previousSize = room.product?.sizes.first { $0.id == sizeID }
    }

    // MARK: - Running header and navigation

    private func runningHeader(margin: CGFloat) -> some View {
        HStack(spacing: 12) {
            Image("BrandMark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .foregroundStyle(Editorial.ink)
                .accessibilityLabel("WEASHION")
            Rectangle().fill(Editorial.rule).frame(width: 0.5, height: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(tab.title).editorialSans(.caption, weight: .semibold)
                Text(tab.edition)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.3)
                    .foregroundStyle(Editorial.muted)
            }
            .lineLimit(1)
            .contentTransition(.opacity)
            .animation(EditorialMotion.transition(reduceMotion: reduceMotion), value: tab)
            Spacer(minLength: 8)
            Text(Date.now, format: .dateTime.month(.twoDigits).day(.twoDigits))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Editorial.muted)
                .accessibilityHidden(true)
            Button { sheet = .settings } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .regular))
                    .frame(width: 44, height: 44)
            }
            .disabled(showGarmentEditor)
            .accessibilityLabel("설정과 안내")
            .accessibilityIdentifier("openSettings")
        }
        .padding(.horizontal, margin)
        .padding(.vertical, 3)
        .background(Editorial.paper)
        .overlay(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                Rectangle().fill(Editorial.rule).frame(height: 0.5)
                EditorialPageSweep(page: tab.rawValue)
            }
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 4) {
            ForEach(MainTab.allCases) { item in
                Button { show(item) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if !dynamicTypeSize.isAccessibilitySize {
                            Text(item.number)
                                .font(Editorial.serif(13, italic: true))
                                .foregroundStyle(Editorial.paper.opacity(selectedTab == item ? 0.8 : 0.5))
                                .accessibilityHidden(true)
                        }
                        Text(item.title).editorialSans(.subheadline, weight: selectedTab == item ? .semibold : .regular)
                    }
                    .padding(.vertical, 16)
                    .foregroundStyle(Editorial.paper.opacity(selectedTab == item ? 1 : 0.75))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background {
                        if selectedTab == item {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Editorial.accent)
                                .matchedGeometryEffect(id: "selectedTab", in: tabIndicator)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("tab-\(item.rawValue)")
                .accessibilityLabel(item.title)
                .disabled(showGarmentEditor)
                .accessibilityAddTraits(selectedTab == item ? .isSelected : [])
            }
        }
        .padding(5)
        .background(Editorial.ink, in: .rect(cornerRadius: 9))
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Editorial.paper.ignoresSafeArea(edges: .bottom))
        .animation(EditorialMotion.transition(reduceMotion: reduceMotion), value: selectedTab)
    }

    private var footer: some View {
        VStack(spacing: 18) {
            EditorialRule()
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("WEASHION").font(Editorial.serif(22)).tracking(1)
                    EditorialEyebrow(text: "A PERSONAL FITTING JOURNAL")
                }
                Spacer()
                Text("/ \(tab.number)").font(.system(size: 12, design: .monospaced))
            }
            .foregroundStyle(Editorial.muted)
        }
    }

    // MARK: - Today

    /// The cover is interactive; detailed size notes precede the weather context.
    @ViewBuilder
    private func today(wide: Bool, margin: CGFloat, profile: BodyProfile, coverHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            cover(height: coverHeight, wide: wide, margin: margin, profile: profile)
            if dynamicTypeSize.isAccessibilitySize {
                coverMetadata(profile: profile)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, margin)
                    .padding(.top, 16)
            }
            coverControls
                .padding(.horizontal, margin)
                .padding(.top, 16)
            if let product = room.product {
                EditorialSizeSpread(product: product, selectedID: room.library.selectedSizeID,
                                    supportsFitting: product.template(in: room.catalog) != nil, margin: margin,
                                    onBrowse: { sheet = .products }) { size in
                    perform {
                        try room.select(productID: product.id, sizeID: size.id)
                        show(.fitting)
                    }
                }
                .padding(.top, 40)
            }
            weatherSpread(wide: wide, margin: margin)
                .padding(.horizontal, margin)
                .padding(.top, 64)
        }
    }

    private func cover(height: CGFloat, wide: Bool, margin: CGFloat, profile: BodyProfile) -> some View {
        ZStack(alignment: .top) {
            WeatherBackdrop(mood: weather.mood)
                .scaleEffect(reduceMotion ? 1 : 1.06)
                .visualEffect { [reduceMotion] content, geometry in
                    content.offset(y: reduceMotion ? 0 :
                        EditorialMotion.parallaxOffset(minY: geometry.frame(in: .scrollView).minY, limit: 10))
                }
            VStack(spacing: 0) {
                Text("WEASHION")
                    .font(Editorial.serif(wide ? 164 : 96, weight: 500))
                    .tracking(wide ? 2 : -1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .foregroundStyle(coverInk)
                    .animation(EditorialMotion.transition(reduceMotion: reduceMotion), value: weather.mood)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, margin * 0.5)
                    .padding(.top, 8)
                    .editorialEntrance(distance: wide ? 160 : 110)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
            }
            mannequin(profile: profile, height: height, editorial: true, chrome: .cover)
        }
        .frame(height: height)
        .clipped()
        .overlay(alignment: .topLeading) {
            HStack(alignment: .top, spacing: 6) {
                Rectangle().fill(coverInk).frame(width: 5, height: 5)
                    .padding(.top, 3)
                Text("YOUR BODY.\nYOUR FIT.")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
            }
            .foregroundStyle(coverInk)
            .padding(.leading, margin)
            .padding(.top, wide ? 156 : 100)
            .editorialEntrance(delay: 0.08, from: .leading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .overlay(alignment: .topTrailing) {
            EditorialRunningHead(text: "PERSONAL FITTING / 001", color: coverInk.opacity(0.8),
                                 font: .system(size: 8, weight: .medium, design: .monospaced), tracking: 1.7)
                .frame(height: height * 0.42, alignment: .top)
                .clipped()
                .padding(.trailing, 10)
                .padding(.top, height * 0.34)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 2) {
                Text(room.sizeTitle)
                    .font(Self.isLatin(room.sizeTitle) ? Editorial.serif(wide ? 132 : 88, italic: true) :
                            Editorial.hangul(28, relativeTo: .title))
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .foregroundStyle(Editorial.accent)
                    .contentTransition(.interpolate)
                    .animation(EditorialMotion.editorial(EditorialMotion.glyphDuration), value: room.sizeTitle)
                Text(room.selectedSize?.isSample == true ? "SAMPLE / SIZE" : "YOUR / SIZE")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(Editorial.muted)
            }
            .frame(maxWidth: wide ? 160 : 90, alignment: .leading)
            .padding(.leading, margin)
            .padding(.bottom, 16)
            .editorialEntrance(delay: 0.12, from: .leading, distance: 80)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .overlay(alignment: .bottomTrailing) {
            if !dynamicTypeSize.isAccessibilitySize {
                coverMetadata(profile: profile)
                    .padding(.leading, 8)
                    .frame(maxWidth: 170, alignment: .trailing)
                    .padding(.trailing, margin)
                    .padding(.bottom, 16)
                    .editorialEntrance(delay: 0.16, from: .trailing)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("WEASHION 표지")
    }

    private func coverMetadata(profile: BodyProfile) -> some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 8) {
            if coverStatus?.tone == .progress {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini).tint(Editorial.ink)
                        .accessibilityHidden(true)
                    Text(coverStatus?.title ?? "")
                        .editorialSans(.caption2, weight: .medium)
                }
                .accessibilityIdentifier("coverGarmentUpdating")
                .transition(.opacity)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(weather.temperature, specifier: "%.0f")°")
                    .font(Editorial.serif(30)).monospacedDigit()
                Text(weather.conditionTitle).editorialSans(.caption2)
            }
            Text(isLiveWeather ? weather.locationName : L("샘플 날씨"))
                .editorialSans(.caption2)
                .foregroundStyle(Editorial.muted)
            Text(verbatim: "\(profile.name) / \(String(format: "%.0f", profile.body.height)) cm")
                .editorialSans(.caption2)
                .foregroundStyle(Editorial.muted)
                .accessibilityIdentifier("coverBodyReference")
                .accessibilityValue(Text(verbatim: "\(profile.body.height) cm / \(profile.body.weight) kg"))
        }
        .fixedSize(horizontal: false, vertical: true)
        .animation(EditorialMotion.feedback(reduceMotion: reduceMotion), value: coverStatus)
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coverMetadata")
    }

    private var coverControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            sizeRail
            Button { show(.fitting) } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text("치수까지 자세히 비교")
                    Spacer()
                    Text("FIT STUDY").font(.system(size: 10, weight: .medium, design: .monospaced))
                        .accessibilityHidden(true)
                    Image(systemName: "arrow.up.right")
                }
            }
            .buttonStyle(EditorialButtonStyle(filled: true, accented: true))
            .accessibilityLabel("피팅룸으로 이동")
            .accessibilityIdentifier("quickFittingRoom")
            selectionNotices
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coverFittingControls")
    }

    @ViewBuilder
    private var selectionNotices: some View {
            if let reason = room.fittingUnavailableReason {
                EditorialNotice(title: L("착장 전 확인해 주세요"), detail: reason, tone: .warning)
            }
            if let status = coverStatus, status.isProblem, status.tone != .progress {
                EditorialNotice(title: status.title, detail: status.detail, tone: status.tone)
                    .accessibilityIdentifier("coverSceneStatus")
            }
    }

    /// The forecast sits directly under the cover. The temperature rises into the cover's edge,
    /// the readings keep to a narrow right column, a sky plate bleeds off the right edge like a
    /// cropped photograph, and the day's statement is set across its lower corner.
    private func weatherSpread(wide: Bool, margin: CGFloat) -> some View {
        let temperatureSize = (wide ? 176 : 132) * numeralScale
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 24))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        let plateHeight: CGFloat = wide ? 320 : 230
        return VStack(alignment: .leading, spacing: 0) {
            layout {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(weather.temperature, specifier: "%.0f")°")
                        .font(Editorial.serif(temperatureSize))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                        .animation(EditorialMotion.transition(reduceMotion: reduceMotion), value: weather.temperature)
                        .editorialReveal(from: .leading, distance: 64)
                        .frame(height: temperatureSize * 0.74, alignment: .bottom)
                        .padding(.top, 16)
                        .accessibilityLabel("현재 기온 \(Int(weather.temperature.rounded()))도")
                    Text(weather.conditionTitle).font(Editorial.hangul(22, relativeTo: .title2))
                        .editorialReveal(delay: 0.06)
                    Text(isLiveWeather ? weather.locationName : L("샘플 날씨 · 실제 위치 미연결"))
                        .editorialSans(.caption).foregroundStyle(Editorial.muted)
                    weatherLink
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        EditorialEyebrow(text: "THE FORECAST", color: Editorial.accent)
                        Text("N° 03").font(Editorial.serif(14, italic: true)).foregroundStyle(Editorial.accent)
                            .accessibilityHidden(true)
                    }
                    .padding(.bottom, 8)
                    .editorialReveal(from: .trailing)
                    weatherMetric(L("체감"), value: "\(Int(weather.feelsLike.rounded()))", unit: "°")
                    weatherMetric(L("강수"), value: "\(Int((weather.precipitationProbability * 100).rounded()))", unit: "%")
                    weatherMetric(L("바람"), value: String(format: "%.1f", weather.windSpeed), unit: "m/s")
                }
                .frame(maxWidth: stacked ? .infinity : wide ? 220 : 150, alignment: .trailing)
                .padding(.top, stacked ? 0 : 22)
            }
            // Sky plate: cropped at the trailing edge, with the statement set across its lower-left corner.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                WeatherBackdrop(mood: weather.mood)
                    .frame(width: wide ? 420 : 236, height: plateHeight)
                    .scaleEffect(reduceMotion ? 1 : 1.16)
                    .visualEffect { [reduceMotion] content, geometry in
                        content.offset(y: reduceMotion ? 0 :
                            EditorialMotion.parallaxOffset(minY: geometry.frame(in: .scrollView).minY, limit: 16))
                    }
                    .clipped()
                    .overlay(alignment: .topLeading) {
                        EditorialFigureCaption(number: "02", text: isLiveWeather ? weather.locationName : "SAMPLE SKY")
                            .padding(12)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Text("\(Int((weather.precipitationProbability * 100).rounded()))%")
                            .font(Editorial.serif(44, italic: true))
                            .foregroundStyle(Editorial.accent)
                            .padding(.trailing, margin + 12)
                            .padding(.bottom, 10)
                            .accessibilityLabel("강수 확률 \(Int((weather.precipitationProbability * 100).rounded()))퍼센트")
                    }
            }
            .padding(.trailing, -margin)
            .padding(.top, 40)
            .editorialReveal(from: .trailing, distance: 72)
            EditorialTitle(text: weather.feelsLike < 20 ? L("가볍게\n겹쳐 입는 날.") : L("가볍게\n입는 하루."),
                           pointSize: wide ? 72 : 50, style: .statement, revealsOnScroll: true)
                .padding(.top, -(wide ? 104 : 76))
                .padding(.trailing, wide ? 240 : 96)
            if !weatherManager.hourly.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(weatherManager.hourly) { hour in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(hour.date, format: .dateTime.hour()).editorialSans(.caption2).foregroundStyle(Editorial.muted)
                                Image(systemName: hour.symbol).font(.body.weight(.light))
                                Text("\(hour.temperature, specifier: "%.0f")°").font(Editorial.serif(22 * numeralScale))
                            }
                            .frame(minWidth: 64, alignment: .leading)
                            .padding(.vertical, 10)
                            .overlay(alignment: .leading) { Rectangle().fill(Editorial.rule).frame(width: 0.5) }
                            .padding(.leading, 12)
                        }
                    }
                }
                .padding(.top, 28)
            }
            outfitList
                .padding(.leading, stacked ? 0 : wide ? margin * 3 : 64)
                .padding(.top, 36)
            if let error = locationManager.errorMessage ?? weatherManager.errorMessage {
                EditorialNotice(title: L("날씨 연결을 확인해 주세요"),
                                detail: L("위치 권한과 네트워크 상태를 확인한 후 다시 시도해 주세요. 피팅은 계속 사용할 수 있어요."),
                                tone: .warning)
                    .padding(.top, 24)
                if isLiveWeather {
                    Text("마지막으로 받은 날씨를 표시하고 있어요.")
                        .editorialSans(.caption)
                        .foregroundStyle(Editorial.muted)
                }
                DisclosureGroup(isExpanded: $showWeatherErrorDetails) {
                    Text(error).textSelection(.enabled).padding(.top, 8)
                } label: {
                    Text("오류 상세").frame(minHeight: 44)
                }
                .editorialSans(.caption)
                .foregroundStyle(Editorial.muted)
                .fixedSize(horizontal: false, vertical: true)
                .animation(EditorialMotion.transition(reduceMotion: reduceMotion), value: showWeatherErrorDetails)
            }
            if let url = weatherManager.attributionURL {
                Link(destination: url) {
                    Text("날씨 제공 · Apple Weather ↗")
                        .editorialSans(.caption2)
                        .foregroundStyle(Editorial.muted)
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
            }
        }
    }

    private var weatherLink: some View {
        Button {
            locationManager.requestLocation()
        } label: {
            HStack(spacing: 6) {
                if weatherManager.isLoading || locationManager.isRequesting { ProgressView().controlSize(.mini) }
                Text(weatherManager.isLoading || locationManager.isRequesting ? L("날씨를 불러오는 중") : isLiveWeather ? L("날씨 새로고침") : L("현재 위치 날씨 연결"))
                    .underline()
                Image(systemName: "arrow.right").font(.caption2)
            }
            .editorialSans(.caption, weight: .medium)
            .foregroundStyle(Editorial.accent)
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .disabled(weatherManager.isLoading || locationManager.isRequesting)
        .accessibilityIdentifier("connectWeather")
    }

    private func weatherMetric(_ title: String, value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).editorialSans(.caption).foregroundStyle(Editorial.muted)
            Spacer(minLength: 12)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(Editorial.serif(26 * numeralScale)).monospacedDigit()
                Text(unit).editorialSans(.caption2).foregroundStyle(Editorial.muted)
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Editorial.rule).frame(height: 0.5) }
        .accessibilityElement(children: .combine)
        .editorialReveal(from: .trailing, distance: 32)
    }

    private var closetLook: ClosetLook {
        ClosetRecommendation.look(weather: weather, products: room.library.products)
    }

    /// Today's look as a numbered credit list, chosen from the user's closet slot by slot.
    /// Slots the closet cannot fill show the generic recommendation, marked as a sample.
    private var outfitList: some View {
        let look = closetLook
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(weather.feelsLike < 20 ? "A little layering." : "Keep it light.")
                    .font(Editorial.headline(24 * numeralScale))
                EditorialEyebrow(text: L("TODAY'S LOOK · 내 옷장에서"))
            }
            .editorialReveal(from: .leading)
            VStack(spacing: 0) {
                ForEach(Array(look.picks.enumerated()), id: \.element.id) { index, pick in
                    outfitRow(index: index, pick: pick)
                        .editorialReveal(delay: Double(min(index, 2)) * 0.04, distance: 32)
                }
            }
            Text(look.picks.contains(where: \.isSample)
                 ? L("샘플로 표시된 항목은 보관함에 해당 종류의 옷이 아직 없어 일반 추천을 보여줍니다. 상품을 추가하면 내 옷으로 바뀝니다.")
                 : L("날씨 기준 스타일 가이드 · 마네킹 착장과는 별개입니다."))
                .editorialSans(.caption2)
                .foregroundStyle(Editorial.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func outfitRow(index: Int, pick: ClosetLook.Pick) -> some View {
        let fittable = pick.product.map { product in
            product.kind.supportsFitting && product.sizes.contains { product.definition(for: $0, in: room.catalog) != nil }
        } ?? false
        return Button {
            guard let product = pick.product,
                  let size = product.sizes.first(where: { product.definition(for: $0, in: room.catalog) != nil }) else { return }
            perform {
                try room.select(productID: product.id, sizeID: size.id)
                show(.fitting)
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(String(format: "%02d", index + 1))
                    .font(Editorial.serif(12, italic: true))
                    .foregroundStyle(Editorial.accent)
                    .accessibilityHidden(true)
                Text(pick.slot.title)
                    .editorialSans(.caption)
                    .foregroundStyle(Editorial.muted)
                    .frame(width: 64, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(pick.title).font(Editorial.headline(20, italic: false))
                    Text(pick.isSample ? L("보관함에 추가된 옷 없음 · 샘플 추천") : L("내 옷장 · \(pick.product?.kind.title ?? "")"))
                        .editorialSans(.caption2)
                        .foregroundStyle(Editorial.muted)
                }
                Spacer(minLength: 0)
                if fittable {
                    Image(systemName: "arrow.right").font(.caption2)
                }
            }
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) { Rectangle().fill(Editorial.rule).frame(height: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(EditorialPressStyle())
        .disabled(!fittable)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("look-\(pick.slot.rawValue)")
    }

    // MARK: - Fitting

    @ViewBuilder
    private func fitting(wide: Bool, margin: CGFloat, profile: BodyProfile, stageHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .lastTextBaseline, spacing: 20) {
                EditorialTitle(text: "Fit study.", pointSize: wide ? 64 : 44)
                Spacer(minLength: 0)
                EditorialEyebrow(text: "SAME BODY\nDIFFERENT SIZES", color: Editorial.accent)
                    .multilineTextAlignment(.trailing)
                    .padding(.bottom, 6)
            }
            spreadLayout(wide: wide).callAsFunction {
                VStack(alignment: .leading, spacing: 16) {
                    if !wide {
                        sizeRail
                        sizeComparison
                    }
                    fittingStage(profile: profile, height: stageHeight, margin: margin)
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 20) {
                    if wide {
                        sizeRail
                        sizeComparison
                    }
                    fittingDetails
                    if wide && room.definition != nil { measurementSummary }
                }
                .frame(maxWidth: wide ? 380 : .infinity)
            }
            if room.definition != nil {
                VStack(alignment: .leading, spacing: 24) {
                    EditorialHeading(number: "01", title: "Cut & measure.", subtitle: L("입력한 숫자와 측정 위치를 함께 읽어요."))
                    if !wide { measurementSummary }
                    fittingCalculation
                }
                .editorialReveal()
            }
        }
        .padding(.horizontal, margin)
        .padding(.top, 16)
    }

    private var sizeRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            outfitRail
            HStack(alignment: .center, spacing: 12) {
                Button { sheet = .products } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            if !dynamicTypeSize.isAccessibilitySize {
                                EditorialEyebrow(text: room.selectedSize?.isSample == true ? "SAMPLE GARMENT" : "ON YOUR MANNEQUIN")
                            }
                            Text(room.product?.name ?? L("상품을 선택하세요."))
                                .editorialSans(.headline, weight: .semibold)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 32, height: 44)
                    }
                }
                .buttonStyle(EditorialPressStyle())
                .disabled(showGarmentEditor)
                .accessibilityLabel("\(room.product?.name ?? L("상품 없음")), 상품과 사이즈 보관함 열기")
                .accessibilityIdentifier("openProductLibrary")
                if room.definition != nil {
                    Button { showGarmentEditor = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "ruler").font(.system(size: 16))
                            Text("치수").editorialSans(.caption, weight: .semibold)
                        }
                        .foregroundStyle(Editorial.accent)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(Editorial.accent.opacity(0.06), in: .rect(cornerRadius: 3))
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Editorial.accent.opacity(0.3), lineWidth: 0.5))
                    }
                    .accessibilityLabel("외부 상품 치수 입력")
                    .accessibilityIdentifier("editGarmentMeasurements")
                    .disabled(showGarmentEditor)
                }
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { sizeChoices }
            } else {
                HStack(spacing: 12) {
                    Text("SIZE")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(Editorial.muted)
                        .accessibilityHidden(true)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .center, spacing: 6) { sizeChoices }
                    }
                }
            }
        }
    }

    private var sizeComparison: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let previousSize, let current = room.selectedSize, previousSize.id != current.id,
               let previousMeasurements = previousSize.measurements, previousMeasurements.isValid,
               let currentMeasurements = current.measurements, currentMeasurements.isValid,
               !currentMeasurements.displayed(for: room.product?.templateID ?? "")
                    .editorialDifferences(from: previousMeasurements.displayed(for: room.product?.templateID ?? "")).isEmpty {
                let before = previousMeasurements.displayed(for: room.product?.templateID ?? "")
                let after = currentMeasurements.displayed(for: room.product?.templateID ?? "")
                HStack(alignment: .firstTextBaseline) {
                    Text("입력 치수 차이").editorialSans(.caption2)
                    Spacer()
                    Text("\(previousSize.label) → \(current.label)")
                        .editorialSans(.caption, weight: .semibold)
                        .foregroundStyle(Editorial.accent)
                }
                let columns = dynamicTypeSize.isAccessibilitySize ? 1 : 3
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: columns),
                          alignment: .leading, spacing: 12) {
                    ForEach(after.editorialDifferences(from: before).filter { $0.id != "sleeve" }) { field in
                        comparisonMetric(field.title, value: field.value, unit: field.unit)
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.left.arrow.right").foregroundStyle(Editorial.accent)
                    Text("사이즈를 바꿔 입력 치수 차이를 비교해 보세요.")
                        .editorialSans(.caption)
                        .foregroundStyle(Editorial.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(Editorial.stock.opacity(0.45), in: .rect(cornerRadius: 3))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sizeComparison")
    }

    private func comparisonMetric(_ title: String, value: Double, unit: String = "cm") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).editorialSans(.caption2).foregroundStyle(Editorial.muted)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(value, specifier: "%+.1f")")
                    .font(Editorial.serif(26 * numeralScale)).monospacedDigit()
                    .contentTransition(.numericText(value: value))
                Text(unit).editorialSans(.caption2).foregroundStyle(Editorial.muted)
            }
        }
        .accessibilityElement(children: .combine)
        .animation(EditorialMotion.feedback(reduceMotion: reduceMotion), value: value)
    }

    @ViewBuilder
    private var sizeChoices: some View {
        if let product = room.product {
            ForEach(product.sizes) { size in
                Button {
                    perform { try room.select(productID: product.id, sizeID: size.id) }
                } label: {
                    sizeLabel(size.label, selected: room.library.selectedSizeID == size.id)
                }

                .disabled(showGarmentEditor || product.definition(for: size, in: room.catalog) == nil)
                .accessibilityLabel("\(size.label) 사이즈")
                .accessibilityAddTraits(room.library.selectedSizeID == size.id ? .isSelected : [])
                .accessibilityIdentifier("fitting-size-\(size.id)")
            }
        }
        Button { perform { try room.undress() } } label: {
            sizeLabel(L("미착용"), selected: room.library.selectedSizeID == nil)
        }
        .disabled(showGarmentEditor)
        .accessibilityAddTraits(room.library.selectedSizeID == nil ? .isSelected : [])
    }

    private var outfitRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(room.outfitDefinitions.count) / 4")
                .editorialSans(.caption).monospacedDigit()
                .accessibilityIdentifier("outfitItemCount")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                ForEach([OutfitSlot.top, .bottom, .shoes, .outer]) { slot in
                    let selection = room.selection(in: slot)
                    let product = room.library.products.first { $0.id == selection?.productID }
                    HStack(spacing: 4) {
                        Button {
                            perform { try room.focus(slot: slot) }
                            if selection == nil { sheet = .products }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(slot.title).editorialSans(.caption, weight: .semibold)
                                Text(product?.name ?? L("미착용")).editorialSans(.caption2).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .accessibilityIdentifier("outfit-slot-\(slot.rawValue)")
                        if selection != nil {
                            Button { perform { try room.undress(slot: slot) } } label: {
                                Image(systemName: "xmark").frame(width: 32, height: 44)
                            }
                            .accessibilityLabel("\(slot.title) 미착용")
                            .accessibilityIdentifier("outfit-remove-\(slot.rawValue)")
                        }
                    }
                    .padding(.horizontal, 8)
                    .background(room.product?.kind.slot == slot ? Editorial.accent.opacity(0.08) : Editorial.muted.opacity(0.04))
                    .disabled(showGarmentEditor)
                }
            }
            if room.outfitDefinitions.count > 1 {
                Text("상의·하의·신발·아우터를 각각 한 개씩 착장합니다. 안쪽 표면을 고려한 정적 보정이며 실제 원단 거동·완전한 무관통은 보장하지 않습니다.")
                    .editorialSans(.caption2).foregroundStyle(Editorial.muted)
            }
        }
    }

    private func sizeLabel(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(Self.isLatin(title) ? Editorial.serif(30 * numeralScale) :
                    EditorialFonts.sans(.subheadline, weight: .medium, dynamicTypeSize: dynamicTypeSize))
            .lineLimit(1)
            .padding(.horizontal, 16)
            .frame(minWidth: 52, minHeight: 48)
            .foregroundStyle(selected ? Editorial.paper : Editorial.ink)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 3).fill(Editorial.accent)
                        .matchedGeometryEffect(id: "fitting-size", in: sizeIndicator)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(selected ? .clear : Editorial.rule, lineWidth: 0.5))
            .contentShape(Rectangle())
            .animation(EditorialMotion.transition(reduceMotion: reduceMotion), value: selected)
    }

    private static func isLatin(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { $0.isASCII }
    }

    private func fittingStage(profile: BodyProfile, height: CGFloat, margin: CGFloat, bodyOnly: Bool = false) -> some View {
        return VStack(alignment: .leading, spacing: 0) {
            mannequin(profile: profile, height: height, editorial: true, bodyOnly: bodyOnly, chrome: .studio,
                      chromeInset: 12)
                .overlay(alignment: .topTrailing) {
                    Text(bodyOnly ? "THE ORIGINAL / 003" : "FIT STUDY / 002")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(Editorial.muted)
                        .padding(18)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name).editorialSans(.subheadline, weight: .semibold)
                    Text("\(profile.body.height, specifier: "%.0f") cm / \(profile.body.weight, specifier: "%.0f") kg")
                        .editorialSans(.caption).monospacedDigit()
                        .foregroundStyle(Editorial.muted)
                        .accessibilityIdentifier("personalBodyReference")
                        .accessibilityValue(Text(verbatim: "\(profile.body.height) cm / \(profile.body.weight) kg"))
                }
                Spacer()
                Button("체형 수정") { sheet = .editBody(profile) }
                    .editorialSans(.caption)
                    .frame(minHeight: 44)
                    .disabled(showGarmentEditor)
                    .accessibilityIdentifier("editActiveProfile")
            }
            .padding(.top, 10)
            EditorialFigureCaption(number: bodyOnly ? "03" : "02", text: L("가로 드래그로 회전 · 핀치로 확대"))
                .padding(.top, 4)
        }
    }

    private var fittingDetails: some View {
        VStack(alignment: .leading, spacing: 14) {
            EditorialEyebrow(text: "READ THE NUMBERS", color: Editorial.accent)
            Text("그림이 아니라 숫자가 비교 기준입니다.")
                .editorialSans(.headline, weight: .semibold)
            Text("실제 상품의 핏과 다를 수 있는 근사 미리보기입니다.")
                .editorialSans(.caption)
                .foregroundStyle(Editorial.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let reason = room.fittingUnavailableReason {
                EditorialNotice(title: L("착장 전 확인해 주세요"), detail: reason, tone: .warning)
            }
            if let summary = fitSummary, let kind = room.definition?.kind {
                if kind == .shoes {
                    if let ease = summary.footLengthEase {
                        measurementLine(L("외부 길이 차이"), value: Double(ease) * 1000, signed: true, unit: "mm")
                    } else {
                        Text("발 치수 비교를 계산할 수 없습니다.").editorialSans(.caption)
                    }
                    Text("외부 치수와 발의 차이입니다. 내부 공간이나 실제 착화감 판정이 아닙니다.")
                        .editorialSans(.caption).foregroundStyle(Editorial.muted)
                } else if kind == .pants {
                    if let ease = summary.waistEase {
                        measurementLine(L("허리둘레 여유"), value: Double(ease) * 100, signed: true)
                    }
                } else {
                    measurementLine(summary.primaryEaseTitle, value: Double(summary.primaryEase) * 100, signed: true)
                }
            }
            if room.definition != nil {
                if let url = room.product?.sourceURL {
                    Link(destination: url) {
                        Label("원본 상품 확인 · \(url.host ?? "")", systemImage: "arrow.up.right")
                            .editorialSans(.caption)
                            .frame(minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var fittingCalculation: some View {
        if let summary = fitSummary {
            DisclosureGroup(isExpanded: $showFitDetails) {
                VStack(alignment: .leading, spacing: 12) {
                    switch room.definition?.kind {
                    case .shoes:
                        if let ease = summary.footLengthEase {
                            measurementLine(L("외부 길이 차이"), value: Double(ease) * 1000, signed: true, unit: "mm")
                        }
                        if let ease = summary.footWidthEase {
                            measurementLine(L("외부 너비 차이"), value: Double(ease) * 1000, signed: true, unit: "mm")
                        }
                        Text("신발 외부 치수 − 발 치수의 비교입니다. 브랜드 호수·내부 공간·실제 착화감이나 천 충돌 시뮬레이션을 뜻하지 않습니다.")
                            .editorialSans(.caption).foregroundStyle(Editorial.muted)
                    case .pants:
                        if let ease = summary.waistEase {
                            measurementLine(L("허리둘레 여유"), value: Double(ease) * 100, signed: true)
                        }
                        if let ease = summary.hipEase {
                            measurementLine(L("엉덩이둘레 여유"), value: Double(ease) * 100, signed: true)
                        }
                        measurementLine(L("착장 길이 · 수직"), value: Double(summary.verticalLength) * 100)
                        Text("단면 × 2와 신체 둘레를 비교한 근사값입니다. 실제 원단의 신축률·착용감과 다를 수 있습니다.")
                            .editorialSans(.caption).foregroundStyle(Editorial.muted)
                    default:
                        measurementLine(L("가슴 여유"), value: Double(summary.chestEase) * 100, signed: true)
                        measurementLine(L("어깨 차이"), value: Double(summary.shoulderEase) * 100, signed: true)
                        if let chest = summary.wornChest {
                            measurementLine(L("착장 가슴둘레"), value: Double(chest) * 100)
                        }
                        measurementLine(L("착장 총장 · 수직"), value: Double(summary.verticalLength) * 100)
                        Text("표면 늘어남(상위 5%) \(String(format: "%.1f%%", summary.maximumStrain * 100))")
                            .editorialSans(.caption).foregroundStyle(Editorial.ink)
                        Text("볼록 단면과 정점 변형에 의한 계산값입니다. 실제 원단의 신축률·착용감과 다를 수 있습니다.")
                            .editorialSans(.caption).foregroundStyle(Editorial.muted)
                    }
                }
                .padding(.top, 14)
            } label: {
                Text("착장 계산 상세 · 근사값").frame(minHeight: 44)
            }
            .editorialSans(.subheadline)
            .animation(EditorialMotion.transition(reduceMotion: reduceMotion), value: showFitDetails)
        }
    }

    @ViewBuilder private var measurementSummary: some View {
        if let measurements = previewMeasurements, let profile = room.profile {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    EditorialEyebrow(text: "GARMENT NOTES")
                    Spacer()
                    Text(room.sizeTitle).font(Editorial.serif(15, italic: true)).foregroundStyle(Editorial.accent)
                }
                if garmentDraft != nil {
                    Label("미적용 치수 미리보기 · 적용 전에는 저장되지 않습니다", systemImage: "pencil.line")
                        .editorialSans(.caption)
                        .foregroundStyle(Editorial.muted)
                }
                switch measurements {
                case .shortSleeve(let input):
                    let displayed = GarmentSizeLabelCalibration(templateID: room.product?.templateID ?? "").displayed(input)
                    if room.product?.kind == .shortSleeveTShirt {
                        GarmentMeasurementPlate(size: input)
                    } else {
                        WearableMeasurementSummary(measurements: measurements.displayed(for: room.product?.templateID ?? ""))
                    }
                    let chest = profile.body.measurementValue(.chest, base: profile.base)
                    Text("입력 기준 가슴둘레 차이 \(displayed.chestWidth * 2 - chest, specifier: "%+.1f") cm")
                        .editorialSans(.caption).foregroundStyle(Editorial.ink)
                    Text("가슴단면 × 2 − 신체 가슴둘레. 소재·패턴이 반영된 핏 판정은 아닙니다.")
                        .editorialSans(.caption2).foregroundStyle(Editorial.muted)
                    if room.product?.templateID == "meshy-hoodie" {
                        Text("후디 숫자는 보정된 샘플 기준값입니다. 실제 모델 치수와 구분하며, 기존 착용 형태와 저장값은 유지됩니다.")
                            .editorialSans(.caption2).foregroundStyle(Editorial.muted)
                    }
                case .trousers(let input):
                    WearableMeasurementSummary(measurements: measurements)
                    let waist = profile.body.measurementValue(.waist, base: profile.base)
                    let hip = profile.body.measurementValue(.hip, base: profile.base)
                    measurementLine(L("입력 기준 허리둘레 차이"), value: input.waistWidth * 2 - waist, signed: true)
                    measurementLine(L("입력 기준 엉덩이둘레 차이"), value: input.hipWidth * 2 - hip, signed: true)
                    Text(measurements.editorialMeasurementNote)
                        .editorialSans(.caption).foregroundStyle(Editorial.muted)
                case .footwear:
                    WearableMeasurementSummary(measurements: measurements)
                    Text(measurements.editorialMeasurementNote)
                        .editorialSans(.caption).foregroundStyle(Editorial.muted)
                }
                if room.selectedSize?.isSample == true {
                    Text("설명용 샘플 치수 · 실측 상품 데이터가 아닙니다.")
                        .editorialSans(.caption).foregroundStyle(Editorial.warning)
                }
            }
        }
    }

    private func measurementLine(_ title: String, value: Double, signed: Bool = false, unit: String = "cm") -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(verbatim: String(format: signed ? "%+.1f" : "%.1f", value) + " " + unit).monospacedDigit()
                .contentTransition(.numericText(value: value))
                .animation(EditorialMotion.transition(reduceMotion: reduceMotion), value: value)
        }
        .editorialSans(.subheadline)
    }

    // MARK: - Body

    @ViewBuilder
    private func bodyProfile(wide: Bool, margin: CGFloat, profile: BodyProfile, stageHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                EditorialEyebrow(text: "THE ORIGINAL", color: Editorial.accent)
                Spacer(minLength: 0)
                Button { sheet = .profiles } label: {
                    HStack(spacing: 6) {
                        Text("저장 체형").editorialSans(.caption, weight: .medium)
                        Text("\(room.library.profiles.count)").font(.system(.caption, design: .monospaced))
                        Image(systemName: "arrow.up.right").font(.caption2)
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityLabel("저장 체형 \(room.library.profiles.count)개, 보관함 열기")
                .accessibilityIdentifier("openBodyLibrary")
            }
            EditorialTitle(text: profile.name, pointSize: wide ? 64 : 44, style: .statement)
            HStack(alignment: .lastTextBaseline, spacing: 28) {
                bodyMetric(.height, profile: profile, size: (wide ? 100 : 72) * numeralScale)
                    .editorialEntrance(delay: 0.08, from: .leading, distance: 64)
                bodyMetric(.weight, profile: profile, size: (wide ? 72 : 54) * numeralScale)
                    .editorialEntrance(delay: 0.16, from: .trailing)
                Spacer(minLength: 0)
            }
            spreadLayout(wide: wide).callAsFunction {
                fittingStage(profile: profile, height: stageHeight, margin: margin, bodyOnly: true).frame(maxWidth: .infinity)
                profileDetails(profile).frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, margin)
        .padding(.top, 24)
    }

    private func spreadLayout(wide: Bool) -> AnyLayout {
        wide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 40))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 32))
    }

    private func profileDetails(_ profile: BodyProfile) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            EditorialHeading(number: "01", title: "My proportions.", subtitle: L("직접 측정한 치수일수록 더 나다운 실루엣"))
                .padding(.trailing, dynamicTypeSize.isAccessibilitySize ? 0 : 72)
            VStack(spacing: 0) {
                ForEach(Array([BodyMeasurement.shoulderWidth, .chest, .waist, .hip, .legLength].enumerated()),
                        id: \.element.id) { index, measurement in
                    let row = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                        : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 14))
                    row {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(String(format: "%02d", index + 1))
                                .font(Editorial.serif(12, italic: true))
                                .foregroundStyle(Editorial.accent)
                                .accessibilityHidden(true)
                            Text(measurement.title).editorialSans(.subheadline)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text("\(profile.body.measurementValue(measurement, base: profile.base), specifier: "%.1f")")
                                    .font(Editorial.serif(30 * numeralScale)).monospacedDigit()
                                Text(measurement.unit).editorialSans(.caption2).foregroundStyle(Editorial.muted)
                            }
                            Text(measurementSource(measurement, profile: profile))
                                .editorialSans(.caption2).foregroundStyle(Editorial.muted)
                        }
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) { Rectangle().fill(Editorial.rule).frame(height: 0.5) }
                    .accessibilityElement(children: .combine)
                    .editorialReveal(delay: Double(min(index, 2)) * 0.04, from: .trailing, distance: 32)
                }
            }
            .padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : 56)
            Button { sheet = .editBody(profile) } label: {
                HStack {
                    Text("내 체형과 치수 수정")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(EditorialButtonStyle(filled: true))
        }
    }

    private func bodyMetric(_ measurement: BodyMeasurement, profile: BodyProfile, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(profile.body.measurementValue(measurement, base: profile.base), specifier: "%.0f")")
                    .font(Editorial.serif(size)).monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(measurement.unit).font(Editorial.serif(size * 0.22, italic: true)).foregroundStyle(Editorial.muted)
            }
            Text("\(measurement.title) · \(measurementSource(measurement, profile: profile))")
                .editorialSans(.caption2).foregroundStyle(Editorial.muted)
        }
        .accessibilityElement(children: .combine)
    }

    private func measurementSource(_ measurement: BodyMeasurement, profile: BodyProfile) -> String {
        if profile.body.measuredFields?.contains(measurement) == true { return L("직접 측정") }
        return profile.body.usesEstimatedMeasurement(measurement, base: profile.base) ? L("체형 추정") : L("기본값 / 조절값")
    }

    // MARK: - Shared

    private enum StageChrome { case cover, studio }

    private func mannequin(profile: BodyProfile, height: CGFloat, editorial: Bool, bodyOnly: Bool = false,
                           chrome: StageChrome, chromeInset: CGFloat = 16) -> some View {
        WEASHIONSceneView(
            bodyData: profile.body, mannequinBase: profile.base, weather: weather,
            isBodyPreview: bodyOnly, sceneHeight: height, garmentSelection: .constant(nil),
            garmentOverride: garmentDraft.flatMap { measurements in
                room.definition.flatMap { measurements.applying(to: $0) }
            } ?? room.definition,
            outfitOverride: bodyOnly ? [] : room.outfitDefinitions.map { definition in
                guard definition.id == room.definition?.id, let garmentDraft else { return definition }
                return garmentDraft.applying(to: definition) ?? definition
            },
            isEditorial: editorial,
            fitSummaryOutput: bodyOnly ? nil : $fitSummary,
            showsViewControls: chrome == .studio,
            showsSceneStatus: chrome == .studio,
            statusOutput: chrome == .cover ? $coverStatus : nil,
            editorialBackdropStyle: chrome == .cover ? .transparent : .studio,
            editorialChromeInset: chromeInset,
            sceneLink: sceneLink,
            onSceneReady: chrome == .cover ? onLaunchReady : nil
        )
    }

    enum MainTab: String, CaseIterable, Identifiable {
        case today, fitting, body
        var id: String { rawValue }
        var number: String {
            switch self {
            case .today: "01"
            case .fitting: "02"
            case .body: "03"
            }

        }
        var title: String {
            switch self {
            case .today: L("오늘")
            case .fitting: L("피팅룸")
            case .body: L("내 체형")
            }
        }
        var runningHead: String {
            switch self {
            case .today: L("오늘 · THE DAILY EDIT")
            case .fitting: L("피팅룸 · THE FITTING ROOM")
            case .body: L("내 체형 · THE BODY")
            }
        }
        var edition: String {
            switch self {
            case .today: "THE DAILY FIT / 001"
            case .fitting: "THE FIT STUDY / 002"
            case .body: "THE ORIGINAL / 003"
            }
        }
    }

    private enum MainSheet: Identifiable {
        case products, profiles, settings, editBody(BodyProfile)

        var id: String {
            switch self {
            case .products: "products"
            case .profiles: "profiles"
            case .settings: "settings"
            case .editBody(let profile): "body-\(profile.id)"
            }
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() }
        catch { errorMessage = error.localizedDescription }
    }
}

@MainActor @Observable
final class EditorialPageTransition {
    private(set) var displayed = ContentView.MainTab.today
    private(set) var requested: ContentView.MainTab?
    private(set) var showsPreview = false
    private(set) var showsExtendedStatus = false
    var reduceMotion = false
    var errorMessage: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var preparation: Task<Void, Never>?
    @ObservationIgnored private var preview: Task<Void, Never>?

    func show(_ next: ContentView.MainTab, reduceMotion: Bool,
              prepare: @escaping @MainActor () async throws -> Void) {
        self.reduceMotion = reduceMotion
        if next == displayed {
            cancel()
            return
        }
        guard requested != next else { return }
        cancel()
        requested = next
        errorMessage = nil
        let token = generation
        preview = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(120))
                guard let self, generation == token else { return }
                showsPreview = true
                try await Task.sleep(for: .milliseconds(880))
                guard generation == token else { return }
                showsExtendedStatus = true
            } catch is CancellationError {
                // Fast, cancelled and superseded navigation never needs a preview.
            } catch {
                assertionFailure("Unexpected transition preview error: \(error)")
            }
        }
        preparation = Task { [weak self] in
            do {
                try await prepare()
                try Task.checkCancellation()
                guard let self, generation == token else { return }
                withAnimation(EditorialMotion.page(reduceMotion: self.reduceMotion)) {
                    self.displayed = next
                }
                finish()
            } catch is CancellationError {
                guard let self, generation == token else { return }
                finish()
            } catch {
                guard let self, generation == token else { return }
                errorMessage = error is BodyPreviewRenderer.PreparationError
                    ? L("신체 미리보기를 생성할 수 없습니다") : error.localizedDescription
                finish()
            }
        }
    }

    func cancel() {
        generation += 1
        preparation?.cancel()
        finish()
    }

    private func finish() {
        preview?.cancel()
        preview = nil
        preparation = nil
        requested = nil
        showsPreview = false
        showsExtendedStatus = false
    }
}
