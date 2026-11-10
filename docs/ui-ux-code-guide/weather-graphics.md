# 날씨 배경과 대기 그래픽

[전체 목차](./README.md) · [이전: 화면별 구도, 내비게이션과 선택면](./screen-composition.md) · [다음: 의류와 신체의 측정 도식](./measurement-diagrams.md)

> 기준: 2026-11-02 원문 가이드의 작업 트리 설명을 종류별로 재분류했습니다. 코드 블록은 실제 소스 발췌이며 독립 실행 예제가 아닙니다. 실제 연결·조건부 표시·보유·미구현의 구분은 그대로 유지합니다.

날씨를 분위기로 전달하는 그라데이션과 Canvas 그림을 다룹니다. 비·눈은 index로 좌표가 정해지는 정적 그림이며, 시간 기반 날씨 입자가 아닙니다. 배경의 동적인 이동은 호출부 패럴랙스이고, 수치·출처·시간별 예보의 지면 구성은 [33](./screen-composition.md#snippet-33)에 있습니다.

## 요소 분류와 책임

| 레이어 | 모양·조건 | 표현상의 의미 |
| --- | --- | --- |
| 하늘 | 날씨별 2~3색 세로 그라데이션 | 화면 전체의 색조 |
| 해 | 맑음의 작은 원과 블러 | 태양 위치를 나타내는 장식, 실측 천체 위치 아님 |
| 구름 | 8개 타원, 날씨별 크기·블러·불투명도 | 대기감과 깊이 |
| 비 | 70개 가는 사선 | 정적 좌표의 빗줄기 |
| 눈 | 26개 원, 일부 블러 | 정적 눈송이 크기·깊이 차이 |
| 하단 베일 | 높이 32%의 대비 그라데이션 | 아래쪽 문자와 지면 연결 |
| 어두운 변형·역상 | 소개의 dark 팔레트, 비 오는 표지 글자색 | 날씨 종류와 별도의 표시 조건도 존재 |

## 문서 내 상세 항목

- [20. 날씨별 시각 디자인](#snippet-20)
- [32. 날씨 배경을 구성하는 모든 그래픽 레이어](#snippet-32)

<a id="snippet-20"></a>

## 20. 날씨별 시각 디자인

원본: [WeatherBackdrop.swift / sky](../../weashion/weashion/Views/WeatherBackdrop.swift#L12)

```swift
private var sky: [Color] {
    if dark { return [Color(red: 0.08, green: 0.17, blue: 0.21), Color(red: 0.31, green: 0.40, blue: 0.42)] }
    switch mood {
    case .clear: return [Color(red: 0.60, green: 0.75, blue: 0.87), Color(red: 0.84, green: 0.89, blue: 0.91), Editorial.paper]
    case .cloud: return [Color(red: 0.76, green: 0.79, blue: 0.80), Color(red: 0.89, green: 0.90, blue: 0.89), Editorial.paper]
    case .rain: return [Color(red: 0.15, green: 0.20, blue: 0.24), Color(red: 0.34, green: 0.40, blue: 0.44), Editorial.paper]
    case .snow: return [Color(red: 0.90, green: 0.92, blue: 0.93), Color(red: 0.96, green: 0.96, blue: 0.95), Editorial.paper]
    }
}
```

- **화면 효과:** 맑음, 흐림, 비, 눈에 따라 배경 그라데이션을 바꿉니다. `dark`는 소개 화면 등에 사용하는 별도 어두운 팔레트입니다.
- **추가 표현:** 같은 뷰의 `Canvas`가 구름, 빗줄기, 눈송이를 그립니다.
- **주의:** 이 파일 자체의 비와 눈은 시간에 따라 움직이는 파티클 구현이 아닙니다. 배경의 스크롤 움직임은 [10](./motion.md#snippet-10)의 호출부가 담당합니다.
- **연결:** 비 오는 표지의 글자색 반전은 [prefersInvertedCover](../../weashion/weashion/Views/WeatherBackdrop.swift#L3)와 [ContentView의 coverInk](../../weashion/weashion/ContentView.swift#L38)에서 연결됩니다.

<a id="snippet-32"></a>

## 32. 날씨 배경을 구성하는 모든 그래픽 레이어

원본: [WeatherBackdrop.swift / 태양](../../weashion/weashion/Views/WeatherBackdrop.swift#L38)

```swift
Circle()
    .fill(Color(red: 1, green: 0.95, blue: 0.80).opacity(dark ? 0.3 : 0.8))
    .frame(width: geometry.size.width * 0.17)
    .blur(radius: 2)
    .position(x: geometry.size.width * 0.76, y: geometry.size.height * 0.2)
```

원본: [WeatherBackdrop.swift / 빗줄기 Canvas](../../weashion/weashion/Views/WeatherBackdrop.swift#L57)

```swift
Canvas { context, size in
    for index in 0..<70 {
        let x = CGFloat((index * 37) % 101) / 101 * size.width
        let y = CGFloat((index * 61) % 103) / 103 * size.height * 0.8
        var line = Path()
        line.move(to: CGPoint(x: x, y: y))
        line.addLine(to: CGPoint(x: x - 3, y: y + 22))
        context.stroke(line, with: .color(Editorial.paper.opacity(0.28)), lineWidth: 0.6)
    }
}
```

원본: [WeatherBackdrop.swift / 눈송이 Canvas](../../weashion/weashion/Views/WeatherBackdrop.swift#L70)

```swift
Canvas { context, size in
    for index in 0..<26 {
        let x = CGFloat((index * 53) % 97) / 97 * size.width
        let y = CGFloat((index * 29) % 89) / 89 * size.height * 0.85
        let diameter = CGFloat(4 + (index * 7) % 6)
        var flake = context
        if index % 3 == 0 { flake.addFilter(.blur(radius: 1.5)) }
        flake.fill(Path(ellipseIn: CGRect(x: x, y: y, width: diameter, height: diameter)),
                   with: .color(.white.opacity(0.92)))
    }
}
```

| 레이어 | 구성 | 표시 조건 |
| --- | --- | --- |
| 하늘 | 위에서 아래로 이어지는 2~3색 LinearGradient | 모든 날씨, dark이면 별도 2색 |
| 태양 | 너비의 17%인 작은 원, 따뜻한 흰색, 2pt 블러 | 맑음만 |
| 구름 | 8개 타원. 흐림은 폭·높이를 키우고 블러 24pt, 그 외 17pt | 모든 날씨. 조건에 따라 opacity 다름 |
| 구름 투명도 | 맑음 0.22, 흐림 0.34, 비 0.07, 눈 0.4, dark 0.08 | `cloudOpacity` |
| 비 | 70개 사선, 길이 22pt, 좌측 기울기 3pt, 두께 0.6pt | 비 |
| 눈 | 26개 원, 지름 4~9pt, 일부 1.5pt 블러 | 눈 |
| 하단 베일 | 전체 높이의 32%, 투명에서 Paper 또는 검정 60%로 이어지는 그라데이션 | 모든 날씨 |

**정적 효과:** 좌표는 index 기반으로 결정됩니다. 타이머나 파티클 물리로 움직이는 비·눈이 아니며, 동적인 움직임은 호출부 패럴랙스와 전환에서 생깁니다.

## 변경·검증 체크리스트

- 날씨별 sky 색과 dark 분기의 우선순위를 확인합니다.
- 배경 팔레트 변경 시 표지의 coverInk 역상 연결도 함께 확인합니다.
- 구름·눈·비의 개수·크기·불투명도가 실제 코드와 일치하는지 확인합니다.
- 비와 눈을 움직이는 파티클이나 실시간 기상 시뮬레이션으로 설명하지 않습니다.
- 스크롤 패럴랙스는 [10](./motion.md#snippet-10)과 [33](./screen-composition.md#snippet-33)의 호출부에서 확인하고 마네킹·조작부까지 함께 움직이지 않게 합니다.
- 날씨 배경만으로 실제 위치·예보 연결 성공을 암시하지 않고 화면의 샘플·출처 문구와 함께 확인합니다.

## 함께 보는 문서

- [색상, 배경면과 대비](./colors-and-surfaces.md): 종이색·잉크색·버건디 토큰과 상태색, 역상, 호출부별 불투명도를 구분합니다.
- [모션, 등장과 화면 전환](./motion.md): 모션 토큰, 스크롤 리빌, 제목 등장, 글자 교체, 스윕·패럴랙스와 소개·실행 전환을 모았습니다.
- [화면별 구도, 내비게이션과 선택면](./screen-composition.md): 표지·날씨 지면·피팅룸·체형·편집·소개 화면의 배치와 헤더·내비게이션·선택면을 연결합니다.
- [저장 피드백, 오류와 진행 상태](./feedback-and-loading.md): 실제 저장 결과, 오류 alert, 늦은 화면 준비 예고와 계산 중 진행선·블러·오버레이를 구분합니다.
