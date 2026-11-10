# 저장 피드백, 오류와 진행 상태

[전체 목차](./README.md) · [이전: 버튼, 선택과 입력 컨트롤](./controls-and-input.md) · [다음: 화면별 구도, 내비게이션과 선택면](./screen-composition.md)

> 기준: 2026-11-02 원문 가이드의 작업 트리 설명을 종류별로 재분류했습니다. 코드 블록은 실제 소스 발췌이며 독립 실행 예제가 아닙니다. 실제 연결·조건부 표시·보유·미구현의 구분은 그대로 유지합니다.

사용자에게 기능의 실제 상태를 전달하는 요소를 모았습니다. 저장 버튼을 눌렀다는 사실과 저장 성공은 다르며, 준비 중 장면과 완성된 피팅 결과도 다릅니다. 장식 스윕이 아니라 비동기 상태와 취소·실패를 기준으로 표시를 판단합니다.

## 요소 분류와 책임

| 상태 종류 | 전달하는 사실 | 시각·조작 수단 |
| --- | --- | --- |
| 선택 변경 | 현재 선택이 달라짐 | 선택 햅틱과 선택면 |
| 저장 성공 | 실제 저장 revision이 변경됨 | 상단 안전 영역 안내, 체크·문구·닫기와 성공 햅틱 |
| 입력·작업 실패 | 확인·복구가 필요한 오류 | 필드 설명, Notice, alert와 오류 햅틱 |
| 늦은 지면 준비 | 120ms가 지나도 준비가 끝나지 않음 | 다음 지면 예고, 총 1초 후 확장 설명 |
| 계산 중 | 준비·드레이핑·취소 상태 | 기존 장면 5pt 블러, 베일·진행 표시·취소/재시도 |
| 진행선 | 대기 중임을 알림 | CALayer 반복선, Reduce Motion에서는 정적 선 |
| 빈 상태·로드 실패 | 표시할 데이터 없음 또는 로드 실패 | ContentUnavailableView와 추가/재시도 행동 |

## 문서 내 상세 항목

- [17. 실제 저장 성공과 오류를 구분하는 피드백](#snippet-17)
- [18. 화면 준비가 늦을 때만 다음 지면 예고](#snippet-18)
- [38. 진행선, 장면 블러와 계산 상태 오버레이](#snippet-38)

<a id="snippet-17"></a>

## 17. 실제 저장 성공과 오류를 구분하는 피드백

원본: [EditorialStyle.swift / EditorialFeedbackTrigger](../../weashion/weashion/Views/EditorialStyle.swift#L212)

```swift
struct EditorialFeedbackTrigger: Equatable {
    enum Kind: Equatable { case selection, success }

    let saveRevision: Int
    let selection: [String?]

    func kind(since previous: Self) -> Kind? {
        if saveRevision != previous.saveRevision { return .success }
        return selection != previous.selection ? .selection : nil
    }
}
```

- **역할:** 저장 revision 변경과 단순 선택 변경을 구분합니다.
- **연결:** [ContentView의 sensoryFeedback](../../weashion/weashion/ContentView.swift#L75)이 이 판정에 따라 성공 또는 선택 햅틱을 발생시킵니다.
- **주의:** 저장 버튼을 눌렀다는 이유만으로 성공을 표시하는 구조가 아닙니다. 실제 저장 완료와 revision 변경의 연결을 유지해야 합니다.

원본: [EditorialStyle.swift / editorialSaveFeedback](../../weashion/weashion/Views/EditorialStyle.swift#L889)

```swift
func editorialSaveFeedback(_ message: Binding<String?>, horizontalInset: CGFloat = 24) -> some View {
    safeAreaInset(edge: .top, spacing: 0) {
        EditorialStatusMessage(message: message, horizontalInset: horizontalInset)
    }
}
```

- **화면 효과:** 스크롤 최상단으로 돌아가지 않아도 저장 안내를 볼 수 있도록 적용된 뷰의 상단 안전 영역에 메시지를 배치합니다.
- **상세 표시:** [EditorialStatusMessage](../../weashion/weashion/Views/EditorialStyle.swift#L680)가 체크 표시, 실제 변경 문구, 닫기 버튼과 160ms 상태 전환을 제공합니다.

원본: [EditorialStyle.swift / editorialError](../../weashion/weashion/Views/EditorialStyle.swift#L899)

```swift
func editorialError(_ message: Binding<String?>) -> some View {
    alert(L("확인이 필요해요"), isPresented: Binding(
        get: { message.wrappedValue != nil },
        set: { if !$0 { message.wrappedValue = nil } }
    )) {
        Button("확인") { message.wrappedValue = nil }
    } message: {
        Text(message.wrappedValue ?? "")
    }
    .sensoryFeedback(trigger: message.wrappedValue) { _, value in
        value == nil ? nil : .error
    }
}
```

- **역할:** 오류 메시지를 명시적인 alert와 오류 햅틱으로 전달합니다.
- **관련 컴포넌트:** [EditorialNotice](../../weashion/weashion/Views/EditorialStyle.swift#L754)는 정보, 진행, 성공, 주의, 오류를 각주 같은 지면형 안내로 표현합니다.

<a id="snippet-18"></a>

## 18. 화면 준비가 늦을 때만 다음 지면 예고

원본: [ContentView.swift / EditorialPageTransition.show의 preview 작업](../../weashion/weashion/ContentView.swift#L1496)

```swift
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
```

- **처리 순서:** 화면 준비와 예고 타이머가 별도 작업으로 시작됩니다. 120ms가 지나도 준비가 끝나지 않았을 때만 예고를 표시하고, 총 1초가 지나면 설명을 확장합니다.
- **핵심:** `generation == token`이 취소되거나 이전 선택으로 밀린 작업의 표시를 막습니다.
- **중요한 구분:** 이 120ms는 화면 전환에 강제로 추가하는 대기 시간이 아닙니다. 준비가 빨리 끝나면 타이머를 취소하고 바로 표시합니다.
- **완료와 실패:** 같은 타입의 `preparation` 작업이 준비 성공 후 표시 지면을 변경합니다. 실패하면 `errorMessage`에 넣고 `finish`에서 진행 상태를 해제합니다.
- **화면 연결:** [EditorialTransitionPreview](../../weashion/weashion/Views/EditorialStyle.swift#L51)가 예고 UI를 표시하고, 그 내부의 [EditorialPendingRule](../../weashion/weashion/Views/EditorialStyle.swift#L79)이 UIKit/CALayer 기반 진행선을 그립니다.
- **수정 시 경계:** 화면 준비 상태와 [09](./motion.md#snippet-09)의 장식 스윕은 다른 책임입니다. 애니메이션 완료 콜백을 실제 기능 실행 조건으로 바꾸지 않습니다.

<a id="snippet-38"></a>

## 38. 진행선, 장면 블러와 계산 상태 오버레이

원본: [EditorialStyle.swift / EditorialPendingRule.updateAnimation](../../weashion/weashion/Views/EditorialStyle.swift#L116)

```swift
private func updateAnimation() {
    stroke.removeAllAnimations()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    stroke.frame = CGRect(x: 0, y: 0, width: reduceMotion ? 24 : bounds.width * 0.25, height: bounds.height)
    CATransaction.commit()
    guard !reduceMotion, window != nil, bounds.width > 0 else { return }
    let animation = CABasicAnimation(keyPath: "position.x")
    animation.fromValue = -stroke.bounds.width / 2
    animation.toValue = bounds.width + stroke.bounds.width / 2
    animation.duration = 0.75
    animation.repeatCount = .infinity
    stroke.add(animation, forKey: "pending")
}
```

원본: [WEASHIONSceneView.swift / 계산 중 장면 흐림](../../weashion/weashion/Views/WEASHIONSceneView.swift#L752)

```swift
.frame(height: sceneHeight)
.frame(maxWidth: .infinity)
.blur(radius: fittingIsObscured ? 5 : 0)
```

| 상태 요소 | 시각 표현 | 조건과 원본 |
| --- | --- | --- |
| 다음 지면 예고 | 번호·섹션명·작은 설명, 높이 1.5pt의 버건디 진행선 | 실제 준비가 늦을 때. [EditorialTransitionPreview](../../weashion/weashion/Views/EditorialStyle.swift#L51) |
| 진행선 | 폭 25%의 띠가 750ms 간격으로 반복 이동 | window가 있고 Reduce Motion이 아닐 때. 줄이기에서는 폭 24pt 정적 선 |
| 계산 중 장면 | 기존 렌더 표면에 5pt 블러 | 준비/드레이핑/취소 상태. [fittingIsObscured](../../weashion/weashion/Views/WEASHIONSceneView.swift#L787) |
| 계산 오버레이 | Paper 82% 베일, ProgressView 또는 pause.circle, 단계·슬롯 개수, 설명과 취소/재시도 버튼 | [fittingLoadingOverlay](../../weashion/weashion/Views/WEASHIONSceneView.swift#L791) |
| 지면형 상태 | 가는 선, 이탤릭 Note/In progress/Saved/Attention/Error, 산세리프 메시지, progress의 작은 스피너 | [EditorialNotice](../../weashion/weashion/Views/EditorialStyle.swift#L754) |
| 저장 성공 | 체크 아이콘, 저장 문구, 실제 변경 내용, 44pt 닫기 | [EditorialStatusMessage](../../weashion/weashion/Views/EditorialStyle.swift#L680) |
| 오류 | 필드 밑줄과 설명, 경고 Notice, 시스템 alert | [editorialError](../../weashion/weashion/Views/EditorialStyle.swift#L899) |
| 빈 상태·로드 실패 | 시스템 ContentUnavailableView의 아이콘·제목·설명과 재시도/추가 행동 | [메인 로드 실패](../../weashion/weashion/ContentView.swift#L49), [상품 빈 상태](../../weashion/weashion/Views/ProductLibraryView.swift#L42) |

미완성 장면을 흐리게 보여주는 상태와 완성된 피팅 결과는 다릅니다. 흐린 형상을 완성본이나 성공 안내로 설명하지 않습니다.

## 변경·검증 체크리스트

- 저장 성공은 버튼 탭이 아니라 실제 저장 완료와 revision 변경에서 발생하는지 확인합니다.
- 스크롤 최상단으로 돌아가지 않아도 저장 안내를 볼 수 있는지 확인합니다.
- 빠른 준비·취소·다음 선택으로 대체된 작업은 이전 예고를 남기지 않는지 확인합니다.
- 120ms와 총 1초는 예고 표시 임계값이며, 빠른 전환에 강제 대기를 추가하지 않는지 확인합니다.
- 진행선은 화면에 붙어 있고 크기가 있을 때만 움직이며 Reduce Motion에서 정적으로 표시되는지 확인합니다.
- 오류를 성공처럼 숨기지 않고 실제 실패 문구와 복구 행동을 유지합니다.
- 흐린 미완성 형상이나 샘플을 완성된 피팅 결과로 표시하지 않습니다.

## 함께 보는 문서

- [버튼, 선택과 입력 컨트롤](./controls-and-input.md): CTA·선택 버튼·눌림·입력 포커스·오류 이동과 시스템 컨트롤의 외형·동작을 다룹니다.
- [모션, 등장과 화면 전환](./motion.md): 모션 토큰, 스크롤 리빌, 제목 등장, 글자 교체, 스윕·패럴랙스와 소개·실행 전환을 모았습니다.
- [3D 형상, 렌더링과 시점 조작](./rendering-and-gestures.md): SceneKit 출력과 RealityKit 형상·재질 연결, 카메라·조명·몸·의류 외관과 회전·확대를 다룹니다.
- [검증, 전체 인벤토리와 구현 경계](./validation-and-inventory.md): 경계값 테스트, 전체 시각 타입·효과·형상 생성 경로와 미구현·미확인 요소를 한곳에서 찾습니다.
