# Spatium (iOS)

**방을 스캔하고, 3D 공간에 가구를 배치하고, 사진 한 장으로 3D 가구를 만드는 공간 인테리어 앱**

LiDAR로 실제 방을 스캔해 3D 공간으로 만들고, 그 안에서 가구를 자유롭게 배치·편집하며 인테리어를 시뮬레이션합니다. 가구는 기본 카탈로그뿐 아니라 사진으로 직접 생성한 3D 모델도 사용할 수 있습니다.

| | |
|---|---|
| **플랫폼** | iOS 17.0+ (iPhone / iPad) |
| **언어 / UI** | Swift 5.0 · SwiftUI |
| **3D** | SceneKit · [GLTFKit2](https://github.com/warrenm/GLTFKit2) 0.5.15 |
| **방 스캔** | Apple RoomPlan (LiDAR) |
| **번들 ID** | `name.dongharyu.Spatium` |
| **버전** | 1.0 (build 1) |

---

## ✨ 주요 기능

- 📷 **방 스캔** — RoomPlan(LiDAR)으로 방을 스캔해 USDZ + 메타데이터로 저장
- 🪑 **3D 룸 에디터** — 가구 배치/이동/편집, undo·redo, 1인칭 시점, 임시 저장, 접근성(VoiceOver·큰 글씨) 대응
- 🖼️ **사진 → 3D 가구 생성** — 가구 사진을 3D 모델로 변환해 내 가구로 추가
- 📁 **프로젝트/룸 관리** — 프로젝트·룸 생성·이름 변경·삭제, 당겨서 새로고침
- 🔐 **인증** — 이메일 로그인 + Google·Apple 소셜 로그인 + 게스트 모드
- 👋 **온보딩** — 첫 실행 시 기능 소개

---

## 📱 화면 구성

하단 5개 탭으로 구성됩니다.

| 탭 | 설명 |
|----|------|
| 홈 | 대시보드 — 프로젝트 요약, 빠른 진입 |
| 프로젝트 | 프로젝트/룸 목록 및 상세, 내 가구 |
| 스캔 | RoomPlan 캡처 → 리뷰 → 업로드 |
| 가구 만들기 | 사진 → 3D 가구 생성 |
| 설정 | 프로필 편집, 로그아웃, 약관 |

첫 실행: **온보딩 → 로그인/게스트 게이트 → 메인 탭** 순으로 진입합니다.

---

## 🚀 시작하기

### 요구 사항
- Xcode 15 이상
- iOS 17.0 이상 (방 스캔은 **LiDAR 탑재 기기** 필요)
- Swift Package는 Xcode가 자동으로 해결합니다 (GLTFKit2)

### 빌드 & 실행
```bash
git clone https://github.com/dongha0312/Spatium
cd Spatium   # (이 앱은 spatium-ios 디렉터리)
open Spatium.xcodeproj
```
Xcode에서 **Spatium** 스킴을 선택하고 실기기/시뮬레이터로 실행합니다.

> ⚠️ RoomPlan 방 스캔은 시뮬레이터에서 동작하지 않습니다. LiDAR가 있는 실기기에서 테스트하세요.

명령줄 빌드:
```bash
xcodebuild -project Spatium.xcodeproj -scheme Spatium -configuration Debug build
```

---

## ⚙️ 서버 설정

앱은 3개의 백엔드 서버를 사용합니다. (`Core/Networking/SpatiumAPIEnvironment.swift`)

| 용도 | 기본 주소 |
|------|-----------|
| API 서버 | `http://210.119.12.115:8080` |
| Image-to-3D 서버 | `http://210.119.12.115:8000` |
| 가구 에셋 서버 | `http://210.119.12.115:3000` |

- **Debug** 빌드에서는 숨겨진 개발자 설정으로 서버 주소를 변경할 수 있습니다.
- **Release** 빌드에서는 배포 주소로 고정됩니다.
- 현재 서버가 IP + 평문 HTTP로 서비스되어 `Info.plist`에서 ATS(`NSAllowsArbitraryLoads`)를 허용해 둔 상태이며, 백엔드 HTTPS 전환 후 도메인 예외로 좁힐 예정입니다.

**소셜 로그인**은 `Core/Networking/SpatiumSocialConfig.swift`에서 Google OAuth 클라이언트 ID를 관리합니다.

---

## 🗂️ 프로젝트 구조

```
Spatium/
├─ SpatiumApp.swift        # @main 진입점
├─ App/                    # ContentView — 온보딩→로그인 게이트→탭
├─ Core/
│  ├─ DesignSystem/        # 테마, 약관 링크
│  ├─ Networking/          # API 클라이언트·환경·소셜 설정
│  ├─ Models/              # 도메인 모델 (Project, RoomLayout, Auth 등)
│  ├─ Extensions/          # JWT, Haptics, 유틸
│  └─ Services/            # Auth/Project/ImgTo3D/Furniture 스토어·서비스
├─ Features/               # 화면 단위 모듈
│  ├─ Auth/  Home/  Rooms/  Scan/
│  ├─ Editor/  ImgTo3D/  Settings/  Onboarding/
├─ Shared/                 # 재사용 UIKit 브리지·컴포넌트
├─ Assets.xcassets/        # 아이콘·이미지·컬러
└─ testdata/               # 내장 3D 모델·테스트 스캔
```

`Core`(공용 인프라·도메인) / `Features`(화면) / `Shared`(재사용 UI) 3계층으로 분리하고, 상태는 `ObservableObject` 스토어(`ProjectStore`, `UserFurnitureStore`, `AuthTokenStore` 등)로 관리합니다.

---

## 🧪 테스트

- **SpatiumTests** — 유닛 테스트
- **SpatiumUITests** — UI / 런치 테스트

DEBUG 빌드는 로그인 없이 특정 화면으로 바로 진입하는 실행 인자를 지원합니다(스크린샷 검증용): `-UITestEditor`, `-UITestSettings`, `-UITestHome`, `-UITestImgTo3D`, `-UITestGuestCreate`, `-UITestTabToggle`.

---

## 🔗 관련 저장소

이 리포는 iOS 앱 전용입니다. 함께 구성되는 별도 저장소:
- `spatium-backend` — 서버
- `spatium-frontend` — 웹 프론트엔드
- `spatium-img-to-3d` — 사진→3D 변환 서버
