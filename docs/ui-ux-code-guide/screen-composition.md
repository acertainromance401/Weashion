# 화면별 구도, 내비게이션과 선택면

[전체 목차](./README.md) · [이전: 저장 피드백, 오류와 진행 상태](./feedback-and-loading.md) · [다음: 날씨 배경과 대기 그래픽](./weather-graphics.md)

> 기준: 2026-11-02 원문 가이드의 작업 트리 설명을 종류별로 재분류했습니다. 코드 블록은 실제 소스 발췌이며 독립 실행 예제가 아닙니다. 실제 연결·조건부 표시·보유·미구현의 구분은 그대로 유지합니다.

색·서체·그래픽·컨트롤을 실제 지면에 조립한 결과를 설명합니다. 공통 요소의 모양은 해당 종류별 문서에서 다루고, 여기서는 레이어 순서·읽는 순서·주요 행동과 정보의 관계를 다룹니다. 현재 오늘 화면은 조작형 표지, 사이즈 노트, 상세 날씨 순서입니다.

## 요소 분류와 책임

| 화면·영역 | 중심 피사체와 읽는 순서 | 조작·상태 경계 |
| --- | --- | --- |
| 오늘 표지 | 날씨 뒤 제호, 중앙 개인 마네킹, 가장자리 메타 | 착장 슬롯·상품·사이즈·피팅 CTA |
| 헤더·하단 바 | 브랜드, 현재 지면, 호수·날짜와 장 번호 | 선택 배경 matched geometry와 실제 지면 상태 |
| 상세 날씨 | 큰 기온, 좁은 기상 열, 하늘판과 겹친 제목 | 실제 예보·샘플·출처·오류 상태 구분 |
| 피팅룸 | 같은 몸, 스튜디오, 치수 비교와 계산 상세 | 사이즈 비교와 외부 시점 조작 |
| 체형·보관함 | 실제 이름·치수·개인 3D, 활성 체형 배지 | 저장한 체형과 사용 중인 체형 구분 |
| 편집·최초 설정 | 단계·도식·미리보기·필드·하단 적용 | 유효 값·오류·선택 단계의 대응 |
| 소개·실행·설정 | 분위기와 카피 또는 목적별 설정 행 | 최초 체형 생성과 브랜드 소개 진입을 구분 |

## 문서 내 상세 항목

- [30. 표지의 겹침과 가장자리 편집](#snippet-30)
- [31. 헤더, 하단 바, 사이즈와 착장 슬롯의 선택면](#snippet-31)
- [33. 날씨 지면의 큰 숫자, 사진 같은 크롭과 겹친 제목](#snippet-33)
- [37. 체형, 최초 설정, 편집과 설정 화면의 시각 구조](#snippet-37)
- [화면별로 더 살펴볼 파일](#supporting-notes)

<a id="snippet-30"></a>

## 30. 표지의 겹침과 가장자리 편집

원본: [ContentView.swift / cover의 제호](../../weashion/weashion/ContentView.swift#L474)

```swift
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
```

레이어 순서는 [cover](../../weashion/weashion/ContentView.swift#L464)의 `ZStack`과 `overlay`에서 확인합니다.

| 요소 | 화면에서 보이는 역할 |
| --- | --- |
| 날씨 배경 | 가장 뒤의 전체 색조와 국소 패럴랙스 |
| WEASHION 제호 | 마네킹 뒤에 놓인 96/164pt Bodoni. 몸을 가리는 전면 제목이 아님 |
| 마네킹 | 투명 렌더 표면의 중앙 피사체 |
| 좌상단 모노 카피 | 작은 사각형과 `YOUR BODY. / YOUR FIT.`. 왼쪽 진입 |
| 우측 세로 메타 | `PERSONAL FITTING / 001`, 크롭된 세로 러닝헤드 |
| 좌하단 사이즈 | 큰 버건디 글자, `SAMPLE / SIZE` 또는 `YOUR / SIZE`. 보간 교체와 측면 진입 |
| 우하단 메타 | 기온·상태·샘플 또는 지역·체형명. 160ms 지연 측면 진입 |
| 큰 글씨 대응 | 메타를 표지 아래 자연 높이 흐름으로 분리 |
| 표지 아래 조작 | 착장 슬롯, 상품·사이즈, 치수 버튼과 버건디 피팅 CTA |

같은 [today](../../weashion/weashion/ContentView.swift#L435)에서 조작형 표지 -> 사이즈 노트 -> 상세 날씨 순서를 조립합니다. 설계 문서의 옛 날씨 우선 순서를 현재 코드로 오해하지 않습니다.

<a id="snippet-31"></a>

## 31. 헤더, 하단 바, 사이즈와 착장 슬롯의 선택면

원본: [ContentView.swift / navigationBar의 선택 배경](../../weashion/weashion/ContentView.swift#L392)

```swift
.background {
    if selectedTab == item {
        RoundedRectangle(cornerRadius: 5)
            .fill(Editorial.accent)
            .matchedGeometryEffect(id: "selectedTab", in: tabIndicator)
    }
}
```

원본: [ContentView.swift / sizeLabel의 선택 배경](../../weashion/weashion/ContentView.swift#L1081)

```swift
.background {
    if selected {
        RoundedRectangle(cornerRadius: 3).fill(Editorial.accent)
            .matchedGeometryEffect(id: "fitting-size", in: sizeIndicator)
    }
}
.overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(selected ? .clear : Editorial.rule, lineWidth: 0.5))
.contentShape(Rectangle())
.animation(EditorialMotion.transition(reduceMotion: reduceMotion), value: selected)
```

| 영역 | 정적인 표현 | 변화 |
| --- | --- | --- |
| [러닝 헤더](../../weashion/weashion/ContentView.swift#L330) | 28pt BrandMark, 세로선, 현재 지면, 호수, 모노 날짜, 설정 아이콘 | 지면 문구의 opacity 교체, 하단 스윕 |
| [하단 내비게이션](../../weashion/weashion/ContentView.swift#L376) | Ink 면, Paper 글자, 작은 장 번호, 바깥 반경 9pt | 버건디 선택면의 matched geometry와 글자 굵기·명도 변화 |
| [상품·사이즈 레일](../../weashion/weashion/ContentView.swift#L896) | 상품명, 하향 chevron, 룰러 버튼, SIZE 메타 | 사이즈별 선택면 이동, 지원되지 않는 선택 비활성 |
| [착장 슬롯](../../weashion/weashion/ContentView.swift#L1032) | 상의·하의·신발·아우터의 2열 목록, 착장 개수와 제거 xmark | 포커스 슬롯의 Accent 8% 배경, 비포커스 Muted 4% |
| [사이즈 비교판](../../weashion/weashion/ContentView.swift#L953) | Stock 45%, 반경 3pt, 최소 높이 104pt | 이전 -> 현재 사이즈, 부호 있는 숫자 교체. 큰 글씨에서는 세로 값 목록 |
| [푸터](../../weashion/weashion/ContentView.swift#L416) | 이중선, 작은 WEASHION 제호, 저널 카피, 페이지 번호 | 기본 정적 |

`matchedGeometryEffect`는 같은 namespace의 선택 배경 관계를 연결합니다. 탭마다 화면 전체나 3D 표면을 복제하는 기능은 아닙니다.

<a id="snippet-33"></a>

## 33. 날씨 지면의 큰 숫자, 사진 같은 크롭과 겹친 제목

원본: [ContentView.swift / 하늘판 아래 선언문](../../weashion/weashion/ContentView.swift#L689)

```swift
EditorialTitle(text: weather.feelsLike < 20 ? L("가볍게\n겹쳐 입는 날.") : L("가볍게\n입는 하루."),
               pointSize: wide ? 72 : 50, style: .statement, revealsOnScroll: true)
    .padding(.top, -(wide ? 104 : 76))
    .padding(.trailing, wide ? 240 : 96)
```

| 요소 | 구도·수치 | 효과와 상태 |
| --- | --- | --- |
| 큰 기온 | 작은 창 132pt / 넓은 창 176pt에 `numeralScale` 적용 | 왼쪽에서 리빌, 숫자 교체 |
| 날씨·지역 | 한글 22pt와 작은 연결 상태 | 측정값과 샘플 날씨 구분 |
| 우측 좁은 단 | 체감·강수·바람, THE FORECAST, N° | 행마다 32pt 우측 리빌, 얇은 하단선 |
| 하늘판 | 폭 236/420pt, 높이 230/320pt | 우측 바깥 여백까지 bleed, 1.16배, ±16pt 패럴랙스, 72pt 우측 리빌 |
| 하늘판 주석 | FIG. 캡션과 버건디 강수 확률 | 실제 지역 또는 SAMPLE SKY |
| 선언문 | 하늘판 하단 모서리 위로 음수 padding으로 겹침 | 줄별 실제 노출 시 리빌 |
| 시간별 예보 | 가로 스크롤, 시간·SF Symbol·세리프 기온 | 시간별 데이터가 있을 때만, 세로 구분선 |
| 옷차림 크레딧 | 번호, 슬롯, 상품·샘플 문구, 얇은 행 구분선 | 40ms 범위의 순차 리빌, 실제 피팅 가능 항목만 동작 |
| 연결·오류·출처 | 밑줄 링크와 작은 진행 표시, 경고, 펼치는 오류 상세, Apple Weather 링크 | 요청 중 비활성, 샘플/최종 수신값 구분 |

연결 원본: [weatherSpread](../../weashion/weashion/ContentView.swift#L619), [weatherMetric](../../weashion/weashion/ContentView.swift#L765), [outfitList와 outfitRow](../../weashion/weashion/ContentView.swift#L786).

<a id="snippet-37"></a>

## 37. 체형, 최초 설정, 편집과 설정 화면의 시각 구조

원본: [BodyLibraryView.swift / 활성 체형 배지](../../weashion/weashion/Views/BodyLibraryView.swift#L107)

```swift
Label(active ? L("사용 중인 체형") : L("저장한 체형"),
      systemImage: active ? "checkmark.circle" : "person.crop.square")
    .editorialSans(.caption2, weight: .semibold)
    .foregroundStyle(active ? Editorial.paper : Editorial.muted)
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(active ? Editorial.accent : Editorial.stock, in: .rect(cornerRadius: 2))
```

| 화면 | 눈에 보이는 요소와 구도 | 원본 |
| --- | --- | --- |
| 피팅룸 | Fit study. 큰 영문 제목, SAME BODY / DIFFERENT SIZES, 스튜디오, 외부 조작바, 치수 비교판, Cut & measure., 계산 상세 | [fitting](../../weashion/weashion/ContentView.swift#L856) |
| 내 체형 | 실제 이름의 statement 제목, 큰 키·몸무게와 작은 단위, 몸 도식 대신 개인 3D, 번호가 붙은 치수 행, 출처와 수정 CTA | [bodyProfile](../../weashion/weashion/ContentView.swift#L1285) |
| 최초 체형 선택 전 | Ink 패널, You, first. 제목, Paper 선과 한글 카피, 세로 러닝헤드 | [BodySetupView.preview](../../weashion/weashion/Views/BodySetupView.swift#L158) |
| 최초 체형 선택 후 | 프레임을 두른 마네킹, 3단계 숫자·진행선, 기준 선택 버튼의 원/체크, 필드와 하단 CTA | [BodySetupView](../../weashion/weashion/Views/BodySetupView.swift#L27) |
| 체형 보관함 | 큰 저장 개수, 순번, 활성 행의 2pt 선, 버건디 배지와 선택 버튼, 이름·기준·날짜, 메뉴 | [BodyLibraryView](../../weashion/weashion/Views/BodyLibraryView.swift#L13) |
| 체형 편집 | 상단 작은 3D와 FIG. 캡션, plain List, 성별·체형·골격 세그먼트, 슬라이더, %, 접히는 세부 부위 | [BodyEditorView](../../weashion/weashion/Views/BodyEditorView.swift#L27) |
| 반팔/상의 치수 편집 | 지면 제목, 미리보기와 선 프레임, LIVE PREVIEW/직전 유효 값 안내, 도식, 샘플 버튼, 입력 밑줄과 단위, 고정 적용 영역 | [GarmentEditorView](../../weashion/weashion/Views/GarmentEditorView.swift#L55) |
| 바지·신발 치수 편집 | 큰 숫자 요약, 종류별 필드와 단위, 범위 오류, 샘플 버튼, 직전 유효 치수 미리보기 | [WearableMeasurementsEditor](../../weashion/weashion/Views/WearableMeasurementsEditor.swift#L181) |
| 상품 등록·수정 | 종류 -> 재질·두께 -> 날씨 제안의 순차 펼침, 선택 메뉴·세그먼트, 계절 선택면, 오류/저장 영역 | [ProductMetadataEditor](../../weashion/weashion/Views/ProductLibraryView.swift#L471) |
| 설정 | 섹션 번호, Language. 세그먼트, How to fit. 단계 번호, 가는 선과 화살표 행, DEBUG 날씨 미리보기 | [FittingSettingsView](../../weashion/weashion/Views/FittingSettingsView.swift#L11) |
| 브랜드 소개 | 어두운 하늘, 검정 하단 그라데이션, BrandMark, 150pt 흐린 페이지 숫자, SVG/반팔/룰러, 카피와 하단 3칸 진행선 | [EditorialWelcomeView](../../weashion/weashion/Views/EditorialWelcomeView.swift#L18) |
| 실행 화면 | 전체 이미지 scaledToFill, 화면 크기에 맞춘 크롭, 안전 영역 무시 | [LaunchSplashView](../../weashion/weashion/Views/LaunchSplashView.swift#L3) |

**최초 설정의 진행선:** [setup-step](../../weashion/weashion/Views/BodySetupView.swift#L46)은 세 단계의 가는 회색 선 위에 버건디 선택선을 matched geometry로 이동시킵니다. 단계 숫자는 numericText로 교체합니다.

**체형의 실제 시각 조절:** [shapeParameter와 partParameter](../../weashion/weashion/Views/BodyEditorView.swift#L200)의 슬라이더가 신체 데이터와 3D 실루엣을 바꿉니다. 이는 제목이나 배경을 움직이는 장식 효과와 다른 실제 형상 변경입니다.

<a id="supporting-notes"></a>

## 화면별로 더 살펴볼 파일

| 목적 | 파일 |
| --- | --- |
| 오늘, 피팅룸, 내 체형의 전체 조립 | [ContentView.swift](../../weashion/weashion/ContentView.swift) |
| 최초 체형 설정과 단계 진행 | [BodySetupView.swift](../../weashion/weashion/Views/BodySetupView.swift) |
| 체형 치수 편집 | [BodyEditorView.swift](../../weashion/weashion/Views/BodyEditorView.swift) |
| 체형 측정 안내와 도식 | [BodyMeasurementGuide.swift](../../weashion/weashion/Views/BodyMeasurementGuide.swift) |
| 저장 체형 보관함 | [BodyLibraryView.swift](../../weashion/weashion/Views/BodyLibraryView.swift) |
| 상품 보관함, 상세, 상품 메타데이터 편집 | [ProductLibraryView.swift](../../weashion/weashion/Views/ProductLibraryView.swift) |
| 사이즈 노트와 측정 도식 | [EditorialGarmentSpread.swift](../../weashion/weashion/Views/EditorialGarmentSpread.swift) |
| 반팔 치수 입력과 적용 | [GarmentEditorView.swift](../../weashion/weashion/Views/GarmentEditorView.swift) |
| 다른 의류 종류의 치수 편집 | [WearableMeasurementsEditor.swift](../../weashion/weashion/Views/WearableMeasurementsEditor.swift) |
| 언어, 사용 안내, 브랜드 소개 진입 | [FittingSettingsView.swift](../../weashion/weashion/Views/FittingSettingsView.swift) |

## 변경·검증 체크리스트

- 제호가 마네킹 뒤에 놓이는 등 ZStack과 overlay의 실제 레이어 순서를 유지합니다.
- 큰 글씨에서 표지 메타가 아래 자연 높이 흐름으로 분리되는지 확인합니다.
- 하단 내비게이션·상품·사이즈·착장 슬롯의 선택 상태가 실제 선택과 일치하는지 확인합니다.
- matchedGeometryEffect를 전체 화면이나 3D 표면을 복제하는 전환으로 취급하지 않습니다.
- 날씨의 실제 수신값·샘플·연결 중·오류·출처를 구분하고, 피팅 가능한 항목만 동작시키는 경계를 유지합니다.
- 체형·치수 미리보기에서 직전 유효 값과 현재 입력 오류의 관계를 확인합니다.
- 브랜드 소개는 설정의 이야기 화면이며, 최초 체형 설정 흐름과 혼동하지 않습니다.

## 함께 보는 문서

- [선, 프레임과 정적인 편집 그래픽](./editorial-graphics.md): 이중선, 스튜디오 워터마크·빛 면·타원, 상품 컷아웃과 아카이브 그래픽을 다룹니다.
- [날씨 배경과 대기 그래픽](./weather-graphics.md): 맑음·흐림·비·눈·어두운 배경의 팔레트와 해·구름·비·눈·하단 베일의 정적 레이어를 다룹니다.
- [반응형 배치, 간격과 표시 컨테이너](./layout.md): 폭·글씨 크기·콘텐츠 요구 크기에 따른 열 배치, 그리드, 여백과 sheet/inspector를 구분합니다.
- [버튼, 선택과 입력 컨트롤](./controls-and-input.md): CTA·선택 버튼·눌림·입력 포커스·오류 이동과 시스템 컨트롤의 외형·동작을 다룹니다.
