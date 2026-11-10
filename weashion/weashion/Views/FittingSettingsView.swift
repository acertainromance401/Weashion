import SwiftUI

struct FittingSettingsView: View {
    @ObservedObject var room: FittingRoom
    @Environment(\.dismiss) private var dismiss
    @State private var showsProfiles = false
    @State private var showsStory = false
    @AppStorage(WeatherPreview.key) private var previewMoodValue = WeatherMood.cloud.rawValue
    @AppStorage(AppLanguage.key) private var appLanguage = AppLanguage.system.rawValue

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    EditorialPageTitle(number: "04", section: "NOTES & ESSENTIALS",
                                       title: L("설정과 안내"), subtitle: L("나의 기록을 보관하고 사용하는 방법."), style: .statement)
                    Button { showsProfiles = true } label: {
                        EditorialActionLabel(title: L("저장 체형과 기준 모델"), subtitle: L("남성·여성 기준은 체형 커스터마이징에서 변경합니다."))
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        EditorialHeading(number: "00", title: "Language.", subtitle: L("앱에서 사용할 언어"))
                        Picker("언어", selection: $appLanguage) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.title).tag(language.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        // Segmented pickers do not refresh their titles in place; rebuild it with the language.
                        .id(appLanguage)
                        .accessibilityIdentifier("appLanguage")
                        Text("시스템을 선택하면 기기 언어를 따릅니다. 한국어·English·日本語 중 하나로 고정할 수도 있어요.")
                            .editorialSans(.caption).foregroundStyle(Editorial.muted)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        EditorialHeading(number: "01", title: "How to fit.", subtitle: L("외부 상품을 내 마네킹에 입히는 세 단계"))
                        step("01", L("쇼핑몰에서 마음에 든 반팔의 사이즈표를 확인해요."))
                        step("02", L("피팅룸에서 총장·어깨너비·가슴단면·소매길이를 cm로 입력해요."))
                        step("03", L("내 체형 위의 길이와 여유를 돌려 보며 확인해요. 사이즈를 바꿔도 체형은 달라지지 않습니다."))
                        Text("현재는 코튼 반팔 형태만 지원합니다. 상품 URL은 원본 확인용이며 디자인·원단을 자동으로 가져오지 않습니다. 실제 상품의 핏, 착용 가능 여부나 사이즈 적합성을 보장하지 않습니다.")
                        Text("마네킹은 사진 스캔 없이 입력한 치수로 만드는 근사 모델입니다. 상품명·URL 수정은 상품 전체에, 치수 수정은 선택한 사이즈에만 적용됩니다.")
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        EditorialHeading(number: "02", title: "Kept with you.", subtitle: L("이 기기에 보관"))
                        Text("체형 프로필, 상품, 사이즈 치수와 선택 상태를 앱 내부에 저장합니다. 완성된 개인 3D 파일을 별도로 저장하는 것이 아니라 기준 모델에 저장값을 다시 적용합니다.")
                        Text("계정·클라우드 동기화는 제공하지 않습니다. 앱 삭제 후 복원이나 다른 기기로의 이전을 보장하지 않습니다.")
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        EditorialHeading(number: "03", title: "A point of view.", subtitle: L("미리보기의 범위"))
                        Text("상의·하의·신발·아우터를 각각 한 개씩 착장합니다. 안쪽 표면을 고려한 정적 보정이며 실제 원단 거동·완전한 무관통은 보장하지 않습니다.")
                        Text("날씨는 오늘 화면에서 연결을 요청할 때 위치 권한을 사용합니다. 연결하지 않아도 피팅을 사용할 수 있습니다.")
                    }
                    Button { showsStory = true } label: {
                        EditorialActionLabel(title: L("WEASHION 이야기"), subtitle: "THE PERSONAL FITTING JOURNAL")
                    }
                    #if DEBUG
                    VStack(alignment: .leading, spacing: 16) {
                        EditorialHeading(number: "04", title: "Preview weather.", subtitle: L("실제 날씨 연결 전, 표지와 옷차림이 날씨마다 어떻게 바뀌는지 확인"))
                        Picker("미리보기 날씨", selection: $previewMoodValue) {
                            ForEach(WeatherMood.allCases) { mood in
                                Text(mood.title).tag(mood.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("previewWeather")
                        Text("개발 빌드에서만 보이는 스위치입니다. 실제 위치 날씨가 연결되면 무시됩니다.")
                            .editorialSans(.caption).foregroundStyle(Editorial.muted)
                    }
                    #endif
                }
                .editorialSans(.subheadline)
                .lineSpacing(5)
                .padding(24)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(Editorial.paper)
            .editorialNavigationTitle(L("설정과 안내"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { EditorialToolbarButton("닫기") { dismiss() } }
            }
            .sheet(isPresented: $showsProfiles) { BodyLibraryView(room: room) }
            .fullScreenCover(isPresented: $showsStory) {
                EditorialWelcomeView { showsStory = false }
            }
        }
        .tint(Editorial.accent)
        .foregroundStyle(Editorial.ink)
        .editorialSans(.body)
        .buttonStyle(EditorialPressStyle())
    }

    private func step(_ number: String, _ title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(number).font(Editorial.serif(20, italic: true)).foregroundStyle(Editorial.accent)
                .accessibilityHidden(true)
            Text(title).fixedSize(horizontal: false, vertical: true)
        }
    }
}
