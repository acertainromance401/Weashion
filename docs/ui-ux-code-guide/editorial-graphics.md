# 선, 프레임과 정적인 편집 그래픽

[전체 목차](./README.md) · [이전: 타이포그래피, 캡션과 현지화](./typography.md) · [다음: 모션, 등장과 화면 전환](./motion.md)

> 기준: 2026-11-02 원문 가이드의 작업 트리 설명을 종류별로 재분류했습니다. 코드 블록은 실제 소스 발췌이며 독립 실행 예제가 아닙니다. 실제 연결·조건부 표시·보유·미구현의 구분은 그대로 유지합니다.

정적인 선·면·도형이 지면을 구획하고 피사체를 강조하는 방식을 모았습니다. 일부 선에는 등장 애니메이션이 있지만, 그래픽의 형태와 움직임의 책임은 구분합니다. 여기의 도식·타원·회전은 실제 상품 사진이나 3D 계산 결과를 뜻하지 않습니다.

## 요소 분류와 책임

| 그래픽 종류 | 형태와 효과 | 구현 경계 |
| --- | --- | --- |
| 이중 구분선 | 1pt 본선과 0.5pt 보조선, 3pt 간격 | 선택적으로 선 리빌. 모든 Rectangle 선이 공통 컴포넌트는 아님 |
| 스튜디오 워터마크 | 큰 W의 크롭과 낮은 불투명도 | 피사체 뒤의 2D 장식 |
| 빛 면·바닥 타원 | 우측 그라데이션과 블러 타원 | 실제 조명이나 모델 접촉 그림자가 아님 |
| 모서리 프레임 | 가는 L자와 좌상단 버건디 강조 | 시각 경계이지 별도 터치 컨트롤이 아님 |
| 상품 컷아웃 | 정규화 Path, 고정 회전, 큰 번호와 여백 | 상품 실측 비율·사진을 보장하지 않음 |
| 아카이브 선택 | 선택 라벨, 체크, 사이즈 노트의 밝고 어두운 면 | 선택 상태와 상품·사이즈 정보의 대응 유지 |

## 문서 내 상세 항목

- [27. 이중 구분선의 형태와 그려지는 효과](#snippet-27)
- [29. 스튜디오의 W, 빛 면, 바닥 그림자와 모서리 표시](#snippet-29)
- [34. 상품 아카이브와 설명용 의류 컷아웃](#snippet-34)

<a id="snippet-27"></a>

## 27. 이중 구분선의 형태와 그려지는 효과

원본: [EditorialStyle.swift / EditorialRule](../../weashion/weashion/Views/EditorialStyle.swift#L398)

```swift
struct EditorialRule: View {
    var animates = false
    var double = true
    var color = Editorial.ink
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    var body: some View {
        VStack(spacing: 3) {
            Rectangle().fill(color).frame(height: 1)
            if double { Rectangle().fill(color.opacity(0.25)).frame(height: 0.5) }
        }
        .scaleEffect(x: animates && !reduceMotion && !drawn ? 0 : 1, y: 1, anchor: .leading)
        .onAppear {
            guard animates else { return }
            withAnimation(reduceMotion ? nil : EditorialMotion.editorial(EditorialMotion.ruleDuration).delay(0.2)) {
                drawn = true
            }
        }
        .accessibilityHidden(true)
    }
}
```

- **정적인 역할:** 잡지의 섹션 경계처럼 진한 선과 가는 보조선을 겹칩니다.
- **동적인 역할:** `animates`인 경우 200ms 지연 후 500ms 동안 왼쪽에서 길어집니다.
- **범위:** 제목·섹션 시작·푸터에서 사용합니다. 모든 `Rectangle` 구분선이 이 컴포넌트인 것은 아닙니다.

<a id="snippet-29"></a>

## 29. 스튜디오의 W, 빛 면, 바닥 그림자와 모서리 표시

원본: [EditorialStyle.swift / EditorialStudioBackdrop의 문자와 타원](../../weashion/weashion/Views/EditorialStyle.swift#L619)

```swift
Text(mark)
    .font(Editorial.serif(min(geometry.size.width * 0.95, 420), italic: true))
    .foregroundStyle(Editorial.ink.opacity(0.045))
    .offset(x: -geometry.size.width * 0.12, y: -geometry.size.height * 0.14)
VStack {
    Spacer()
    Ellipse()
        .fill(Editorial.ink.opacity(0.05))
        .frame(width: geometry.size.width * 0.55, height: 18)
        .blur(radius: 12)
        .padding(.bottom, 18)
}
.frame(maxWidth: .infinity)
```

원본: [EditorialStyle.swift / 모서리의 버건디 강조](../../weashion/weashion/Views/EditorialStyle.swift#L645)

```swift
var accent = Path()
accent.move(to: CGPoint(x: 16, y: 30))
accent.addLine(to: CGPoint(x: 16, y: 16))
accent.addLine(to: CGPoint(x: 44, y: 16))
context.stroke(accent, with: .color(Editorial.accent), lineWidth: 2)
```

| 레이어 | 모양과 역할 |
| --- | --- |
| 바탕 | Studio 단색 |
| 빛 면 | 오른쪽 40% 폭에 Paper 70%에서 투명으로 내려가는 그라데이션 |
| 대형 W | 최대 420pt, Ink 4.5%로 크롭된 워터마크 |
| 바닥 타원 | 너비 55%, 높이 18pt, Ink 5%, 블러 12pt의 **2D 장식 그림자** |
| 네 모서리 | 여백 16pt, 길이 14pt의 가는 L자 표시 |
| 좌상단 강조 | 2pt 버건디 꺾인 선 |
| 마감 | 바깥 클리핑, 터치 비활성, 접근성 장식 제외 |

이 타원은 3D 모델에서 계산한 접촉 그림자나 실제 조명의 그림자가 아닙니다. [WEASHIONSceneView의 배경 분기](../../weashion/weashion/Views/WEASHIONSceneView.swift#L589)는 표지에서는 투명, 피팅 지면에서는 이 스튜디오를 사용합니다.

<a id="snippet-34"></a>

## 34. 상품 아카이브와 설명용 의류 컷아웃

원본: [EditorialStyle.swift / GarmentIllustration의 음영과 봉제선](../../weashion/weashion/Views/EditorialStyle.swift#L934)

```swift
shirt.fill(LinearGradient(colors: [
    tint.opacity(0.65), tint
], startPoint: .topLeading, endPoint: .bottomTrailing))
shirt.stroke(Editorial.ink.opacity(0.35), lineWidth: 0.8)
Path { path in
    path.move(to: CGPoint(x: w * 0.35, y: h * 0.12))
    path.addQuadCurve(to: CGPoint(x: w * 0.65, y: h * 0.12),
                      control: CGPoint(x: w * 0.5, y: h * 0.36))
    path.move(to: CGPoint(x: w * 0.29, y: h * 0.87))
    path.addLine(to: CGPoint(x: w * 0.71, y: h * 0.87))
}
.stroke(.white.opacity(0.3), lineWidth: 1)
```

| 컴포넌트 | 시각적 구성 | 구현 |
| --- | --- | --- |
| `GarmentIllustration` | 정규화 좌표의 반팔 Path, 목 곡선, 사선 그라데이션, 외곽선과 목·밑단의 밝은 선 | [반팔 그림](../../weashion/weashion/Views/EditorialStyle.swift#L914) |
| `EditorialGarmentArtwork` | Studio 바탕, 우측 36% Paper 면, 큰 번호 6% opacity, 여백 속 의류, 고정 -7도 회전 | [상품 지면](../../weashion/weashion/Views/EditorialGarmentSpread.swift#L310) |
| `WearableSilhouette` | 바지·반바지의 밑단 높이, 신발, 니트, 그 외 상의의 다각형 실루엣 | [Shape](../../weashion/weashion/Views/EditorialGarmentSpread.swift#L355) |
| 선택 라벨 | Paper 바탕 위 버건디 checkmark와 '선택됨', 좌하단 | [아트워크 선택 표시](../../weashion/weashion/Views/EditorialGarmentSpread.swift#L339) |
| 상품 타일 | 200pt 아트워크, 실제 상품명, 종류·사이즈 수, 외부 이동 화살표 | [productTile](../../weashion/weashion/Views/ProductLibraryView.swift#L84) |
| 상품 상세 | 240pt 아트워크, 기후 요약, 원본 링크, 사이즈 행, 펼치는 비교표 | [ProductDetailView](../../weashion/weashion/Views/ProductLibraryView.swift#L185) |
| 사이즈 노트 | Ink 배경, Paper 글자, 큰 사이즈와 작은 치수, 우측 세로 러닝헤드 | [EditorialSizeSpread](../../weashion/weashion/Views/EditorialGarmentSpread.swift#L166) |
| 사이즈 선택선 | Paper 18%의 얇은 선 위에 1.5pt 선택선의 matched geometry, 체크와 문구 교체 | [sizeNote](../../weashion/weashion/Views/EditorialGarmentSpread.swift#L280) |

회전은 컷아웃을 비스듬히 배치하는 정적인 디자인입니다. 도식의 크기를 사이즈마다 임의 확대해서 실제 상품 차이처럼 보여주는 구현은 아닙니다.

## 변경·검증 체크리스트

- 장식선의 두께와 실제 버튼·입력의 터치 영역을 혼동하지 않습니다.
- 스튜디오 장식은 터치와 접근성 탐색에서 제외된 상태를 유지합니다.
- W와 큰 번호의 낮은 불투명도, 컷아웃의 크롭이 피사체나 상품명을 가리지 않는지 확인합니다.
- 타원 그림자를 실제 3D 그림자로, 설명용 의류 Path를 정확한 상품 형상으로 설명하지 않습니다.
- 사이즈마다 그림을 임의 확대해 실제 상품 치수 차이처럼 오인시키지 않습니다.
- 구분선 리빌 변경은 [04](./motion.md#snippet-04)의 공통 시간값과 Reduce Motion 분기도 확인합니다.

## 함께 보는 문서

- [타이포그래피, 캡션과 현지화](./typography.md): 서체의 역할, 한글 폴백, 크기 대응, 제목·캡션·세로 조판과 다국어 문구를 다룹니다.
- [모션, 등장과 화면 전환](./motion.md): 모션 토큰, 스크롤 리빌, 제목 등장, 글자 교체, 스윕·패럴랙스와 소개·실행 전환을 모았습니다.
- [의류와 신체의 측정 도식](./measurement-diagrams.md): 의류 치수의 번호·강조선·값과 신체 앞/옆 실루엣·실선·점선·측정 강조를 구분합니다.
- [화면별 구도, 내비게이션과 선택면](./screen-composition.md): 표지·날씨 지면·피팅룸·체형·편집·소개 화면의 배치와 헤더·내비게이션·선택면을 연결합니다.
