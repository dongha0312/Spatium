# Spatium Design Guide

> 프론트엔드 UI를 기준으로 PPT, 발표 자료, 보고서 삽화, 썸네일, 홍보 이미지와 시스템 다이어그램을 제작하기 위한 디자인 기준서입니다.  
> 최종 확인일: 2026-07-20  
> 디자인 원본 기준: `spatium-frontend/src/styles/`

## 1. Design Direction

Spatium의 시각 언어는 **따뜻한 공간감, 정돈된 정밀함, 현실과 디지털의 연결**을 표현한다.

- **Warm Spatial**: 나무, 가구, 실내 공간을 연상시키는 월넛 브라운과 샌드 골드를 사용한다.
- **Calm Precision**: 3D·AI 기술을 과도한 네온이나 사이버펑크 이미지로 표현하지 않는다. 정돈된 그리드, 얇은 경계선, 명확한 위계를 우선한다.
- **Tactile but Minimal**: 아이보리 표면, 부드러운 그림자, 8~20px의 라운드로 실제 인테리어 재료처럼 편안한 인상을 만든다.
- **One Product, Two Moods**: 일반 서비스 화면은 밝고 따뜻하게, 3D 편집 작업 공간과 발표 표지는 짙은 브라운으로 깊이감을 준다.

### 핵심 키워드

`공간` · `실측` · `따뜻함` · `정밀함` · `신뢰` · `모듈형` · `차분한 기술`

### 피해야 할 방향

- 파랑·보라 중심의 일반적인 SaaS/AI 그라데이션
- 형광색, 과도한 글로우, 사이버펑크 분위기
- 순백색 배경과 순검정 텍스트만 사용한 차가운 문서
- 한 슬라이드에 여러 종류의 그림자·모서리 반경을 혼용
- 장식 목적의 3D 오브젝트를 다수 배치해 실제 제품 화면보다 튀게 만드는 구성

---

## 2. Brand Palette

### 2.1 Core colors

| Token | Hex | RGB | 권장 역할 |
| --- | --- | --- | --- |
| Brand Brown | `#5C3D2E` | 92, 61, 46 | 주요 버튼, 핵심 선, 강조 제목, 활성 상태 |
| Sand Gold | `#C4956A` | 196, 149, 106 | 보조 강조, 단계 번호, 아이콘, 포커스, 그라데이션 시작점 |
| Espresso | `#1C1209` | 28, 18, 9 | 기본 제목과 본문, 다크 배경의 기준색 |
| Warm Gray | `#5A4535` | 90, 69, 53 | 본문 보조 텍스트, 캡션 |
| Taupe | `#A08878` | 160, 136, 120 | 메타데이터, 비활성 요소, 작은 라벨 |
| Warm Border | `#DDD3C6` | 221, 211, 198 | 카드·표·구분선 |
| Canvas Beige | `#F2EDE6` | 242, 237, 230 | 페이지 및 섹션 배경 |
| Ivory Surface | `#FAF7F3` | 250, 247, 243 | 카드, 헤더, 밝은 콘텐츠 표면 |
| White | `#FFFFFF` | 255, 255, 255 | 입력창, 이미지 프레임, 다크 배경 위 텍스트 |

### 2.2 Extended colors

| 이름 | Hex | 사용처 |
| --- | --- | --- |
| Soft Brand Fill | `#F3E9DE` | 선택된 탭, 활성 필터, 강조 박스 |
| Hero Brown | `#2A1D14` | 표지·히어로의 주 배경 |
| Editor Brown 1 | `#332820` | 다크 툴바 그라데이션 시작 |
| Editor Brown 2 | `#241B16` | 다크 툴바 그라데이션 끝 |
| Editor Base | `#1E1B18` | 3D 편집 캔버스 주변 |
| Light Gold | `#E8C49A` | 다크 배경의 강조 텍스트 그라데이션 |
| Success | `#3E7256` | 성공 및 완료 상태 |
| Success Light | `#E7F7ED` | 성공 배지 배경 |
| Danger | `#C0392B` | 오류 및 삭제 강조 |
| Danger UI | `#DC2626` | 폼 오류, 경고 아이콘 |
| Danger Light | `#FEE2E2` | 오류 배지 배경 |
| Info Blue | `#60A5FA` | 3D 편집기의 제한적 정보 강조에만 사용 |

### 2.3 Color usage ratio

밝은 슬라이드 또는 이미지의 권장 비율:

- 60%: `Canvas Beige` / `Ivory Surface`
- 25%: 흰색 카드 및 이미지 영역
- 10%: `Espresso` / `Warm Gray` 텍스트
- 5% 이하: `Brand Brown` / `Sand Gold` 강조

다크 표지 또는 섹션 슬라이드의 권장 비율:

- 70%: `Hero Brown` 또는 `Editor Base`
- 20%: 아이보리 텍스트와 반투명 브라운 표면
- 10% 이하: `Sand Gold` 및 `Light Gold`

### 2.4 Standard gradients

브랜드 그라데이션:

```text
135°  #C4956A  →  #5C3D2E
```

로고 확장 그라데이션:

```text
135°  #C4956A  →  #5C3D2E  →  #1C1209
```

홈 히어로 강조 텍스트:

```text
90°  #C4956A  →  #E8C49A
```

다크 편집기 툴바:

```text
180°  #332820  →  #241B16
```

### 2.5 PPT theme color mapping

| PowerPoint theme slot | 값 |
| --- | --- |
| Dark 1 | `#1C1209` |
| Light 1 | `#FAF7F3` |
| Dark 2 | `#5A4535` |
| Light 2 | `#F2EDE6` |
| Accent 1 | `#5C3D2E` |
| Accent 2 | `#C4956A` |
| Accent 3 | `#3E7256` |
| Accent 4 | `#996B3D` |
| Accent 5 | `#60A5FA` |
| Accent 6 | `#C0392B` |

---

## 3. Typography

### 3.1 Font family

프론트엔드 기준 글꼴:

```css
-apple-system, BlinkMacSystemFont, "Pretendard", "Segoe UI", sans-serif
```

PPT 및 이미지 권장 순서:

1. **Pretendard**: 한글·영문 혼용 자료의 기본
2. **Noto Sans KR**: Pretendard를 사용할 수 없을 때
3. **Segoe UI**: 영문 및 Windows 호환 대안
4. **Apple SD Gothic Neo**: macOS 대안

로고 워드마크 `SPATIUM`은 굵은 산세리프와 넓은 자간을 사용한다. 장문 본문에 세리프 글꼴을 섞지 않는다.

### 3.2 PPT type scale for 16:9 slides

| 역할 | 크기 | 굵기 | 권장 색상 |
| --- | ---: | ---: | --- |
| Cover title | 34~44pt | 800~900 | Ivory 또는 Espresso |
| Section number | 12~16pt | 700~800 | Sand Gold |
| Slide title | 26~32pt | 800 | Espresso |
| Lead sentence | 18~22pt | 600~700 | Brand Brown 또는 Espresso |
| Body | 15~18pt | 400~550 | Warm Gray |
| Card title | 15~18pt | 700~800 | Espresso |
| Caption / source | 9~11pt | 400~600 | Taupe |
| Numeric KPI | 30~48pt | 800~900 | Brand Brown |

### 3.3 Typography rules

- 제목은 짧고 단단하게 쓰고, 한 슬라이드의 핵심 문장은 한 줄 또는 두 줄로 제한한다.
- 한글 제목은 자간 `-1% ~ -3%`, 영문 대문자 라벨은 자간 `+8% ~ +16%`를 권장한다.
- 본문 줄 간격은 글자 크기의 `1.35~1.55배`로 설정한다.
- 본문은 한 줄 35~55자 수준을 권장한다.
- 강조는 굵기와 색상으로 해결한다. 밑줄과 이탤릭은 링크나 전문 용어 외에는 사용하지 않는다.
- 숫자와 단위 사이의 규칙을 통일한다. 예: `43,761 lines`, `4 applications`, `143 tests`.

---

## 4. Shape, Spacing and Depth

### 4.1 Corner radius

| 요소 | Radius |
| --- | ---: |
| 작은 버튼·입력창 | 8px |
| 태그·작은 정보 카드 | 10~12px |
| 일반 카드 | 16px |
| 큰 기능 카드·PPT 이미지 프레임 | 20px |
| 칩·단계 표시·프로필 | 999px 또는 원형 |

PPT에서는 화면 크기를 고려하여 위 수치를 약 1.5~2배 확대해도 된다. 한 페이지 안에서는 최대 두 종류의 radius만 사용한다.

### 4.2 Borders

- 기본 경계선: `1px solid #DDD3C6`
- 선택/포커스: `1~2px solid #C4956A`
- 다크 표면 경계: `1px solid rgba(255,255,255,0.10~0.14)`
- 표는 완전한 진한 격자보다 헤더 하단선과 연한 행 구분선을 선호한다.

### 4.3 Shadows

기본 카드:

```text
0 4px 24px rgba(60, 30, 10, 0.08)
```

강조 카드:

```text
0 12px 36px rgba(60, 30, 10, 0.08)
```

큰 기능 카드:

```text
0 10px 30px rgba(28, 18, 9, 0.06)
```

다크 배경의 강조 요소:

```text
0 8px 20px rgba(75, 42, 26, 0.35)
```

그림자는 중립 회색이 아니라 브라운 계열 투명색을 사용한다.

### 4.4 Spacing system

기본 단위는 4px이며, 실사용 핵심 단위는 다음과 같다.

`4 · 8 · 12 · 16 · 20 · 24 · 32 · 40 · 48 · 64 · 72`

- 카드 내부 여백: 24~40px
- 카드 사이 간격: 20~32px
- 섹션 사이 간격: 48~72px
- 제목과 설명 사이: 8~16px
- 설명과 주요 시각물 사이: 24~36px

---

## 5. Logo and Brand Mark

### 5.1 Source assets

- SVG logo: `spatium-ios/Spatium/Assets.xcassets/SpatiumLogo.imageset/spatium-logo.svg`
- Web raster logo: `spatium-frontend/src/assets/spatium-logo.png`
- App cube asset: `spatium-ios/Spatium/Assets.xcassets/SpatiumCube.imageset/spatium_cube.png`

### 5.2 Logo construction

로고는 라운드 사각형 안에 흰색 공간 분할 기호가 들어간 형태이며, 배경은 `Sand Gold → Brand Brown → Espresso` 그라데이션이다. 자료에서는 로고의 비율과 내부 선 굵기를 변경하지 않는다.

### 5.3 Clear space and minimum size

- 최소 여백: 로고 전체 폭의 25% 이상
- 화면용 최소 크기: 24px
- PPT 표지 권장 크기: 52~72px
- 워드마크와 함께 배치할 때 간격: 로고 폭의 20~30%

### 5.4 Wordmark

`SPATIUM`을 대문자로 쓰고, 800~900 굵기와 넓은 자간을 적용한다. 프론트엔드 헤더는 약 6px의 자간을 사용한다. PPT에서는 글자 크기에 비례해 자간을 조정하되, 일반 본문처럼 붙여 쓰지 않는다.

### 5.5 Do not

- 로고 배경을 단색 파랑이나 보라로 변경하지 않는다.
- 그라데이션 방향을 임의로 반전하지 않는다.
- 흰색 내부 기호만 떼어 다른 형태의 아이콘으로 사용하지 않는다.
- 사진 위에 대비가 부족한 상태로 직접 올리지 않는다. 필요하면 아이보리 또는 다크 브라운 원형/카드 위에 배치한다.

---

## 6. UI-derived Component Language

### 6.1 Header

- 높이: 63px
- 배경: `Ivory Surface`
- 하단: `Warm Border` 1px
- 좌우 여백: 데스크톱 32px, 모바일 20px
- 로고는 좌측, 메뉴는 중앙 또는 좌측 확장, 계정 액션은 우측에 배치한다.

PPT의 상단 라벨 영역에도 같은 구조를 응용할 수 있다. 좌측에 섹션명, 우측에 페이지 번호 또는 짧은 메타데이터를 두고 연한 하단선을 사용한다.

### 6.2 Buttons

Primary:

- 배경 `#5C3D2E`, 글자 흰색
- Radius 8~10px
- 굵기 700
- 표지 CTA나 핵심 결론에만 제한적으로 사용

Gradient primary:

- `#C4956A → #5C3D2E`
- 홈 히어로, 단계 번호, 완료 아이콘처럼 브랜드 인상이 필요한 곳에 사용

Secondary:

- 배경 `#FAF7F3`, 경계 `#DDD3C6`, 글자 `#5A4535`

Ghost on dark:

- 반투명 흰색 배경과 `rgba(255,255,255,0.12)` 경계
- 주요 버튼과 경쟁하지 않도록 채도를 낮춘다.

### 6.3 Cards

- 배경: `#FAF7F3` 또는 흰색
- 경계: `#DDD3C6`
- Radius: 16~20px
- 내부 여백: 24~40px
- 그림자: 브라운 계열 6~8% 투명도

PPT에서 기능 3개를 소개할 때도 같은 카드 문법을 사용한다. 아이콘, 짧은 제목, 최대 세 줄 설명의 순서로 구성한다.

### 6.4 Chips and step indicators

- Pill radius 사용
- 비활성: Border 또는 Taupe
- 현재 단계: Brand Brown
- 완료 단계: Sand Gold 또는 Success
- 번호는 원형 안에 배치하고 카드보다 작은 크기로 유지한다.

### 6.5 Status

| 상태 | 배경 | 텍스트/아이콘 |
| --- | --- | --- |
| Success | `#E7F7ED` | `#166534` 또는 `#3E7256` |
| Error | `#FEE2E2` | `#991B1B` 또는 `#C0392B` |
| Information | `#EFF6FF` | `#1E40AF` |
| Neutral | `#F2EDE6` | `#5A4535` |

정보 파랑은 상태 표시용 예외색이다. 브랜드 강조색처럼 넓게 사용하지 않는다.

---

## 7. Light and Dark Modes

### 7.1 Light mode

적용 대상:

- 일반 본문 슬라이드
- 기능 목록
- 시스템 아키텍처
- 사용자 여정
- 결과 및 테스트 표
- 보고서 삽화

기본 조합:

```text
Background  #F2EDE6
Surface     #FAF7F3 / #FFFFFF
Title       #1C1209
Body        #5A4535
Border      #DDD3C6
Accent      #5C3D2E / #C4956A
```

### 7.2 Dark mode

적용 대상:

- PPT 표지
- 섹션 전환 슬라이드
- 3D 에디터 기능 소개
- 핵심 기술 또는 데모 시작 화면

기본 조합:

```text
Background  #2A1D14 or #1E1B18
Surface     #332820 / rgba(255,255,255,0.05)
Title       #F5EFE6
Body        #C9BBAA
Accent      #C4956A / #E8C49A
Border      rgba(196,149,106,0.24)
```

다크 화면에서는 순백색을 모든 텍스트에 사용하지 않는다. 제목은 아이보리, 본문은 따뜻한 회갈색으로 단계화한다.

---

## 8. Presentation System

### 8.1 Canvas

- 화면비: 16:9
- 권장 크기: 1920×1080px 또는 PowerPoint Widescreen
- 안전 여백: 좌우 7.5%, 상하 7%
- 기본 열: 12-column grid
- 콘텐츠 최대 폭: 화면의 84~86%

### 8.2 Recommended slide templates

#### A. Cover

- 배경: `Hero Brown`
- 좌상단 또는 중앙에 작은 로고
- 제목: 아이보리 36~44pt
- 핵심 단어 한 구절만 Sand Gold 그라데이션
- 우측 하단에 제품 화면 또는 3D 공간 이미지를 20px radius 프레임으로 배치
- 배경 장식은 흐린 브라운 radial glow 두 개 이내

#### B. Section divider

- 다크 배경
- 작은 영문 eyebrow: Sand Gold, 대문자, 넓은 자간
- 큰 한글 섹션명
- 얇은 Sand Gold 선 또는 작은 원형 번호 하나만 사용

#### C. Text + screenshot

- 5:7 또는 4:8 비율의 2열
- 텍스트 영역에는 제목, 한 문장 결론, 3개 이하 bullet
- 스크린샷은 아이보리 프레임과 얇은 경계선 사용
- 스크린샷 아래 캡션은 Taupe 9~11pt

#### D. Three-feature cards

- 밝은 베이지 배경 위 동일 폭 카드 3개
- 카드별 아이콘 1개, 제목 1줄, 설명 2~3줄
- 한 카드만 강조해야 하면 Soft Brand Fill을 사용하고 크기를 바꾸지 않는다.

#### E. Process / user journey

- 4~6개의 단계 노드
- 각 노드는 원형 번호 + 짧은 제목 + 한 줄 설명
- 연결선은 Warm Border, 현재 핵심 단계만 Sand Gold
- 권장 흐름: `Scan → Restore → Edit → Generate → Save`

#### F. Architecture

- Client / Server / Storage의 3개 영역으로 구분
- 각 컴포넌트는 아이보리 카드
- 선은 Brand Brown 55% 또는 Sand Gold 75%
- 실선은 실제 연결, 점선은 선택 또는 향후 연결
- 기술 로고의 원색 사용은 최소화하고, 단색 아이콘으로 통일

#### G. KPI / result

- 큰 수치 2~4개만 사용
- 숫자는 Brand Brown 32~48pt
- 라벨은 Taupe 10~12pt
- 예: `4 Applications`, `43.7K LOC`, `143 Test Cases`, `2 3D Editors`

#### H. Problem / solution comparison

- 좌측 문제: 연한 Danger 또는 중립 회갈색
- 우측 해결: Soft Brand Fill 또는 Success Light
- 빨강과 초록을 넓은 면적으로 사용하지 말고 아이콘·라벨 수준으로 제한

### 8.3 Suggested deck rhythm

전체 자료에서 다크 슬라이드는 약 20~30%만 사용한다.

1. Dark cover
2. Light problem
3. Light solution and user journey
4. Dark product overview or demo opener
5. Light architecture
6. Light core features
7. Light technical deep dive
8. Light results and validation
9. Light limitations and roadmap
10. Dark closing

---

## 9. Screenshot and Image Treatment

### 9.1 Existing reusable sources

- 홈 단계 이미지·GIF: `spatium-frontend/public/images/steps/`
- 사용자 매뉴얼 이미지: `spatium-frontend/public/manuals/`
- iOS 온보딩 이미지: `spatium-ios/Spatium/Assets.xcassets/Onboarding*.imageset/`
- 로고 및 앱 아이콘: `spatium-ios/Spatium/Assets.xcassets/`
- 현재 시스템 구성도: `docs/images/system-architecture.svg`

### 9.2 Screenshot framing

- 기본 비율: 16:10 또는 실제 화면 비율 유지
- 모서리: 14~20px
- 경계: 1px `#DDD3C6`
- 밝은 화면의 바깥 프레임: `#FAF7F3`
- 다크 에디터 화면의 바깥 프레임: `#2A1D14`
- 그림자: `0 10px 30px rgba(28,18,9,0.10)` 이하
- 캡처 위에는 긴 문장을 올리지 않는다. 필요하면 1~3개의 번호형 callout을 사용한다.

### 9.3 Cropping

- 제품의 핵심 조작점이 중앙 또는 삼등분 교차점에 오도록 자른다.
- 헤더, 단계 표시기, 주요 버튼 중 최소 두 가지가 보여야 실제 서비스 화면임을 인식하기 쉽다.
- 3D 에디터는 캔버스만 자르지 말고 툴바나 가구 패널 일부를 함께 보여준다.
- Image-to-3D는 `원본 이미지 → 분할 결과 → GLB`의 전후 비교를 우선한다.

### 9.4 Callouts

- 원형 번호: Sand Gold 배경, 흰색 숫자
- 설명 라벨: Ivory Surface, Warm Border, Espresso 텍스트
- 선: 1.5~2px Sand Gold
- 화면 하나당 3개 이하

### 9.5 Photo direction

외부 사진이나 생성 이미지를 사용할 경우 다음 분위기를 유지한다.

- 따뜻한 자연광과 중성적인 실내
- 월넛, 오크, 베이지 패브릭, 아이보리 벽
- 현실적인 소형 주거 공간과 실제 생활감
- 광각 왜곡이 심하지 않은 카메라 높이
- 편집 전후를 비교하기 쉬운 정돈된 구도

피해야 할 이미지:

- 비현실적으로 넓고 비어 있는 고급 저택
- 보라·파랑 네온 조명의 게임형 3D 룸
- 메시가 지나치게 완벽해 실제 Image-to-3D 결과로 오해할 수 있는 이미지
- 텍스트가 들어간 AI 생성 이미지

---

## 10. Diagram and Chart Style

### 10.1 Architecture diagrams

권장 영역 색:

| 영역 | 배경 | 경계/아이콘 |
| --- | --- | --- |
| Client | `#FAF7F3` | `#C4956A` |
| Backend | `#F3E9DE` | `#5C3D2E` |
| AI | `#F2EDE6` | `#996B3D` |
| Storage | `#FFFFFF` | `#A08878` |

기존 `docs/images/system-architecture.svg`는 내용 구조는 재사용할 수 있으나 인디고·보라·파랑 팔레트가 현재 웹 브랜드와 다르다. 외부 제출용 PPT나 보고서에서는 위의 warm palette로 다시 스타일링한다.

### 10.2 Lines and arrows

- 실제 요청·응답: Brand Brown 실선 2px
- 파일/대용량 스트림: Sand Gold 실선 2px
- 선택적·후속 흐름: Taupe 점선 1.5px
- 화살표 라벨은 11~13pt, Warm Gray
- 교차선은 피하고, 연결선 방향은 좌→우 또는 상→하 중 하나로 통일한다.

### 10.3 Charts

데이터 시리즈 권장 순서:

1. `#5C3D2E`
2. `#C4956A`
3. `#996B3D`
4. `#A08878`
5. `#3E7256`
6. `#60A5FA`

- 축과 격자선: `#DDD3C6` 60~80%
- 데이터 라벨: `#5A4535`
- 배경: 투명 또는 `#FAF7F3`
- 3D 차트, 강한 그라데이션 막대, 원형 차트 남용을 피한다.
- 비율 비교는 가로 막대, 흐름은 단계도, 구성은 100% 누적 막대를 우선한다.

---

## 11. Image Generation Prompt Guide

AI로 PPT 배경이나 컨셉 이미지를 생성할 때 다음 템플릿을 사용한다.

### 11.1 Interior hero image

```text
A warm, realistic compact apartment interior prepared for spatial computing,
soft natural daylight, walnut and oak furniture, ivory walls, beige textiles,
clean but lived-in, subtle room scanning visualization and precise measurement cues,
premium editorial product photography, warm brown and sand-gold palette,
wide 16:9 composition with generous negative space for a Korean presentation title,
no text, no logos, no neon, no cyberpunk, no futuristic hologram overload
```

### 11.2 Product concept illustration

```text
An elegant product illustration showing a real room transforming into a clean 3D digital twin,
LiDAR scan lines transitioning into measured walls, doors and furniture,
warm ivory background, walnut brown structure lines, restrained sand-gold highlights,
minimal spatial computing aesthetic, accurate geometry, soft shadows,
professional Korean technology presentation style, 16:9, no text, no logo
```

### 11.3 Image-to-3D process visual

```text
A three-stage editorial composition: a single furniture photo, clean background segmentation,
and a textured 3D GLB-style model, consistent object identity across all stages,
warm beige studio background, walnut brown labels left blank, sand-gold connectors,
minimal technical infographic aesthetic, realistic and trustworthy, 16:9,
no text, no watermark, no neon colors
```

### 11.4 Negative prompt concepts

`purple gradient`, `blue neon`, `cyberpunk`, `hologram overload`, `sci-fi HUD`, `glossy plastic`, `luxury mansion`, `floating text`, `watermark`, `distorted furniture`, `impossible geometry`

생성 이미지는 실제 제품 기능을 설명하는 보조 시각물로만 사용한다. 실제 구현 화면처럼 오인될 수 있는 경우 반드시 `Concept image` 또는 `연출 이미지`로 표기한다.

---

## 12. Accessibility and Legibility

- 밝은 배경의 본문은 `#5A4535` 이상 농도를 사용한다. `#A08878`은 작은 메타데이터에만 사용한다.
- `#C4956A` 텍스트를 밝은 배경의 장문에 단독 사용하지 않는다.
- 다크 배경에서는 제목 `#F5EFE6`, 본문 `#C9BBAA`를 기본으로 한다.
- PPT 본문은 15pt 미만으로 줄이지 않는다. 발표장 규모가 큰 경우 18pt 이상을 사용한다.
- 색상만으로 상태를 구분하지 않고 아이콘, 라벨 또는 패턴을 함께 사용한다.
- 그래프 범례와 라벨을 직접 연결해 색상 판별 부담을 줄인다.
- 애니메이션은 fade, 12~24px 이동, 150~600ms 범위의 차분한 전환을 사용한다.
- 화면 전환, 확대/축소, 3D 회전 애니메이션은 한 번에 하나만 강조한다.

---

## 13. PPT and Image Production Checklist

### Before production

- [ ] 결과물의 목적과 대상이 발표, 보고서, 홍보 중 무엇인지 정했다.
- [ ] 16:9 또는 최종 출력 비율을 먼저 고정했다.
- [ ] Pretendard 또는 Noto Sans KR을 사용할 수 있는지 확인했다.
- [ ] 실제 제품 화면과 컨셉 이미지를 구분했다.

### Visual consistency

- [ ] Brand Brown과 Sand Gold가 핵심 강조색이다.
- [ ] 베이지/아이보리 면적이 전체에서 가장 크다.
- [ ] 카드 radius와 그림자 규칙이 슬라이드 전체에서 일관된다.
- [ ] 파랑·보라는 상태 정보 외에 넓게 사용하지 않았다.
- [ ] 한 슬라이드의 핵심 강조색은 한 종류다.

### Content and layout

- [ ] 제목은 두 줄 이내다.
- [ ] 본문은 3~5개 bullet 또는 짧은 단락으로 제한했다.
- [ ] 스크린샷이 왜 중요한지 한 문장으로 설명한다.
- [ ] 시스템 다이어그램의 실선과 점선 의미가 명확하다.
- [ ] 출처와 측정 기준을 9~11pt 캡션으로 표기했다.

### Final QA

- [ ] 100% 보기에서 텍스트와 이미지가 잘리지 않는다.
- [ ] 발표 화면에서 본문 크기와 대비가 충분하다.
- [ ] 로고의 비율, 색상, 안전 여백이 유지된다.
- [ ] 실제 기능보다 과장된 이미지에 `Concept` 표기가 있다.
- [ ] PDF 내보내기 후 글꼴 대체와 줄바꿈을 다시 확인했다.

---

## 14. Source Map

이 문서의 기준은 다음 파일에서 추출했다.

| 기준 | 소스 파일 |
| --- | --- |
| 전역 색상·글꼴·radius·shadow | `spatium-frontend/src/styles/global.css` |
| 헤더·로고 워드마크·계정 패널 | `spatium-frontend/src/styles/Header.css` |
| 다크 히어로·기능 카드·스크린샷 비율 | `spatium-frontend/src/styles/homepage.css` |
| 프로젝트 카드·사이드바·계정 화면 | `spatium-frontend/src/styles/mypage.css` |
| 다크 작업 공간·툴바·편집 컨트롤 | `spatium-frontend/src/styles/3deditor.css` |
| 단계 표시·업로드·분할·모델 보정 | `spatium-frontend/src/styles/imgto3d.css` |
| 인증 폼과 오류 상태 | `spatium-frontend/src/styles/loginpage.css`, `signuppage.css` |
| 긴 문서와 안내 콘텐츠 | `spatium-frontend/src/styles/cookiepolicy.css`, `manualpage.css` |
| 연락처용 큰 타이포 카드 | `spatium-frontend/src/styles/ContactUsPage.css` |
| 로고 색상과 형태 | `spatium-ios/Spatium/Assets.xcassets/SpatiumLogo.imageset/spatium-logo.svg` |

프론트엔드 토큰이 변경되면 이 문서의 Brand Palette, PPT theme mapping, 버튼·카드 규칙을 함께 갱신한다.
