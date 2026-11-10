# 의류와 신체의 측정 도식

[전체 목차](./README.md) · [이전: 날씨 배경과 대기 그래픽](./weather-graphics.md) · [다음: 3D 형상, 렌더링과 시점 조작](./rendering-and-gestures.md)

> 기준: 2026-11-02 원문 가이드의 작업 트리 설명을 종류별로 재분류했습니다. 코드 블록은 실제 소스 발췌이며 독립 실행 예제가 아닙니다. 실제 연결·조건부 표시·보유·미구현의 구분은 그대로 유지합니다.

도식은 실제 값의 의미와 측정 위치를 설명하는 장치입니다. 개인 3D의 캡처나 실제 상품 메시 투영이 아닙니다. 의류 도식의 선택은 번호·선·설명을 함께 바꾸며, 신체 도식은 실측 항목과 시각 조절 항목을 서로 다르게 표현합니다.

## 요소 분류와 책임

| 도식 요소 | 시각적 부호 | 연결·한계 |
| --- | --- | --- |
| 의류 윤곽 | 설명용 반팔 그림 | 실제 상품 비율을 보장하지 않음 |
| 치수선·눈금 | 총장·어깨·가슴단면·소매 위치 | 선택선 2pt, 비선택선 0.8pt |
| 번호와 설명 | 1~4 번호, 큰 값과 작은 cm | 같은 focus Binding, 별도 44×44pt 터치 영역 |
| 치수 숫자 | 고정폭 세리프 숫자와 numericText | 값 변화와 도식 선택을 구분 |
| 신체 실루엣 | 앞·옆·뒷모습 설명, 머리와 몸 윤곽 | 정규화 Path, 개인 몸 렌더가 아님 |
| 둘레·측정 위치 | 앞 실선과 뒤 점선, 길이선 | 실측 3pt와 시각 조절 6pt 구분 |
| 비교 안내 | 상의·하의 선택과 비교표 | 신체 치수와 의류 단면 치수의 의미 구분 |

## 문서 내 상세 항목

- [35. 의류 치수 도식의 번호, 강조선과 숫자](#snippet-35)
- [36. 신체 측정 안내의 실루엣, 실선과 점선](#snippet-36)

<a id="snippet-35"></a>

## 35. 의류 치수 도식의 번호, 강조선과 숫자

원본: [EditorialGarmentSpread.swift / 선택된 치수선](../../weashion/weashion/Views/EditorialGarmentSpread.swift#L89)

```swift
let selected = focus.wrappedValue?.rawValue == index + 1
context.stroke(path, with: .color(selected ? Editorial.accent : Editorial.ink),
               lineWidth: selected ? 2 : 0.8)
```

원본: [EditorialGarmentSpread.swift / 치수 숫자의 교체](../../weashion/weashion/Views/EditorialGarmentSpread.swift#L145)

```swift
Text("\(value, specifier: "%.1f")")
    .font(Editorial.serif(48 * min(scale, 1.3))).monospacedDigit()
    .contentTransition(.numericText(value: value))
    .animation(EditorialMotion.transition(reduceMotion: reduceMotion), value: value)
Text("cm").font(Editorial.serif(13, italic: true)).foregroundStyle(Editorial.muted)
```

- **도식:** 반팔 그림 위에 총장, 어깨너비, 가슴단면, 소매길이의 선과 양끝 눈금을 Canvas로 그립니다.
- **번호:** 1~4의 작은 버건디 번호와 선택 배경을 배치합니다. 표시 번호와 별도로 44×44pt 투명 버튼을 두어 터치 영역을 확보합니다.
- **쌍방 연결:** 도식 번호와 치수 설명의 버튼이 같은 `focus` Binding을 바꿉니다. 선택한 선과 설명이 함께 강조됩니다.
- **숫자:** 큰 세리프 숫자, 작은 cm, 고정폭 숫자와 numericText 전환을 사용합니다.
- **배치:** 가로에 들어가면 도식+설명, 부족하면 세로. 설명 값은 일반 글씨 2열, 접근성 글씨 1열입니다.
- **경계:** 설명용 도식이며 실제 상품 비율이나 3D 메시를 투영한 그림이 아닙니다.

전체 원본: [GarmentMeasurementPlate](../../weashion/weashion/Views/EditorialGarmentSpread.swift#L26). 반팔 이외의 숫자 요약은 [WearableMeasurementSummary](../../weashion/weashion/Views/WearableMeasurementsEditor.swift#L77)를 사용합니다.

<a id="snippet-36"></a>

## 36. 신체 측정 안내의 실루엣, 실선과 점선

원본: [BodyMeasurementGuide.swift / 실루엣과 머리 윤곽](../../weashion/weashion/Views/BodyMeasurementGuide.swift#L233)

```swift
let transform = CGAffineTransform(scaleX: size.width, y: size.height)
let outline = silhouette(sideView: sideView).applying(transform)
context.fill(outline, with: .color(.secondary.opacity(0.13)))
context.stroke(outline, with: .color(.secondary.opacity(0.65)), lineWidth: 1.5)
let head = Path(ellipseIn: CGRect(x: sideView ? 0.44 : 0.42, y: 0.02, width: 0.16, height: 0.13))
    .applying(transform)
context.fill(head, with: .color(.secondary.opacity(0.13)))
context.stroke(head, with: .color(.secondary.opacity(0.65)), lineWidth: 1.5)
```

원본: [BodyMeasurementGuide.swift / 측정선 스타일](../../weashion/weashion/Views/BodyMeasurementGuide.swift#L292)

```swift
context.stroke(hidden.applying(transform), with: .color(.accentColor.opacity(0.55)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
context.stroke(tape.applying(transform), with: .color(.accentColor), style: StrokeStyle(lineWidth: measurement.isPhysical ? 3 : 6, lineCap: .round))
```

| 대상 | 표시되는 그림 |
| --- | --- |
| 키 | 머리와 발끝 기준의 세로 치수선, 연장 보조선 |
| 어깨너비 | 뒷모습 설명과 수평 치수선 |
| 가슴·허리·엉덩이 | 앞·옆 실루엣, 둘레 위치의 앞 실선과 뒤 점선 |
| 안쪽 다리 길이 | 가랑이 기준에서 바닥으로 내려가는 치수선 |
| 팔·다리 굵기 | 해당 부위를 따라가는 굵은 강조선 |
| 체중 | 실루엣 대신 64pt `scalemass` 시스템 아이콘 |
| 의류/신체 비교 | 상의·하의 세그먼트와 2열 비교표, 설명 문구 |

- **크기:** 각 패널의 Canvas는 110×210pt입니다. 정규화 Path를 패널 크기로 변환합니다.
- **의미:** 실측 항목은 3pt, 시각 조절은 6pt로 구분합니다. 신체 그림은 개인 마네킹의 실제 렌더 캡처가 아닙니다.
- **연결:** [BodyMeasurementGuideSheet](../../weashion/weashion/Views/BodyMeasurementGuide.swift#L89), 내부 `BodyMeasurementDiagram`, [ClothingMeasurementComparisonSheet](../../weashion/weashion/Views/BodyMeasurementGuide.swift#L355).

## 변경·검증 체크리스트

- 도식 번호와 설명 버튼이 동일한 focus를 바꾸고 같은 치수선을 강조하는지 확인합니다.
- 보이는 작은 번호와 독립적인 44×44pt 조작 영역을 유지합니다.
- cm 단위·소수 자리·고정폭 숫자와 선택 상태를 확인합니다.
- 가로 도식+설명 배치와 큰 글씨의 세로·한 열 흐름을 함께 확인합니다.
- 신체 둘레의 숨겨진 뒤쪽 점선과 앞쪽 실선이 의미를 잃지 않는지 확인합니다.
- 설명용 실루엣을 개인 몸이나 실제 의류 형상으로 오인시키지 않습니다.
- 치수 편집과 실제 형상 계산의 연결을 바꾸는 경우에는 [46](./validation-and-inventory.md#snippet-46)의 별도 경로를 확인합니다.

## 함께 보는 문서

- [선, 프레임과 정적인 편집 그래픽](./editorial-graphics.md): 이중선, 스튜디오 워터마크·빛 면·타원, 상품 컷아웃과 아카이브 그래픽을 다룹니다.
- [버튼, 선택과 입력 컨트롤](./controls-and-input.md): CTA·선택 버튼·눌림·입력 포커스·오류 이동과 시스템 컨트롤의 외형·동작을 다룹니다.
- [반응형 배치, 간격과 표시 컨테이너](./layout.md): 폭·글씨 크기·콘텐츠 요구 크기에 따른 열 배치, 그리드, 여백과 sheet/inspector를 구분합니다.
- [3D 형상, 렌더링과 시점 조작](./rendering-and-gestures.md): SceneKit 출력과 RealityKit 형상·재질 연결, 카메라·조명·몸·의류 외관과 회전·확대를 다룹니다.
