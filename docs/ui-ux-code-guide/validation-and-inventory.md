# 검증, 전체 인벤토리와 구현 경계

[전체 목차](./README.md) · [이전: 이미지 자산, 폰트 파일과 아이콘](./assets-and-icons.md)

> 기준: 2026-11-02 원문 가이드의 작업 트리 설명을 종류별로 재분류했습니다. 코드 블록은 실제 소스 발췌이며 독립 실행 예제가 아닙니다. 실제 연결·조건부 표시·보유·미구현의 구분은 그대로 유지합니다.

각 종류별 문서가 전체 구현 표면에서 어디에 연결되는지 확인하는 문서입니다. 판단 함수 테스트와 실제 화면 검수의 범위를 구분하며, 미구현·제외·직접 참조 미확인 상태를 명시합니다. 이번 재분류는 원문을 옮긴 문서 작업이며 앱의 현재 동작을 새로 실행 검증했다는 뜻이 아닙니다.

## 요소 분류와 책임

| 검증 대상 | 확인하는 내용 | 이 확인만으로 보장하지 않는 것 |
| --- | --- | --- |
| 공통 판단 함수 | 제목 모션 허용 조건, 699/700pt 열 경계 | 실제 잘림·터치·프레임 성능 |
| 기존 UI 테스트 | 큰 글씨·가로 배치·입력·저장 안내의 검증 위치 | 이번 문서 작업에서 새로 실행한 결과 아님 |
| 시각 타입 | View·Modifier·Style·Representable·Shape 연결 | 모든 타입이 모든 화면에서 항상 표시됨을 의미하지 않음 |
| 형상 경로 | 입력→몸·의류 계산→표면→출력 | 사진 기반 피팅·브랜드 정답 사이즈 보장 아님 |
| 효과 인덱스 | 종류별 트리거·표시 표면·상세 문서 | 모든 효과가 같은 접근성 정책을 가진다는 의미 아님 |
| 자산·미구현 경계 | 실제 연결·보유·설계·제외·미확인 | 파일 존재만으로 런타임 사용을 단정하지 않음 |
| 문서 이동 | 48개 원문 항목과 57개 코드 블록, 링크·앵커 보존 | 앱 빌드·실기기 품질 검수와 별개 |

## 문서 내 상세 항목

- [24. 접근성 및 반응형 경계값을 검증하는 테스트](#snippet-24)
- [46. 직접 그리는 코드와 형상을 만드는 코드의 연결](#snippet-46)
- [47. 움직임과 화면 효과의 전체 빠른 인덱스](#snippet-47)
- [48. 참고 자산, 미구현 요소와 검증 한계](#snippet-48)

<a id="snippet-24"></a>

## 24. 접근성 및 반응형 경계값을 검증하는 테스트

원본: [EditorialDesignTests.swift / 제목 모션과 폭 경계 테스트](../../weashion/weashionTests/EditorialDesignTests.swift#L368)

```swift
@Test func editorialTitleMotionIsOptionalForAccessibility() {
    #expect(EditorialMotion.allowsTitleMotion(reduceMotion: false, voiceOver: false, accessibility: false))
    #expect(!EditorialMotion.allowsTitleMotion(reduceMotion: true, voiceOver: false, accessibility: false))
    #expect(!EditorialMotion.allowsTitleMotion(reduceMotion: false, voiceOver: true, accessibility: false))
    #expect(!EditorialMotion.allowsTitleMotion(reduceMotion: false, voiceOver: false, accessibility: true))
}

@MainActor
@Test func editorialSpreadsReflowAtTheContentWidthBoundary() {
    #expect(!EditorialLayout.usesColumns(width: 699, accessibility: false))
    #expect(EditorialLayout.usesColumns(width: 700, accessibility: false))
    #expect(!EditorialLayout.usesColumns(width: 1200, accessibility: true))
}
```

- **검증 내용:** 제목 모션이 접근성 설정에서 비활성화되는지, 699pt와 700pt 경계에서 배치 판단이 달라지는지 확인합니다.
- **한계:** 상수와 판단 함수 테스트만으로 실제 화면의 잘림, 프레임 성능, 터치 동작을 보장하지는 않습니다.
- **관련 UI 테스트:** [weashionUITests.swift](../../weashion/weashionUITests/weashionUITests.swift)의 `testInteractiveCoverSupportsAccessibilityTextSize`, `testLandscapeLayout`, `testGarmentInputValidationAndPersistence`, `testSavedFeedbackIsVisibleWithoutScrollingBackToTheTop` 등을 확인합니다.
- **실행 여부:** 이 문서 작성에서는 앱 소스를 변경하지 않았으며 빌드와 앱 테스트를 실행하지 않았습니다. 기존 테스트의 위치와 의도를 설명한 것입니다.

<a id="snippet-46"></a>

## 46. 직접 그리는 코드와 형상을 만드는 코드의 연결

화면이 만들어지는 경로를 책임별로 읽으면 장식 수정과 피팅 계산 변경을 구분할 수 있습니다.

| 단계 | 코드·리소스 | 시각 결과에 미치는 영향 |
| --- | --- | --- |
| 지면 조립 | [ContentView](../../weashion/weashion/ContentView.swift), [목적별 Views](../../weashion/weashion/Views) | 어떤 요소를 어느 위치·순서·조건에 표시하는지 결정 |
| 공통 표현 | [EditorialStyle](../../weashion/weashion/Views/EditorialStyle.swift), [EditorialFonts](../../weashion/weashion/Views/EditorialFonts.swift) | 색, 글꼴, 선, 모션과 반응형 기준 |
| 사용자 입력·형태 상태 | [UserBody](../../weashion/weashion/Models/UserBody.swift), [BodyShapeProfile](../../weashion/weashion/Models/BodyShapeProfile.swift), [BodyMeasurement](../../weashion/weashion/Models/BodyMeasurement.swift) | 실제 치수·체형 프리셋·시각 배율 |
| 신체 형상 계산 | [BodyPreviewRenderer](../../weashion/weashion/Models/BodyPreviewRenderer.swift), [MannequinMesh](../../weashion/weashion/Models/MannequinMesh.swift), [ParametricBody](../../weashion/weashion/Models/ParametricBody.swift), [BodyAnatomy](../../weashion/weashion/Models/BodyAnatomy.swift), [BodySkeleton](../../weashion/weashion/Models/BodySkeleton.swift) | 입력에 맞춘 정점·부위·골격·실루엣 |
| 몸 표면·재질 | [BodySurfaceMesh](../../weashion/weashion/Views/BodySurfaceMesh.swift), [WEASHIONMannequin](../../weashion/weashion/Views/WEASHIONMannequin.swift) | 법선, mesh, 회색 재질과 몸 root |
| 의류 정의 | [GarmentDefinition](../../weashion/weashion/Models/GarmentDefinition.swift), [GarmentSizing](../../weashion/weashion/Models/GarmentSizing.swift), [garments.json](../../weashion/weashion/Resources/garments.json) | 선택 모델·치수·외관 설정 |
| 의류 배치·계산 | [GarmentController](../../weashion/weashion/Views/GarmentController.swift), [GarmentDraper](../../weashion/weashion/Services/GarmentDraper.swift), [GarmentFit](../../weashion/weashion/Models/GarmentFit.swift), [LowerGarmentFitter](../../weashion/weashion/Models/LowerGarmentFitter.swift), [GarmentSleeveBinding](../../weashion/weashion/Models/GarmentSleeveBinding.swift), [ClothPhysics](../../weashion/Packages/ClothPhysics) | 몸·치수에 따른 의류의 실제 표시 정점, 소매·하의·레이어 배치와 계산 상태 |
| 의류 표면 | [GarmentRenderer](../../weashion/weashion/Views/GarmentRenderer.swift) | 평활화, 안팎 표면, 마감 형상과 재질 |
| 실제 출력 | [WEASHIONSceneView](../../weashion/weashion/Views/WEASHIONSceneView.swift), 내부 `MannequinRenderView`, `MannequinSceneSurface` | SceneKit 렌더링, 카메라·광원·상태와 SwiftUI 연결 |
| 시점 공유 | [EditorialSceneLink와 EditorialScenePose](../../weashion/weashion/Views/WEASHIONSceneView.swift#L252) | 오늘/피팅룸에서 회전·줌·초점 유지 |

계산 알고리즘의 모든 공식을 이 문서에 전사하지는 않습니다. 여기서는 **실제 화면 형상을 만드는 경로**와 시각 디자인을 직접 다루는 경로를 빠짐없이 연결하는 데 초점을 둡니다.

#### 시각 타입 인벤토리

현재 앱 Swift 소스에서 View, ViewModifier, ButtonStyle, UIViewRepresentable, Shape로 선언된 타입을 아래에 묶었습니다. 내부 보조 타입까지 포함합니다.

| 파일 | 시각 타입 | 설명 위치 |
| --- | --- | --- |
| [ContentView.swift](../../weashion/weashion/ContentView.swift) | `ContentView` | [10](./motion.md#snippet-10)~[18](./feedback-and-loading.md#snippet-18), [30](./screen-composition.md#snippet-30)~[33](./screen-composition.md#snippet-33), [37](./screen-composition.md#snippet-37) |
| [EditorialStyle.swift](../../weashion/weashion/Views/EditorialStyle.swift) | `EditorialSansText` | [02](./typography.md#snippet-02) |
| 동일 파일 | `EditorialTransitionPreview`, `EditorialPendingRule` | [18](./feedback-and-loading.md#snippet-18), [38](./feedback-and-loading.md#snippet-38) |
| 동일 파일 | `EditorialButtonStyle`, `EditorialPressStyle`, `EditorialChoiceStyle`, `EditorialPressFeedback` | [03](./controls-and-input.md#snippet-03), [05](./controls-and-input.md#snippet-05), [39](./controls-and-input.md#snippet-39) |
| 동일 파일 | `EditorialReveal`, `EditorialPageSweep`, `EditorialDisplayGlyph`, `EditorialTitle` | [06](./motion.md#snippet-06)~[09](./motion.md#snippet-09) |
| 동일 파일 | `EditorialHeading`, `EditorialRule`, `EditorialPageTitle`, `EditorialFigureCaption`, `EditorialEyebrow`, `EditorialRunningHead` | [27](./editorial-graphics.md#snippet-27), [28](./typography.md#snippet-28) |
| 동일 파일 | `EditorialStudioBackdrop`, `EditorialActionLabel` | [28](./typography.md#snippet-28), [29](./editorial-graphics.md#snippet-29) |
| 동일 파일 | `EditorialStatusMessage`, `EditorialNotice` | [17](./feedback-and-loading.md#snippet-17), [38](./feedback-and-loading.md#snippet-38) |
| 동일 파일 | `EditorialNavigationTitle`, `EditorialToolbarButton` | [28](./typography.md#snippet-28) |
| 동일 파일 | `EditorialInputSurface`, `EditorialTextField` | [16](./controls-and-input.md#snippet-16), [39](./controls-and-input.md#snippet-39) |
| 동일 파일 | `GarmentIllustration` | [34](./editorial-graphics.md#snippet-34) |
| [EditorialGarmentSpread.swift](../../weashion/weashion/Views/EditorialGarmentSpread.swift) | `GarmentMeasurementPlate`, `EditorialSizeSpread`, `EditorialGarmentArtwork`, `WearableSilhouette` | [15](./layout.md#snippet-15), [34](./editorial-graphics.md#snippet-34), [35](./measurement-diagrams.md#snippet-35) |
| [BodyMeasurementGuide.swift](../../weashion/weashion/Views/BodyMeasurementGuide.swift) | `BodyMeasurementGuideSheet`, `BodyMeasurementDiagram`, `ClothingMeasurementComparisonSheet` | [36](./measurement-diagrams.md#snippet-36) |
| [BodySetupView.swift](../../weashion/weashion/Views/BodySetupView.swift) | `BodySetupView` | [12](./layout.md#snippet-12), [37](./screen-composition.md#snippet-37) |
| [BodyEditorView.swift](../../weashion/weashion/Views/BodyEditorView.swift) | `BodyEditorView` | [37](./screen-composition.md#snippet-37), [39](./controls-and-input.md#snippet-39) |
| [BodyLibraryView.swift](../../weashion/weashion/Views/BodyLibraryView.swift) | `BodyLibraryView` | [37](./screen-composition.md#snippet-37) |
| [GarmentEditorView.swift](../../weashion/weashion/Views/GarmentEditorView.swift) | `GarmentEditorView` | [16](./controls-and-input.md#snippet-16), [37](./screen-composition.md#snippet-37) |
| [WearableMeasurementsEditor.swift](../../weashion/weashion/Views/WearableMeasurementsEditor.swift) | `WearableMeasurementSummary`, `WearableMeasurementsEditor` | [35](./measurement-diagrams.md#snippet-35), [37](./screen-composition.md#snippet-37) |
| [ProductLibraryView.swift](../../weashion/weashion/Views/ProductLibraryView.swift) | `ProductLibraryView`, `ProductDetailView`, `ProductMetadataEditor` | [14](./layout.md#snippet-14), [34](./editorial-graphics.md#snippet-34), [37](./screen-composition.md#snippet-37) |
| [WeatherBackdrop.swift](../../weashion/weashion/Views/WeatherBackdrop.swift) | `WeatherBackdrop` | [20](./weather-graphics.md#snippet-20), [32](./weather-graphics.md#snippet-32) |
| [EditorialWelcomeView.swift](../../weashion/weashion/Views/EditorialWelcomeView.swift) | `EditorialWelcomeView` | [21](./motion.md#snippet-21), [37](./screen-composition.md#snippet-37) |
| [FittingSettingsView.swift](../../weashion/weashion/Views/FittingSettingsView.swift) | `FittingSettingsView` | [37](./screen-composition.md#snippet-37) |
| [LaunchSplashView.swift](../../weashion/weashion/Views/LaunchSplashView.swift) | `LaunchSplashView` | [22](./motion.md#snippet-22), [37](./screen-composition.md#snippet-37), [44](./assets-and-icons.md#snippet-44) |
| [weashionApp.swift](../../weashion/weashion/weashionApp.swift) | `LaunchSplashContainer` | [22](./motion.md#snippet-22) |
| [WEASHIONSceneView.swift](../../weashion/weashion/Views/WEASHIONSceneView.swift) | `MannequinRenderView`, `WEASHIONSceneView`, `MannequinInteractionView` | [19](./rendering-and-gestures.md#snippet-19), [38](./feedback-and-loading.md#snippet-38), [40](./rendering-and-gestures.md#snippet-40), [41](./rendering-and-gestures.md#snippet-41) |

<a id="snippet-47"></a>

## 47. 움직임과 화면 효과의 전체 빠른 인덱스

| 효과 종류 | 현재 사용되는 대상 | 스니펫 |
| --- | --- | --- |
| opacity·밝기·축소 | 버튼 눌림, 비활성 명도 | [03](./controls-and-input.md#snippet-03), [05](./controls-and-input.md#snippet-05) |
| 색·테두리·채움 전환 | 탭, 사이즈, 선택 버튼, 입력 포커스와 오류 | [31](./screen-composition.md#snippet-31), [39](./controls-and-input.md#snippet-39) |
| 한 번의 스크롤 등장 | 날씨 숫자·행·하늘판·카피, 치수, 아카이브 아트워크 | [06](./motion.md#snippet-06), [33](./screen-composition.md#snippet-33)~[35](./measurement-diagrams.md#snippet-35) |
| 마스크 진입 | 표지 제호·캡션, 줄 단위 제목 | [06](./motion.md#snippet-06), [07](./motion.md#snippet-07), [30](./screen-composition.md#snippet-30) |
| 고정 회전·크롭 | 세로 러닝헤드 90도, 상품 컷아웃 -7도, 소개 반팔 -8도, 화면 경계 잘림 | [28](./typography.md#snippet-28), [30](./screen-composition.md#snippet-30), [34](./editorial-graphics.md#snippet-34), [37](./screen-composition.md#snippet-37) |
| 숫자·문자 교체 | numericText 치수·기온·단계 숫자, interpolate 표지 사이즈. 상하 교체 컴포넌트는 보유하되 현재 직접 사용 미확인 | [08](./motion.md#snippet-08), [31](./screen-composition.md#snippet-31), [33](./screen-composition.md#snippet-33), [35](./measurement-diagrams.md#snippet-35), [37](./screen-composition.md#snippet-37) |
| 선택 배경·선의 연결 | `selectedTab`, `fitting-size`, `size-note`, `setup-step`, `selectedPage`의 matched geometry | 31, 34, [37](./screen-composition.md#snippet-37) 및 [21](./motion.md#snippet-21)의 소개 진행선 |
| 지면 스윕 | 35% 폭의 버건디 띠 | [09](./motion.md#snippet-09) |
| 선 리빌 | 제목 위 이중 구분선 | [27](./editorial-graphics.md#snippet-27) |
| 스크롤 패럴랙스 | 표지 ±10pt, 하늘판 ±16pt와 확대 | [10](./motion.md#snippet-10), [33](./screen-composition.md#snippet-33) |
| 페이드·작은 이동 전환 | 소개 페이지, 상품 등록 단계, 저장·기상·3D 상태 | [17](./feedback-and-loading.md#snippet-17), [21](./motion.md#snippet-21), [37](./screen-composition.md#snippet-37), [38](./feedback-and-loading.md#snippet-38) |
| 높이 변화 | 상세 치수, 날씨 상세, 세부 부위, 상품 추가 정보의 펼침·접힘 | [37](./screen-composition.md#snippet-37), [39](./controls-and-input.md#snippet-39) |
| 진행 애니메이션 | CALayer 진행선, 시스템 ProgressView | [18](./feedback-and-loading.md#snippet-18), [38](./feedback-and-loading.md#snippet-38) |
| 블러·베일 | 구름·눈·태양의 부드러움, 스튜디오 타원, 계산 중 흐림 | [29](./editorial-graphics.md#snippet-29), [32](./weather-graphics.md#snippet-32), [38](./feedback-and-loading.md#snippet-38) |
| 그라데이션 | 날씨 하늘과 하단 대비, 소개의 어두운 베일, 스튜디오 빛 면, 반팔 음영 | [29](./editorial-graphics.md#snippet-29), [32](./weather-graphics.md#snippet-32), [34](./editorial-graphics.md#snippet-34), [37](./screen-composition.md#snippet-37) |
| 전체 실행 전환 | 스플래시 최소 시간과 본문 표시 | [22](./motion.md#snippet-22) |
| 시스템 전환 | sheet, inspector, fullScreenCover, 메뉴, 경고, 키보드 | [13](./layout.md#snippet-13), [39](./controls-and-input.md#snippet-39) |
| 실제 3D 변화 | 사용자 회전·확대, 입력 치수에 따른 몸·의류, 재계산 결과 | [19](./rendering-and-gestures.md#snippet-19), [40](./rendering-and-gestures.md#snippet-40)~[43](./rendering-and-gestures.md#snippet-43), [46](#snippet-46) |

**접근성 적용은 효과별로 다릅니다.** 공통 제목은 Reduce Motion·VoiceOver·접근성 글씨를 확인하지만, 모든 직접 `withAnimation`, 시스템 전환, 고정 회전과 3D 사용자 조작이 같은 조건을 공유하는 것은 아닙니다. 원본 호출부의 분기를 우선합니다.

<a id="snippet-48"></a>

## 48. 참고 자산, 미구현 요소와 검증 한계

| 구분 | 현재 문서에서의 취급 |
| --- | --- |
| 외부 디자인 레퍼런스 | [25](./design-principles.md#snippet-25)의 설계 문서에 기록된 편집 원리. 외부 사이트의 현재 화면이나 자산을 새로 가져오지 않음 |
| 앱에서 사용하는 2D 파일 | [44](./assets-and-icons.md#snippet-44)의 BrandMark, 실행·소개 아트워크와 시스템 앱 아이콘 |
| 보유하되 Swift 직접 참조 미확인 | BrandIcon 계열 SVG 3종. 현재 UI에 표시된다고 단정하지 않음 |
| 보유하되 현재 호출 미확인 | `EditorialDisplayGlyph`의 상하 교체. 현재 표지 글자 보간과 구분 |
| 저장소 루트의 사진·영상 | 이름이나 존재만으로 UI 레퍼런스·실제 상품 이미지라고 지정하지 않음. 앱 코드의 확인된 Image 호출과 구분 |
| Blender·reference 자료 | [reference 폴더](../../weashion/reference)와 [변환 보고서](../../weashion/reference/garments/conversion_report.md)는 3D 제작·검증 자료. 앱에 그대로 표시하는 2D 배경이 아님 |
| App Store 자료 | [AppStoreScreenshots 폴더](../../AppStoreScreenshots)는 앱 런타임 렌더 경로와 구분 |
| 실제 옷 사진 아카이브 | 장기 확장으로 기록되어 있으며 현재 도식·상품 URL을 사진 자동 수집 기능으로 설명하지 않음 |
| 원단 스와치·재질 기반 텍스처 | 승인 범위에서 제외. 텍스트 재질·두께 정보와 기존 고정 외관 렌더링은 존재 |
| 정면·측면·후면 바로보기, 오늘 목차 | 설계에서 제외된 항목. 기존 회전·확대·초기화와 혼동하지 않음 |
| 3D 캡처를 다음 화면에 옮기는 전환 | 이전 버전에서 제거. 현재는 2D 스윕과 시점 공유를 사용 |
| 사진 기반 피팅·브랜드 정답 사이즈 | 현재 형상·도식이 이를 보장하지 않음 |
| 커스텀 셰이더·시간 기반 날씨 입자 | 현재 확인한 앱 소스와 리소스에서 별도 shader 파일이나 해당 날씨 타임라인 구현이 확인되지 않음 |
| 실기기 시각 품질·FPS | 코드 상수·렌더 설정만으로 60fps, 실제 동적 그림자, 발열·햅틱 품질을 보장하지 않음 |

#### 이 문서의 검증 방식

- 모든 코드 블록은 연결한 원본 파일의 실제 연속 구간과 대조합니다. Swift와 SVG를 구분합니다.
- 상대 경로, 파일·폴더 링크, 이미지 미리보기의 src와 내부 목차를 확인합니다.
- 앱의 시각 타입 인벤토리, 자산 카탈로그 파일, 폰트, 표시 메시 리소스가 문서에서 연결되는지 확인합니다.
- 문서만 수정하는 작업이므로 앱 빌드·UI 테스트·실기기 시각 검수는 새로 수행하지 않습니다. 기존 테스트의 위치는 [24](#snippet-24)에 있습니다.
- 설명 대상의 현재 코드와 과거 설계 기록이 다르면 현재 코드의 값과 실제 연결 여부를 우선합니다.

## 변경·검증 체크리스트

- 변경된 토큰·판단 함수와 직접 연결된 기존 단위 테스트부터 확인합니다.
- 실제 레이아웃·포커스·저장 안내는 관련 UI 테스트와 화면 확인의 대상으로 구분합니다.
- 시각 타입·자산·메시 리소스의 연결과 문서 링크가 누락되지 않는지 확인합니다.
- 정의만 있는 타입과 현재 직접 호출되는 효과를 구분합니다.
- 문서만 수정하는 경우 코드 블록·상대 경로·앵커·이미지 src 보존을 확인하고 앱 테스트를 실행한 것처럼 쓰지 않습니다.
- 새 기능을 설명할 때 [48](#snippet-48)의 제외·미구현 항목을 기존 구현으로 오인시키지 않습니다.

## 함께 보는 문서

- [디자인 원칙과 레퍼런스](./design-principles.md): 에디토리얼 레퍼런스를 화면의 구도·위계·조작 원칙으로 해석한 기준입니다.
- [반응형 배치, 간격과 표시 컨테이너](./layout.md): 폭·글씨 크기·콘텐츠 요구 크기에 따른 열 배치, 그리드, 여백과 sheet/inspector를 구분합니다.
- [저장 피드백, 오류와 진행 상태](./feedback-and-loading.md): 실제 저장 결과, 오류 alert, 늦은 화면 준비 예고와 계산 중 진행선·블러·오버레이를 구분합니다.
- [3D 형상, 렌더링과 시점 조작](./rendering-and-gestures.md): SceneKit 출력과 RealityKit 형상·재질 연결, 카메라·조명·몸·의류 외관과 회전·확대를 다룹니다.
