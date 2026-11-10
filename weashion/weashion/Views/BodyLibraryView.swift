import SwiftUI

struct BodyLibraryView: View {
    @ObservedObject var room: FittingRoom
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var editing: BodyProfile?
    @State private var creating = false
    @State private var creationDraft: BodySetupDraft?
    @State private var deleting: BodyProfile?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    EditorialPageTitle(number: "03", section: "THE BODY ARCHIVE",
                                       title: L("저장 체형"),
                                       subtitle: L("체형은 보관하고, 피팅에는 한 기준만 사용해요."), animated: true, style: .statement)
                    HStack(alignment: .lastTextBaseline, spacing: 18) {
                        Text(room.library.profiles.count, format: .number)
                            .font(Editorial.serif(64)).monospacedDigit()
                            .foregroundStyle(Editorial.accent)
                            .accessibilityLabel("보관 중인 체형")
                            .accessibilityValue("\(room.library.profiles.count)")
                            .accessibilityIdentifier("savedProfileCount")
                        VStack(alignment: .leading, spacing: 5) {
                            Text("보관 중인 체형").editorialSans(.subheadline)
                            Text("피팅에는 하나의 체형만 사용합니다.").editorialSans(.caption).foregroundStyle(Editorial.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottom) { Rectangle().fill(Editorial.rule).frame(height: 0.5) }
                    Button {
                        creationDraft = nil
                        creating = true
                    } label: {
                        Label("새 체형 만들기", systemImage: "plus")
                    }
                    .buttonStyle(EditorialButtonStyle(filled: true))
                    .accessibilityIdentifier("addBodyProfile")
                    ForEach(Array(room.library.profiles.enumerated()), id: \.element.id) { index, profile in
                        profileRow(profile, index: index)
                    }
                    Text("사용 중인 체형을 바꾸면 같은 상품 치수로 착장을 다시 계산합니다. 상품 기록은 변경하지 않습니다.")
                        .editorialSans(.caption).foregroundStyle(Editorial.muted)
                }
                .padding(24)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(Editorial.paper)
            .editorialSaveFeedback($room.statusMessage)
            .editorialNavigationTitle(L("마네킹 관리"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { EditorialToolbarButton("닫기") { dismiss() } }
            }
            .sheet(item: $editing) { profile in
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
                .presentationDetents([.large])
            }
            .sheet(isPresented: $creating) {
                BodySetupView(room: room, isInitialSetup: false, draft: creationDraft) { creating = false }
                    .presentationDetents([.large])
            }
            .confirmationDialog("체형을 삭제할까요?", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }
            ), presenting: deleting) { profile in
                Button("체형 삭제", role: .destructive) {
                    perform { try room.deleteProfile(profile.id) }
                }
            } message: { profile in
                Text("‘\(profile.name)’의 치수와 조절값을 삭제합니다. 상품 기록은 유지됩니다.")
            }
        }
        .buttonStyle(EditorialPressStyle())
        .tint(Editorial.accent)
        .foregroundStyle(Editorial.ink)
        .editorialSans(.body)
        .editorialError($errorMessage)
    }

    private func profileRow(_ profile: BodyProfile, index: Int) -> some View {
        let active = profile.id == room.library.activeProfileID
        return VStack(alignment: .leading, spacing: 22) {
            Rectangle().fill(active ? Editorial.accent : Editorial.rule).frame(height: active ? 2 : 0.5)
            HStack(alignment: .top, spacing: 18) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(String(format: "%02d", index + 1))
                        .font(Editorial.serif(42, italic: true))
                        .foregroundStyle(Editorial.accent)
                        .frame(minWidth: 40, alignment: .leading)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Label(active ? L("사용 중인 체형") : L("저장한 체형"),
                          systemImage: active ? "checkmark.circle" : "person.crop.square")
                        .editorialSans(.caption2, weight: .semibold)
                        .foregroundStyle(active ? Editorial.paper : Editorial.muted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(active ? Editorial.accent : Editorial.stock, in: .rect(cornerRadius: 2))
                    Text(profile.name).editorialSans(.title2, weight: .semibold)
                    Text("\(profile.base == .male ? L("남성") : L("여성")) 기준 · \(profile.body.height, specifier: "%.1f") cm / \(profile.body.weight, specifier: "%.1f") kg")
                        .editorialSans(.subheadline)
                    Text(profile.updatedAt, format: .dateTime.year().month().day())
                        .editorialSans(.caption).foregroundStyle(Editorial.muted)
                }
                Spacer()
                Menu {
                    Button("체형 수정") { editing = profile }
                    Button("복사해 새로 만들기") {
                        var draft = BodySetupDraft()
                        draft.name = L("\(profile.name) 사본")
                        draft.base = profile.base
                        draft.body = profile.body
                        draft.height = profile.body.height
                        draft.weight = profile.body.weight
                        draft.step = 2
                        creationDraft = draft
                        creating = true
                    }
                    Button("삭제", role: .destructive) { deleting = profile }
                        .disabled(active)
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }
                .accessibilityLabel("\(profile.name) 관리")
            }
            HStack(spacing: 12) {
                Button(active ? L("사용 중") : L("이 체형 사용")) {
                    perform { try room.activateProfile(profile.id) }
                }
                .buttonStyle(EditorialChoiceStyle(selected: active))
                .disabled(active)
                .accessibilityIdentifier("activate-profile-\(profile.id)")
                Button("수정") { editing = profile }
                    .frame(minWidth: 60, minHeight: 44)
                    .accessibilityLabel("\(profile.name) 수정")
            }
        }
        .padding(.bottom, 14)
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() }
        catch { errorMessage = error.localizedDescription }
    }
}
