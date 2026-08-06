# MAP-LINE iOS

**이 제품의 기본은 앱입니다.** 웹도 그대로 유지하지만, 손으로 그리고 손으로 짚는
제품이라 원래 앱으로 만들려던 것이었습니다. 웹은 링크를 받은 사람이 아무것도 설치하지
않고 여는 자리로 남습니다.

안드로이드는 한참 뒤입니다. 지금은 iOS만 봅니다.

## 왜 네이티브인가

웹(JS SDK)에는 없는 것들이 여기에는 있습니다.

| | 웹 JS SDK | iOS SDK v2 |
|---|---|---|
| 화면좌표 → 위경도 | `coordsFromContainerPoint` | `getPosition(CGPoint)` |
| 위경도 → 화면좌표 | `containerPointFromCoords` | **공개 메서드 없음** |
| 지도 회전 | ❌ 없음, 계획도 없음 | ✅ |
| 도형 오버레이 | 직접 캔버스에 그림 | `ShapeManager`가 관리 |
| 꾹 누르기·핀 탭 | 직접 만들어야 함 | SDK 이벤트 또는 UIKit 인식기 |

역방향 변환이 없는 것은 문제가 아니라 **설계의 방향**입니다. 획을 `ShapeManager`에
등록하면 팬·줌·회전 시 재투영을 SDK가 전부 맡습니다. 웹에서는 캔버스를 손으로 따라
움직여야 했고, 확대 중에 선이 어긋나는 문제를 오래 겪었습니다. 여기서는 그 층이 없습니다.

제스처도 같습니다. 웹에서 직접 만든 꾹 누르기는 "터치만 해도 메뉴가 뜬다", "확대하고
손 떼면 메뉴가 뜬다", "지도가 블록 지정한 것처럼 파래진다" 같은 문제를 계속 냈습니다.
SDK의 롱프레스 이벤트는 시간을 바꿀 수 없어 앱은 `UILongPressGestureRecognizer`를
0.45초로 두고, 8pt 이상 움직이면 실패하게 합니다. SDK 팬·줌과는 동시 인식시키고 최종
위경도는 여전히 `getPosition(CGPoint)`으로 구합니다.

## 지금 되는 것

| 기능 | 파일 |
|---|---|
| 손그림 (위경도 고정, RDP 단순화) | `Map/DrawingOverlayView.swift`, `Domain/GeoStroke.swift` |
| 꾹 눌러 주변 장소·건물명 찾기 또는 이름 검색 → 새 단계/기존 단계 후보로 담기 | `Course/DropPinSheet.swift`, `Shared/PlaceLookup.swift`(`NearbyLookup`) |
| 번호 붙은 단계 핀, 복수검색·단계 선택·후보 일괄 추가, 대표 지정·삭제 | `Course/CoursePlacePickerSheet.swift`, `Course/CourseSheet.swift`, `Course/StopPinSheet.swift`, `Domain/MapDocument.swift` |
| 구간 이동수단(직선/도보/대중교통/자전거)과 실제 경로 | `Course/CourseSheet.swift`, `Domain/StopLeg.swift`, `Domain/RouteLookup.swift`, `Domain/LegShapes.swift`, `Map/LegStyle.swift` |
| 지도 위 메모 작성·수정·롱프레스 드래그 이동·삭제 | `Map/KakaoMapViewController.swift`, `Course/DropPinSheet.swift`, `Course/MemoSheet.swift`, `Domain/MapDocument.swift`(`MapLabel`) |
| 저장·불러오기·공유 링크 | `Domain/MapStore.swift`, `Course/MyMapsView.swift`, `Course/ActivitySheet.swift` |
| 보관함 폴더·마크·직접 장소 추가·공유 수신 | `Course/SavedPlacesView.swift`, `Shared/SavedPlaceGroup.swift`, `Shared/SavedPlaceStore.swift` |
| 중간지점 찾기 + 기록 + 지도 표시 | `Midpoint/MidpointView.swift`, `Shared/MidpointHistory.swift`, `Map/MidpointPlot.swift` |
| 공유 익스텐션 (다른 앱 → 보관함) | `ShareExtension/` |

**웹 기능은 전부 옮겨졌습니다.** 웹에만 있고 앱에 없는 기능은 현재 없습니다
(반대로 손그림은 앱에만 있습니다).

지도 오른쪽의 `장소 추가`는 웹 검색 패널과 같은 동선 전용 흐름입니다. 검색 결과를 여러
곳 체크하고 `새 단계` 또는 기존 `N단계`를 고른 뒤 하단 버튼으로 한 번에 담습니다.
동선 화면의 `이 단계에 후보 추가`도 같은 시트를 해당 단계가 선택된 상태로 엽니다.
지도에서 새 장소를 꾹 눌러 `핀 찍기`를 선택해도, 이미 단계가 있으면 `새 단계 만들기`와
각 `N단계에 후보로 추가` 중 하나를 고릅니다. 첫 장소만 선택 단계를 생략하고 바로
1단계가 됩니다.
핀 컨텍스트의 주변 장소와 단계 선택 행은 글자·아이콘뿐 아니라 행의 빈 여백까지 전체가
터치 영역입니다. 저장된 핀 상세의 대표 지정·삭제 행도 같은 규칙을 씁니다.
단계 핀은 20pt, 장소 이름표는 16pt입니다.

지도 메모는 메모 글자를 0.45초간 누른 뒤 그대로 끌면 손가락을 따라 움직이고, 손을 떼는
순간 새 좌표로 확정됩니다. 드래그 중에는 지도가 움직이지 않습니다. 메모 편집 화면의
`위치 옮기기`는 드래그가 어려운 경우를 위한 보조 경로로 남겨 두었습니다.

중간지점 찾기는 사이드 메뉴에만 둡니다. 지도 오른쪽의 떠 있는 버튼은 자주 쓰는
`장소 추가`·`동선 만들기`·`공유`만 남겨 같은 기능이 두 곳에 반복되지 않게 했습니다.

보관함은 공유 수신함이 아니라 개인 장소 라이브러리입니다. `받은 장소` 기본 폴더 외에
사용자가 폴더를 만들고 8종 마크와 7종 색을 정할 수 있습니다. 폴더 안에서 장소를 직접
검색해 넣거나 기존 장소를 다른 폴더로 옮기고, 동선 단계로 올리면 폴더 색이 핀 색으로
이어집니다. 예전 `saved-places.json`에는 폴더 키가 없으므로 읽을 때 자동으로 `받은 장소`에
넣습니다. 폴더를 삭제해도 장소 자체는 지우지 않고 `받은 장소`로 이동합니다.

중간지점은 참가자마다 정한 도보·대중교통·자전거를 후보 검색과 최종 실제 경로 시간에
모두 반영합니다. 결과 1·2·3순위를 여러 개 체크해 지도에 함께 올릴 수 있고, 지도 선도
직선이 아니라 `/api/midpoint`가 반환한 실제 경로 좌표를 그립니다. 대중교통 탈것 사이와
출발·도착의 좌표 없는 구간은 기존 동선과 같은 도보 점선으로 잇습니다.
검색이 끝나면 참가자·이동수단·후보·경로를 기기에 자동 저장합니다. 상단 기록 버튼에서
최근 20건을 다시 열거나 개별 삭제할 수 있습니다. 실제 경로 좌표가 커질 수 있어
UserDefaults가 아니라 Application Support의 JSON 파일에 보관합니다.

공유 익스텐션은 주소 줄을 기준으로 최대 10개 장소를 나눠 받습니다. 담을 보관함 폴더를
고르고 장소별 후보 하나를 고른 뒤 하단 버튼으로 한꺼번에 담습니다. 서버는 정확한 주소 검색 결과를 먼저
주고 장소명 검색 결과를 뒤에 보완합니다. Share Extension의 Web URL 활성화 상한도 10개입니다.

## 구조

```
ios/
  project.yml              XcodeGen 설정. .xcodeproj는 여기서 생성한다
  MapLine/
    MapLineApp.swift       SDK 초기화, 앱 키 읽기
    ContentView.swift      지도가 곧 첫 화면. 떠 있는 버튼 + 사이드 메뉴
    Map/
      KakaoMapView.swift            SwiftUI ↔ UIKit 다리
      KakaoMapViewController.swift  엔진 생명주기, 모든 그리기
      DrawingOverlayView.swift      손가락 입력, 긋는 중인 획 미리보기
      MidpointPlot.swift            중간지점을 지도에 얹을 형태 (순수)
      LegStyle.swift                이동수단별 선 모양 + 점선 자르기 (순수)
      UIColor+Hex.swift
    Domain/                SDK를 import하지 않는 순수 규칙
      GeoStroke.swift      RDP 단순화
      MapDocument.swift    Stop / MapPlace / MapLabel / MapDocument
      StopLeg.swift        TravelMode / RoutePath / LegRules
      LegShapes.swift      구간을 어떻게 그릴지 (대중교통 구간 자르기)
      MapStore.swift       /api/maps 클라이언트, 편집 토큰, 내 지도 목록
      RouteLookup.swift    /api/route 클라이언트
    Course/                단계·구간·보관함·내 지도 화면
    Midpoint/              중간지점 화면
  Shared/                  앱과 공유 익스텐션이 함께 쓰는 것
    AppConfig / PlaceLookup / SavedPlace / SavedPlaceStore / ShareIntake / Midpoint
  ShareExtension/
  MapLineTests/            시뮬레이터 없이도 도는 도메인 테스트
  MapLineUITests/          시뮬레이터를 띄워 화면을 찍는 테스트
```

### 어디에 무엇을 두는가

- **`Domain/`은 SDK를 import하지 않습니다.** 나중에 안드로이드를 붙일 때 이 규칙만
  옮기면 되고, 무엇보다 시뮬레이터 없이 검증할 수 있습니다. 맥이 없는 환경에서 이건
  선택이 아니라 생존 조건입니다.
- **`Shared/`는 공유 익스텐션에도 컴파일됩니다.** 여기에 앱 전용 타입을 참조하는
  코드를 넣으면 익스텐션 빌드가 깨집니다. 실제로 `RouteLookup`을 여기 뒀다가
  `Domain/`으로 옮겼습니다.
- **그리기는 전부 `KakaoMapViewController`에 있습니다.** 레이어를 용도별로 나눠 두었고
  (`strokes` / `stopPins` / `stopLegs` / `midpointPins` / `midpointLinks` / `memos`),
  한쪽을 지울 때 다른 쪽이 같이 사라지지 않게 하려는 것입니다.
- **웹과 같은 값을 내야 하는 규칙은 웹 파일을 명시해 뒀습니다.** `lib/map/types.ts`,
  `lib/map/legs.ts`, `lib/render/sceneGeometry.ts`가 짝입니다. 한쪽만 고치면 같은
  지도가 두 곳에서 다르게 그려집니다.

## 빌드와 검증 — 맥이 없다

**개발 환경이 윈도우라 맥이 없습니다. GitHub Actions의 macOS 러너가 사실상 유일한
컴파일러입니다.** 저장소가 public이라 러너는 무료입니다.

```
push → .github/workflows/ios.yml
  빌드 → 앱 키가 번들에 들어갔는지 확인 → 도메인 테스트 → UI 테스트 → 스크린샷 아티팩트
```

그래서 작업 방식이 보통과 다릅니다.

1. **컴파일 한 번이 약 10분입니다.** 추측으로 고쳐서 밀어 넣지 말고, SDK 시그니처를
   먼저 확인하고 한 번에 맞히세요(아래 참고).
2. **눈으로 볼 방법은 UI 테스트 스크린샷뿐입니다.** 새 화면·새 그림을 만들면
   `MapLineUITests`에 그 흐름을 걸어가는 테스트를 함께 넣으세요. 안 넣으면 그게
   화면에 어떻게 나오는지 아무도 모릅니다.

중간지점 UI 테스트는 1·2순위를 함께 고른 화면과 실제 경로가 지도에 함께 올라간 화면을
찍습니다. 공유 익스텐션 화면은 일반 앱 UI 테스트 타깃에서 직접 실행하지 못하므로 응답
그룹 디코딩과 빈 Kakao ID 대체 식별자는 `ShareIntakeTests`에서 검증하고, 최종 화면은
실기기 공유 시트에서 확인해야 합니다.

```bash
gh run list --workflow=ios.yml --limit 1
gh run view <id> --json status,conclusion
gh run download <id> -n ui-screenshots -D shots   # screenshots/manifest.json에 이름↔파일 대응
```

3. **그림만으로 원인을 못 좁히면 숫자를 화면 밖으로 내보내세요.** `renderLegs`가
   `view.accessibilityValue`에 `legs:1 segs:1 conns:2 perPt:...`를 걸어 두고 UI
   테스트가 그걸 첨부합니다. 디버거를 붙일 수 없으니 이게 디버거 대신입니다.
   실제로 "선이 핀에 안 닿는다"를 두 번 잘못 고친 뒤 이걸로 원인을 확정했습니다.

맥이 있다면 로컬에서도 됩니다.

```bash
brew install xcodegen
cd ios && xcodegen generate && open MapLine.xcodeproj
```

## TestFlight

`.github/workflows/testflight.yml`을 수동 실행(`workflow_dispatch`)하면 아카이브해서
업로드합니다. **EAS 같은 유료 빌드 서비스는 필요 없습니다** — Apple 개발자 프로그램
연회비 외에 추가 비용이 없습니다.

저장소 시크릿 3개가 필요합니다.

| 시크릿 | 어디서 |
|---|---|
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect > 사용자 및 액세스 > 통합 > 키 |
| `APP_STORE_CONNECT_ISSUER_ID` | 같은 화면 상단 |
| `APP_STORE_CONNECT_PRIVATE_KEY` | 키 생성 시 받은 `AuthKey_*.p8` 전문 |

`KAKAO_NATIVE_APP_KEY`도 시크릿으로 들어가 있어야 지도 타일이 뜹니다.

진단이 필요하면 추측하지 말고 이 스크립트들이 상태 코드를 그대로 보여 줍니다.

```bash
python3 scripts/apple_key_check.py <key_id> <issuer_id> <p8_path>   # 무엇이 막혔는지
python3 scripts/apple_team_id.py  <key_id> <issuer_id> <p8_path>    # 팀 ID
```

## SDK 시그니처를 확인하는 법

맥이 없으면 자동완성도 헤더 점프도 없습니다. 문서에도 생성자 인자까지는 안 나옵니다.
추측하지 말고 **SDK 바이너리에서 직접 읽으세요.** SPM 저장소에 xcframework가 통째로
들어 있습니다.

```bash
BASE="https://raw.githubusercontent.com/kakao-mapsSDK/KakaoMapsSDK-SPM/2.12.17/BinaryFramework/KakaoMapsSDK.xcframework/ios-arm64/KakaoMapsSDK.framework"

# Swift API 전체 (클래스, 메서드, 생성자 시그니처)
curl -sL "$BASE/Modules/KakaoMapsSDK.swiftmodule/arm64-apple-ios.swiftinterface" -o /tmp/k.si

# 열거형 (CompetitionType, PoiTextLayout, GestureType 등)
curl -sL "$BASE/Headers/ApiEnums.h" -o /tmp/ae.h

# 구조체
curl -sL "$BASE/Headers/ApiStructs.h"
```

`.swiftinterface`에 안 보이는 `@objc` 열거형은 `ApiEnums.h`에 있습니다
(`CompetitionTypeNone` → Swift에서는 `.none`).

## 밟은 함정 — 다시 겪지 마세요

**`PolylineShape`과 `MapPolylineShape`은 다릅니다.**
`PolylineShape`은 기준점 대비 모델 좌표(CGPoint)라 지도를 옮기면 따라오지 않습니다.
위경도로 이루어진 선은 `Map`이 붙은 쪽입니다. 잘못 고르면 컴파일은 되는데 그림이
지도에 안 붙습니다. `Polygon`/`MapPolygon`도 같은 짝입니다.

**폴리라인에 점선 기능이 없습니다.** `PerLevelPolylineStyle`에는 색과 굵기뿐입니다.
그래서 `LegStyle.swift`의 `dashedSegments`가 선을 짧은 조각으로 잘라 도형 하나에
담습니다. 조각 길이는 `angularEpsilon(map:pixels:1)`로 구한 "1pt에 해당하는 각도"를
곱해 정하므로 어느 줌에서 봐도 같은 간격으로 보이고, 카메라가 멈출 때 다시 자릅니다.

**점선은 반드시 그린 조각으로 끝나야 합니다.** 빈칸 차례에 길이 끝나면 선이 끝점에
닿지 않아 "핀 앞에서 끊긴" 것처럼 보입니다. 길이와 간격이 어떻게 나누어떨어지느냐에
따라 어떤 구간은 닿고 어떤 구간은 안 닿아서, 기하 버그로 착각하기 쉽습니다.

**카카오 길찾기는 요청한 좌표가 아니라 가장 가까운 도로 노드에서 시작하고 끝납니다.**
실측으로 25m 떨어진 곳에서 끝났습니다. 그 간격을 잇는 것이 `LegShapes`의
`connectors`입니다. "핀에 가리는 짧은 건 그리지 말자"며 최소 길이를 20m쯤 두었더니
정확히 그 구간이 잘려 나갔습니다. 지금은 길이 0짜리만 거릅니다.

**대중교통 응답은 탈것 구간의 좌표만 줍니다.** 1,682m 중 882m가 도보인데 좌표로 오는
것은 지하철 800m뿐인 경우가 있었습니다. 그대로 그리면 선이 역에서 시작해 역에서 끝나
핀 어디에도 닿지 않습니다. `TransitLeg.pointCount`로 되잘라 그 사이를 도보 점선으로
잇습니다. 웹에서 겪고 고친 것과 같은 문제입니다.

**SwiftUI `ZStack`은 가장 큰 자식에 맞춰 커집니다.** 지도가 안전 영역을 넘어가면
ZStack도 넘어가고 그 안의 버튼이 상태바 시계와 겹칩니다. 지도는 `.background`로
두세요. 그리고 **앱 루트(`MapLineApp`)에서 `.ignoresSafeArea()`를 걸면 아래에서
무엇을 해도 되돌릴 수 없습니다** — 이걸로 두 번 헛고쳤습니다.

**지도 오른쪽 아래에는 카카오 로고가 박혀 있습니다.** 그 위에 버튼을 얹으면 가려지는데
SDK 이용약관이 로고 노출을 요구합니다.

**`.none`은 `Optional.none`으로도 읽힙니다.** `CompetitionType.none`처럼 타입을
적으세요.

**SwiftUI `List` 안의 `Button`은 내용 전체를 강조색으로 물들입니다.** `NavigationLink`나
`.buttonStyle(.plain)`을 쓰세요.

**`State`라는 이름의 열거형을 만들지 마세요.** `@State`와 겹쳐 컴파일이 이상하게 깨집니다.
`Phase`를 씁니다.

**iOS 16이 최소 버전입니다.** `navigationDestination(item:)`은 17부터라 못 씁니다.

**CI 워크플로에서 `continue-on-error: true`를 쓰지 마세요.** 진짜 실패를 초록으로
덮습니다. 실제로 UI 테스트 두 개가 깨졌는데 통과로 나왔습니다.

**서명 설정이 새어 나갑니다.** 시뮬레이터 CI용 `CODE_SIGNING_ALLOWED=NO`를
`project.yml`에 박아 두면 배포 아카이브까지 따라가 "No Team Found in Archive"가 됩니다.
명령줄에서만 끄세요. 반대로 `CODE_SIGN_IDENTITY` 같은 걸 명령줄로 넘기면 SPM 패키지
타깃에까지 적용돼 "requires a development team"으로 죽습니다. 아카이브는 설정 없이
하고 export 단계가 배포용으로 다시 서명합니다.

**수출 규정 준수 답변은 Info.plist에 박아 둡니다** (`ITSAppUsesNonExemptEncryption`).
없으면 올라간 빌드가 "규정 준수 누락"에 걸려 테스터에게 안 갑니다. 다만 **이미 올라간
빌드에는 소급되지 않아** 그 빌드는 App Store Connect에서 한 번 답해 줘야 합니다.

**아이콘·시각물은 올리기 전에 사용자에게 보여 주고 확인받으세요.** 한 번 자체 판단으로
올렸다가 지적받았습니다.
