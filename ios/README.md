# MAP-LINE iOS (스파이크)

에디터를 네이티브로 옮기기 전에, **이것 하나만** 확인하려고 만든 앱입니다.

> 손가락으로 그은 선이 위경도에 고정되어, 지도를 옮기고 확대해도 제자리에 남는가.

이게 되면 이 코드가 곧 앱의 뼈대가 됩니다. 안 되면 스택을 다시 논의합니다.

## 왜 네이티브인가

웹(JS SDK)에는 없는 것들이 여기에는 있습니다.

| | 웹 JS SDK | iOS SDK v2 |
|---|---|---|
| 화면좌표 → 위경도 | `coordsFromContainerPoint` | `getPosition(CGPoint)` |
| 위경도 → 화면좌표 | `containerPointFromCoords` | **공개 메서드 없음** |
| 지도 회전 | ❌ 없음, 계획도 없음 | ✅ |
| 도형 오버레이 | 직접 캔버스에 그림 | `ShapeManager`가 관리 |

역방향 변환이 없는 것은 문제가 아니라 **설계의 방향**입니다. 획을 `ShapeManager`에
등록하면 팬·줌·회전 시 재투영을 SDK가 전부 맡습니다. 웹에서는 캔버스를 손으로 따라
움직여야 했고, 확대 중에 선이 어긋나는 문제를 오래 겪었습니다. 여기서는 그 층이
아예 없습니다.

## 구조

```
ios/
  project.yml              XcodeGen 설정. .xcodeproj는 여기서 생성한다
  MapLine/
    MapLineApp.swift       SDK 초기화, 앱 키 읽기
    ContentView.swift      지도 + "그리기" 토글
    Map/
      KakaoMapView.swift            SwiftUI ↔ UIKit 다리
      KakaoMapViewController.swift  엔진 생명주기, 획을 Shape로 등록
      DrawingOverlayView.swift      손가락 입력, 긋는 중인 획 미리보기
    Domain/
      GeoStroke.swift      SDK를 부르지 않는 순수 규칙 (RDP 단순화)
  MapLineTests/            시뮬레이터 없이도 도는 도메인 테스트
```

`Domain/`은 SDK를 import하지 않습니다. 나중에 안드로이드를 붙일 때 이 규칙만 옮기면
되고, 웹의 `lib/geo/rdp.ts`와 같은 알고리즘을 씁니다. **같은 획이 웹과 앱에서 다르게
보이면 안 됩니다.**

## 빌드

맥이 없어 GitHub Actions의 macOS 러너에서 빌드합니다 (`.github/workflows/ios.yml`).
이 저장소가 public이라 러너는 무료입니다.

맥이 있다면 로컬에서도 됩니다.

```bash
brew install xcodegen
cd ios && xcodegen generate && open MapLine.xcodeproj
```

## 시작 전에 필요한 것

1. **번들 ID** — 지금은 `com.mapline.editor`로 두었습니다. `project.yml`의
   `PRODUCT_BUNDLE_IDENTIFIER`만 바꾸면 됩니다
2. **카카오 콘솔에 iOS 플랫폼 등록** — 그 번들 ID로. 등록 전에는 빌드는 되지만
   지도 타일이 뜨지 않고 `addViewFailed`가 호출됩니다
3. **네이티브 앱 키** — 저장소의 Settings > Secrets에 `KAKAO_NATIVE_APP_KEY`로
   넣습니다. 코드에 하드코딩하지 않습니다. JS 키가 아니라 **네이티브 앱 키**입니다

## 아직 확인하지 못한 것

이 코드는 윈도우에서 작성됐고 **한 번도 컴파일되지 않았습니다.** CI가 첫 컴파일러입니다.
특히 아래는 문서만 보고 쓴 부분이라 이름이 틀렸을 수 있습니다.

- `import KakaoMapsSDK` — SPM 제품명은 `KakaoMapsSDK-SPM`인데 모듈명은 다를 수 있음
- `PolylineStyle` / `PerLevelPolylineStyle` / `PolylineShapeOptions`의 정확한 시그니처
- `setGestureEnable(type:enable:)`의 열거형 이름
- `MapPoint.wgsCoord`의 프로퍼티명

CI 로그를 보고 맞춰 나갑니다.
