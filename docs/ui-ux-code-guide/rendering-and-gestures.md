# 3D 형상, 렌더링과 시점 조작

[전체 목차](./README.md) · [이전: 의류와 신체의 측정 도식](./measurement-diagrams.md) · [다음: 이미지 자산, 폰트 파일과 아이콘](./assets-and-icons.md)

> 기준: 2026-11-02 원문 가이드의 작업 트리 설명을 종류별로 재분류했습니다. 코드 블록은 실제 소스 발췌이며 독립 실행 예제가 아닙니다. 실제 연결·조건부 표시·보유·미구현의 구분은 그대로 유지합니다.

실제 3D 출력을 2D 편집 장식과 분리해 설명합니다. 화면 표면은 UIKit 호스트의 SCNView이며, RealityKit Entity의 형상·변환·지원 재질 속성을 SceneKit으로 동기화합니다. 사용자 시점 조작과 입력에 따른 형상 변경은 장식 애니메이션과 다른 책임입니다.

## 요소 분류와 책임

| 책임 | 실제 구현·시각 결과 | 보장하지 않는 것 |
| --- | --- | --- |
| 렌더 표면 | 투명 SCNView, 4X MSAA | SwiftUI RealityView 직접 출력이라고 설명하지 않음 |
| 형상·재질 브리지 | Entity 변환·mesh·색·float roughness/metallic 전달 | 원단 텍스처·normal map 자동 복원 아님 |
| 시점 | 원근 카메라, Y축 회전, 핀치 중심 보정 줌 | 화면 전체의 2D 전환과 별개 |
| 광원·바닥 | 방향광·보조광·환경광, 조건부 3D 바닥 | shadow 설정만으로 실제 출력 그림자 보장 불가 |
| 몸·의류 표면 | 법선·평활화·안팎 표면·마감 형상 | 실물 원단 조직·촉감의 정확한 재현 아님 |
| 모델 리소스 | 신체 메시와 의류 정의·치수·외관 | 파일만으로 고정된 최종 형상이 아님 |
| 제스처 | 가로 pan 회전, pinch 확대 | 세로 페이지 스크롤과 구분 |

## 문서 내 상세 항목

- [19. 마네킹 회전과 페이지 스크롤의 제스처 구분](#snippet-19)
- [40. 실제 렌더 표면과 SceneKit 재질 연결](#snippet-40)
- [41. 카메라, 회전·확대, 조명과 바닥](#snippet-41)
- [42. 마네킹과 의류의 재질, 음영, 안팎 표면](#snippet-42)
- [43. 실제 실루엣과 외관을 결정하는 모델 리소스](#snippet-43)
- [UI 모션과 3D 계산의 경계](#supporting-notes)

<a id="snippet-19"></a>

## 19. 마네킹 회전과 페이지 스크롤의 제스처 구분

원본: [WEASHIONSceneView.swift / MannequinInteractionView.Coordinator](../../weashion/weashion/Views/WEASHIONSceneView.swift#L1010)

```swift
func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
    let velocity = pan.velocity(in: pan.view)
    return abs(velocity.x) > abs(velocity.y)
}

@objc func rotate(_ recognizer: UIPanGestureRecognizer) {
    guard recognizer.state == .began || recognizer.state == .changed || recognizer.state == .ended else { return }
    parent.onRotate(recognizer.translation(in: recognizer.view).x)
    recognizer.setTranslation(.zero, in: recognizer.view)
}

@objc func zoom(_ recognizer: UIPinchGestureRecognizer) {
    guard recognizer.state == .began || recognizer.state == .changed || recognizer.state == .ended,
          let view = recognizer.view else { return }
    parent.onZoom(recognizer.scale, recognizer.location(in: view), view.bounds.size)
    recognizer.scale = 1
}
```

- **역할:** 가로 속도가 세로 속도보다 큰 pan만 마네킹 회전으로 시작해 세로 페이지 스크롤과의 충돌을 줄입니다.
- **확대:** pinch의 배율과 손가락 위치를 부모에 전달하고 배율을 1로 재설정해 다음 변화량을 받습니다.
- **기술 경계:** SwiftUI에 UIKit 제스처를 연결하는 부분입니다. UI 장식 애니메이션이나 의류 물리 계산 자체는 아닙니다.

<a id="snippet-40"></a>

## 40. 실제 렌더 표면과 SceneKit 재질 연결

원본: [WEASHIONSceneView.swift / MannequinSceneSurface 초기화](../../weashion/weashion/Views/WEASHIONSceneView.swift#L69)

```swift
override init(frame: CGRect, options: [String: Any]? = nil) {
    super.init(frame: frame, options: options)
    isOpaque = false
    backgroundColor = .clear
    antialiasingMode = .multisampling4X
}
```

원본: [WEASHIONSceneView.swift / RealityKit 재질에서 SceneKit으로 전달](../../weashion/weashion/Views/WEASHIONSceneView.swift#L127)

```swift
let material = SCNMaterial()
material.lightingModel = .physicallyBased
if model.materials.indices.contains(part.materialIndex),
   let source = model.materials[part.materialIndex] as? SimpleMaterial {
    material.diffuse.contents = source.color.tint
    if case .float(let roughness) = source.roughness {
        material.roughness.contents = roughness
    }
    if case .float(let metallic) = source.metallic {
        material.metalness.contents = metallic
    }
}
geometry.materials = [material]
```

- **실제 표면:** `MannequinRenderView`는 UIKit 호스트에 `MannequinSceneSurface: SCNView`를 붙입니다. 실제 화면 출력을 SwiftUI `RealityView`라고 부르면 부정확합니다.
- **형상 소스:** RealityKit Entity의 변환, mesh와 재질을 SceneKit 노드로 동기화합니다.
- **시각 효과:** 투명 바탕은 뒤의 날씨/스튜디오를 드러내고, 4X MSAA는 윤곽의 계단 현상을 줄입니다. 재질은 physicallyBased 모델입니다.
- **형상 재사용:** mesh가 달라졌을 때 geometry를 다시 만들고, 노드의 변환·활성 상태도 전달합니다.
- **경계:** 이 경로에서 전달하는 것은 색, float roughness, float metallic입니다. 원단 이미지 텍스처나 normal map을 자동으로 복원하는 코드가 아닙니다.

<a id="snippet-41"></a>

## 41. 카메라, 회전·확대, 조명과 바닥

원본: [WEASHIONSceneView.swift / updateViewpoint](../../weashion/weashion/Views/WEASHIONSceneView.swift#L878)

```swift
private func updateViewpoint() {
    let pose = viewpoint.wrappedValue
    displayRoot.orientation = simd_quatf(angle: pose.rotation, axis: [0, 1, 0])
    let target = pose.focus + SIMD3<Float>(0, Float(bodyData.height) / 200, 0)
    camera.look(
        at: target,
        from: target + cameraOffset / pose.zoom,
        relativeTo: nil
    )
}
```

| 요소 | 실제 코드의 시각 설정 |
| --- | --- |
| 카메라 | 원근 카메라, FOV 38도, 기준 오프셋 `(0, 0.06, 3.25)` |
| 대상 높이 | 신체 높이의 중간 근처에 focus를 더해 바라봄 |
| 회전 | 몸과 의류를 포함한 displayRoot를 Y축으로 회전 |
| 확대 | 줌 범위 0.75~3. 핀치 위치를 기준으로 focus를 보정 |
| SceneKit 카메라 | near 0.01, far 100, HDR 사용, 자동 노출 적응 끔 |
| 방향광 | RealityKit 설정 intensity 1000, 위치 `(-3, 4, 3)`, 목표 `(0, 0.9, 0)` |
| 보조광 | PointLight intensity 150, 위치 `(2, 1.8, 2)` |
| 브리지 광량 | SceneKit directional은 원본 ×0.225, omni는 ×0.15 |
| 기본 환경광 | SceneKit ambient intensity 25 |
| 3D 바닥 | 10×8 평면, y=-0.002, 비 관련 조건은 흰색도 0.16, 그 외 0.25 |
| 바닥 표시 경로 | `!isEditorial`에서만 장면에 추가. 에디토리얼 지면은 [29](./editorial-graphics.md#snippet-29)의 2D 배경 사용 |
| 조작바 | 16pt light 아이콘과 44pt 버튼, 좌측 구분선, 회전·확대·축소·초기화 |

원본 연결: [카메라·조명 생성](../../weashion/weashion/Views/WEASHIONSceneView.swift#L704), [카메라·광원 브리지](../../weashion/weashion/Views/WEASHIONSceneView.swift#L145), [makeGround](../../weashion/weashion/Views/WEASHIONSceneView.swift#L924), [viewControls](../../weashion/weashion/Views/WEASHIONSceneView.swift#L842).

**그림자 주의:** RealityKit 방향광에 shadow 설정은 존재하지만, 현재 SceneKit 동기화 부분에서 광원의 shadow 속성을 그대로 복사하는 코드는 확인되지 않습니다. 따라서 설정 한 줄만으로 실제 출력에 동적 그림자가 보장된다고 설명하지 않습니다. [29](./editorial-graphics.md#snippet-29)의 흐린 타원과도 구분합니다.

<a id="snippet-42"></a>

## 42. 마네킹과 의류의 재질, 음영, 안팎 표면

원본: [WEASHIONMannequin.swift / 기본 마네킹 재질](../../weashion/weashion/Views/WEASHIONMannequin.swift#L34)

```swift
private static let material = SimpleMaterial(color: UIColor(white: 0.84, alpha: 1), roughness: 0.48, isMetallic: false)
```

원본: [GarmentRenderer.swift / 의류 재질](../../weashion/weashion/Views/GarmentRenderer.swift#L76)

```swift
func material(_ color: SIMD3<Float>) -> SimpleMaterial {
    SimpleMaterial(
        color: UIColor(red: CGFloat(color.x), green: CGFloat(color.y), blue: CGFloat(color.z), alpha: 1),
        roughness: .init(floatLiteral: appearance.roughness),
        isMetallic: false
    )
}
```

원본: [GarmentRenderer.swift / 얇은 안팎 표면 생성](../../weashion/weashion/Views/GarmentRenderer.swift#L264)

```swift
let outer = vertices.indices.map { vertices[$0] + normals[$0] * 0.0004 }
let inner = vertices.indices.map { vertices[$0] - normals[$0] * 0.0004 }
descriptor.positions = MeshBuffers.Positions(outer + inner)
descriptor.normals = MeshBuffers.Normals(normals + normals.map { -$0 })
var doubleSided = indices
let offset = UInt32(vertices.count)
for triangle in stride(from: 0, to: indices.count, by: 3) {
    doubleSided.append(contentsOf: [indices[triangle] + offset, indices[triangle + 2] + offset, indices[triangle + 1] + offset])
}
descriptor.primitives = .triangles(doubleSided)
```

| 시각 요소 | 구현과 의미 |
| --- | --- |
| 마네킹 바탕 | 밝은 회색 0.84, roughness 0.48, 비금속 |
| 몸의 음영 | [BodySurfaceMesh.prepared](../../weashion/weashion/Views/BodySurfaceMesh.swift#L8)가 삼각형 법선을 합산·정규화. 기본 형상과 조명에 따라 음영 생성 |
| 의류 바탕·마감 | `appearance.color`, `trimColor`, `roughness`가 표면과 바인딩 부분의 외관을 결정 |
| 마감 형상 | trim loop를 따라 binding과 일부 ribbon을 생성. 단순 2D 테두리가 아닌 별도 3D 형상 |
| 안팎 표면 | 법선 방향 ±0.0004m의 두 표면과 뒤집은 삼각형. 안쪽이 뚫려 보이는 현상을 줄이는 구조 |
| 표면 평활화 | [GarmentSurface.smoothed](../../weashion/weashion/Views/GarmentRenderer.swift#L119)가 표시 형상을 다듬음 |
| 신발 높이 | [setFootwearElevation](../../weashion/weashion/Views/WEASHIONMannequin.swift#L57)이 몸 root 높이에 반영 |

겉색과 roughness가 있다는 이유로 실제 코튼·니트 조직, 광택, 촉감이나 원단 물성을 정확히 재현한다고 해석하지 않습니다.

<a id="snippet-43"></a>

## 43. 실제 실루엣과 외관을 결정하는 모델 리소스

근거: [garments.json](../../weashion/weashion/Resources/garments.json), [GarmentAppearance](../../weashion/weashion/Models/GarmentDefinition.swift#L173), [신체 리소스 로더](../../weashion/weashion/Models/MannequinMesh.swift#L53).

아래 RGB는 0~1 값이며 같은 모델의 S/M/L은 현재 같은 외관 설정을 공유합니다.

| 의류 | 바탕 RGB | 마감 RGB | Roughness | 메시 |
| --- | --- | --- | --- | --- |
| 코튼 반팔 | 0.44, 0.46, 0.45 | 0.40, 0.42, 0.41 | 0.94 | [meshy_cotton_tshirt.json](../../weashion/weashion/Resources/meshy_cotton_tshirt.json) |
| 긴팔 | 0.62, 0.65, 0.66 | 0.54, 0.57, 0.58 | 0.94 | [meshy_long_sleeve.json](../../weashion/weashion/Resources/meshy_long_sleeve.json) |
| 후디 | 0.34, 0.40, 0.37 | 0.29, 0.35, 0.32 | 0.96 | [meshy_hoodie.json](../../weashion/weashion/Resources/meshy_hoodie.json) |
| 슬랙스 | 0.20, 0.22, 0.24 | 0.17, 0.19, 0.21 | 0.90 | [meshy_dress_pants.json](../../weashion/weashion/Resources/meshy_dress_pants.json) |
| 청바지 | 0.19, 0.28, 0.40 | 0.16, 0.23, 0.34 | 0.95 | [meshy_jeans.json](../../weashion/weashion/Resources/meshy_jeans.json) |
| 봄버 | 0.24, 0.26, 0.25 | 0.20, 0.22, 0.21 | 0.85 | [meshy_bomber.json](../../weashion/weashion/Resources/meshy_bomber.json) |
| 스니커즈 | 0.72, 0.73, 0.71 | 0.63, 0.64, 0.62 | 0.88 | [meshy_sneakers.json](../../weashion/weashion/Resources/meshy_sneakers.json) |

| 신체 리소스 | 시각적 역할 |
| --- | --- |
| [male_body_40k.json](../../weashion/weashion/Resources/male_body_40k.json) | 남성 기본형의 정점·삼각형·영역·해부학 데이터 |
| [female_body_40k.json](../../weashion/weashion/Resources/female_body_40k.json) | 여성 기본형의 별도 표면 데이터 |
| [female_body_frame_presets.json](../../weashion/weashion/Resources/female_body_frame_presets.json) | 여성 골격 실루엣의 변형 프리셋 |

형상은 파일만으로 고정되지 않습니다. 입력 치수·체형 프리셋·세부 부위 조절과 의류 피팅 계산을 적용한 결과가 보입니다. 구체적인 연결은 [46](./validation-and-inventory.md#snippet-46)에 정리합니다.

<a id="supporting-notes"></a>

## UI 모션과 3D 계산의 경계

[GarmentDraper.swift](../../weashion/weashion/Services/GarmentDraper.swift)는 의류 배치, 드레이핑 계산과 캐시를 담당합니다. 버튼 눌림이나 제목 리빌을 바꾸기 위해 이 파일의 계산 로직을 수정할 필요는 없습니다.

반대로 UI가 버벅인다는 이유만으로 모든 원인을 애니메이션 시간값으로 판단해서도 안 됩니다. 2D 모션, 화면 준비 상태, 3D 렌더 표면과 계산 작업은 구분해서 살펴봐야 합니다.

## 변경·검증 체크리스트

- UI 장식 변경인지 카메라·재질 변경인지 실제 신체·의류 계산 변경인지 먼저 구분합니다.
- SceneKit 브리지가 전달하는 속성과 전달하지 않는 속성을 구분합니다.
- 투명 배경, 4X MSAA, 카메라·광원 설정을 실제 렌더 표면 기준으로 확인합니다.
- 가로 pan과 세로 스크롤의 충돌, 확대 범위 0.75~3과 초기화를 확인합니다.
- 2D 타원과 실제 3D 바닥·광원의 그림자를 같은 효과로 설명하지 않습니다.
- 얇은 안팎 표면과 마감 형상이 정상적으로 보이는지, 새 재질이 현재 브리지로 전달되는지 확인합니다.
- 성능 문제는 2D 모션·준비 상태·렌더 표면·형상 계산으로 나누고 시간 상수만으로 단정하지 않습니다.
- 실제 화면 품질·동적 그림자·FPS·발열은 코드 설정만으로 보장하지 않습니다.

## 함께 보는 문서

- [저장 피드백, 오류와 진행 상태](./feedback-and-loading.md): 실제 저장 결과, 오류 alert, 늦은 화면 준비 예고와 계산 중 진행선·블러·오버레이를 구분합니다.
- [선, 프레임과 정적인 편집 그래픽](./editorial-graphics.md): 이중선, 스튜디오 워터마크·빛 면·타원, 상품 컷아웃과 아카이브 그래픽을 다룹니다.
- [의류와 신체의 측정 도식](./measurement-diagrams.md): 의류 치수의 번호·강조선·값과 신체 앞/옆 실루엣·실선·점선·측정 강조를 구분합니다.
- [검증, 전체 인벤토리와 구현 경계](./validation-and-inventory.md): 경계값 테스트, 전체 시각 타입·효과·형상 생성 경로와 미구현·미확인 요소를 한곳에서 찾습니다.
