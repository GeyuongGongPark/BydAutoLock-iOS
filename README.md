# BYD AutoLock — iOS / watchOS

BYD 전기차 자동 잠금/해제 앱의 비공식 iOS 포팅 프로젝트입니다.
Android [BydAutoLock](https://github.com/PoorGrammerA/BydAutoLock)을 네이티브 Swift/SwiftUI로 완전 재구현했습니다.

> **비공식 프로젝트**입니다. BYD 자동차와 무관하며, 사용에 따른 책임은 사용자 본인에게 있습니다.

---

## 주요 기능

### iPhone 앱

| 기능 | 설명 |
|---|---|
| **자동 잠금 해제** | BLE 신호 강도(RSSI)가 임계값 이상이면 자동 잠금 해제 |
| **자동 잠금** | RSSI가 임계값 이하로 떨어지면 자동 잠금 |
| **RSSI 필터링** | EMA 지수 이동 평균 + 선형 회귀 이상값 제거 + 히스테리시스 |
| **신호 소실 보호** | 신호 끊김 후 2분 그레이스 타이머 (오작동 방지) |
| **차량 상태 조회** | 잠금 여부, 배터리 %, 주행 가능 거리, 실내 온도, 에어컨 상태 |
| **수동 제어** | 앱 내 잠금/해제 버튼 |
| **에어컨 자동 제어** | 잠금 해제 시 에어컨 자동 켜기 / 잠금 시 자동 끄기 |
| **지오펜싱** | 차량 150m 이탈 시 BLE 스캔 자동 중단 (배터리 절약) |
| **정지 감지** | 5분간 정지 중이면 스캔 일시 중단, 움직임 감지 시 재개 |
| **백그라운드 동작** | 앱 종료/화면 잠금 상태에서도 자동 잠금/해제 동작 |
| **15개 지역 서버** | KR / EU / JP / SG / AU / BR / MX / NO / UZ / KZ / IN / ID / VN / SA / OM |
| **디버그 로그** | BLE·API·Geofence·GPS·Motion 이벤트 SQLite 저장, 태그 필터 지원 |

### 홈 화면 / 잠금 화면 위젯

| 위젯 | 표시 내용 |
|---|---|
| Small (2×2) | 서비스 ON/OFF · 잠금 상태 · 배터리 % |
| Medium (4×2) | 서비스 · 잠금 · 배터리 · RSSI |
| 잠금 화면 원형 | 잠금 상태 아이콘 |
| 잠금 화면 직사각형 | 서비스 상태 · 잠금 상태 · 배터리 % |

### Apple Watch 앱

| 기능 | 설명 |
|---|---|
| **차량 상태 표시** | 서비스 ON/OFF · 잠금/열림 · 배터리 % |
| **수동 제어** | 잠금 해제 / 잠금 버튼 |
| **서비스 토글** | Watch에서 서비스 시작/중지 |
| **iPhone 연결 상태** | 연결 끊김 시 안내 표시 |

### Watch 페이스 컴플리케이션

| 종류 | 표시 내용 |
|---|---|
| 원형 (Circular) | 잠금 상태 아이콘 + 배터리 % |
| 직사각형 (Rectangular) | 서비스/잠금/배터리 상태 + 잠금·해제 버튼 |
| 코너 (Corner) | 잠금 아이콘 + ON/OFF 레이블 |

> 컴플리케이션에서 잠금/해제 버튼 탭 시 Watch 앱이 즉시 열리며 동작 실행

---

## 기술 스택

| 영역 | 사용 기술 |
|---|---|
| UI | SwiftUI (Dark theme, NavigationStack) |
| BLE | CoreBluetooth (Background Central, State Restore) |
| 위치 | CoreLocation (CLCircularRegion, 150m Geofencing) |
| 모션 | CoreMotion (CMMotionActivityManager) |
| 암호화 | CommonCrypto (AES-128-CBC) · CryptoKit (MD5/SHA1) · Bangcle 커스텀 코덱 |
| 네트워크 | URLSession async/await (Swift Concurrency) |
| 저장소 | UserDefaults · Keychain (Security.framework) · SQLite3 |
| Watch 연동 | WatchConnectivity (WCSession) |
| 위젯/컴플리케이션 | WidgetKit |

---

## 아키텍처

```
iPhone App
├── AutoLockService          ← BLE 스캔 + RSSI 처리 + API 호출 (@MainActor)
├── BydVehicleService        ← BYD Cloud API 클라이언트 (actor)
├── GeofenceManager          ← CoreLocation 지오펜싱
├── WatchConnectivityManager ← Watch ↔ iPhone 양방향 통신
├── StorageManager           ← Keychain + UserDefaults + App Group
└── LogManager               ← SQLite 디버그 로그

Watch App
├── WatchMainView            ← SwiftUI UI
├── WatchConnectivityManager ← iPhone 명령 전송 / 상태 수신
└── WatchComplication        ← WidgetKit 컴플리케이션

Widget Extension
└── BydAutoLockWidget        ← WidgetKit (App Group으로 데이터 공유)
```

---

## 빌드 방법

### 요구 사항

- Xcode 15 이상
- iOS 16+ / watchOS 10+ 실기기
- Apple 계정 (무료 계정으로 사이드로딩 가능)
- `xcodegen` (`brew install xcodegen`)

### 빌드 단계

```bash
# 1. 저장소 클론
git clone https://github.com/GeyuongGongPark/BydAutoLock-iOS.git
cd BydAutoLock-iOS

# 2. project.yml에서 Bundle ID 변경
# PRODUCT_BUNDLE_IDENTIFIER: com.yourname.bydautolock
# App Group: group.com.yourname.bydautolock (iPhone + Widget entitlements)

# 3. Xcode 프로젝트 생성
xcodegen generate

# 4. Xcode로 열기
open BydAutoLock.xcodeproj

# 5. Product → Archive
```

### 무료 계정 사이드로딩 (AltStore / Sideloadly)

```bash
# Archive 후 IPA 추출
ARCHIVE=$(ls -t ~/Library/Developer/Xcode/Archives/**/*.xcarchive | head -1)
mkdir -p Payload
cp -r "$ARCHIVE/Products/Applications/BYD AutoLock.app" Payload/
zip -r BydAutoLock.ipa Payload
```

1. AltStore / Sideloadly로 iPhone에 설치
2. **설정 → 일반 → VPN 및 기기 관리**에서 개발자 신뢰

> 무료 계정은 7일마다 재서명 필요. 슬롯 3개 한도.

---

## 초기 설정

1. 앱 실행 후 **설정 → BYD 계정 설정**에서 이메일/비밀번호/PIN/지역 입력 후 로그인
2. **설정 → 블루투스 기기 설정**에서 차량 BLE 기기 선택
3. **설정 → RSSI 임계값 설정**에서 임계값 조정 (기본: 잠금 해제 -70dBm / 잠금 -85dBm)
4. 메인 화면에서 **자동 잠금 서비스 토글 ON**

---

## iOS 백그라운드 BLE 제한 안내

| 항목 | Android | iOS |
|---|---|---|
| 백그라운드 광고 스캔 | 무제한 | 시스템이 주기적으로 전달 (빈도 제한) |
| AllowDuplicatesKey | 항상 유효 | 백그라운드에서 무시됨 |
| 앱 종료 후 복원 | Foreground Service | `CBCentralManagerOptionRestoreIdentifierKey` |

포그라운드에서는 Android와 동일하게 동작합니다.

---

## 프로젝트 구조

```
BydAutoLock/
├── API/
│   ├── BangcleCodec.swift           # BYD 독자 CBC-AES 코덱 (808KB 룩업 테이블)
│   ├── CryptoUtils.swift            # MD5, SHA1-Mixed, AES-128-CBC
│   ├── BydConfig.swift              # 15개 지역 서버 팩토리
│   └── BydVehicleService.swift      # BYD API async/await 클라이언트
├── Models/                          # VehicleStatus, GpsInfo, HvacStatus 등
├── Service/
│   ├── AutoLockService.swift        # 핵심 서비스 (BLE + RSSI + API)
│   ├── GeofenceManager.swift        # CoreLocation 지오펜싱
│   └── WatchConnectivityManager.swift
├── Storage/
│   ├── StorageManager.swift         # UserDefaults + Keychain + App Group
│   └── KeychainHelper.swift
├── Log/
│   ├── LogManager.swift             # SQLite 로그 (최대 5,000행)
│   └── LogEntry.swift
├── Views/                           # SwiftUI 뷰 (메인, 설정, 로그)
└── Resources/
    └── bangcle_tables.bin           # BYD 암호화 룩업 테이블 (808KB)

BydAutoLockWatch/
├── BydAutoLockWatchApp.swift        # Watch 앱 진입점 + 딥링크 처리
├── WatchMainView.swift              # Watch UI
├── WatchConnectivityManager.swift
└── WatchComplication.swift          # WidgetKit 컴플리케이션

BydAutoLockWidget/
└── BydAutoLockWidget.swift          # iOS 홈/잠금 화면 위젯
```

---

## 릴리즈 노트

### v1.4.2 (build 11) — 2026-07-01

**iOS 26/27 베타 백그라운드 BLE 안정화**
- 앱이 백그라운드일 때 BLE 장치를 수 시간 동안 못 찾던 문제 수정
  → 기존: 전체 스캔(`scanForPeripherals`) 시도 → iOS 백그라운드에서 차단됨
  → 변경: UUID 저장 후 `retrievePeripherals` + `connect()` 로 스캔 없이 직접 재연결
  → 실측: 9시간 공백 → 38분으로 개선

**자동 해제 반응 속도 개선 (예측 사전 해제)**
- 차에 접근해도 해제까지 1~3분 걸리던 문제 개선
  → ATTO 3 BLE 20초 끊김/재연결 사이클에서 RSSI 데이터가 매번 초기화되던 문제
  → 60초 시간 기반 누적으로 변경, 여러 사이클에 걸쳐 접근 기울기 계산 가능

**이탈 시 자동 잠금 누락 수정**
- 해제 직후 BLE 신호가 순간 급락할 때 잠금이 실행되지 않던 문제 수정
  → 해제 후 30초 쿨다운 중 이탈 감지 시 쿨다운 만료 후 자동 잠금 예약
  → 그 사이 다시 접근하면 예약 취소

**안전성 개선 (화이트박스 테스트 #4)**
- 주행 시작 시 이탈 예약 잠금 자동 취소 (주행 중 오발 방지)
- 정지 감지 중 BLE 끊김 시 불필요한 재연결 시도 차단
- 복호화 실패 시 빈 문자열 대신 에러 반환으로 변경

---

### v1.4.1 (build 10) — 2026-06-30

**로그 전체 누락 버그 수정**
- v1.4 이전 일부 기기에서 로그가 전혀 기록되지 않던 문제 수정
  → SQLite DB 파일 경로의 디렉토리가 자동 생성되지 않아 DB 열기 실패

**안정성 개선**
- 자동 잠금 API 실패 후 45초 재시도 성공 시 잠금 상태 미반영 버그 수정
  → 이후 재연결 사이클에서 중복 잠금 API 호출 방지
- 차량 연결 없이 상태 새로고침 시 "로그인이 필요합니다" → "차량과 연결해 주세요"로 문구 수정
- 로그 뷰 빈 상태 안내 문구 오류 수정 (v1.3에서 제거된 기능 언급 잔존)

---

### v1.4 (build 9) — 2026-06-29

**주행 관련 버그 수정**
- 주행 종료 후 자동 잠금이 실행되지 않던 버그 수정
  → 지오펜스 이탈 후 주행 종료 시 즉시 GPS 폴링 + 잠금 API 호출
- 주행 중 지오펜스가 반복적으로 "내부"로 감지되던 버그 수정
  → BYD GPS API가 실시간 speed를 반환하지 않아 주행 중에도 지오펜스 재등록되던 문제
  → CoreMotion `isDriving` 기준으로 주행 중 지오펜스 재등록/진입 이벤트 차단

**백그라운드 안정화**
- GPS 정확도를 `ThreeKilometers`(셀룰러 기지국 기반)로 낮춰 배터리 소모 절감 (앱 suspend 방지 효과 동일)
- `fetch` 백그라운드 모드 선언 제거 (구현 없는 dead 선언)

**로그 스팸 제거**
- BLE 20초 재연결 사이클마다 반복되던 "이미 닫힘/열림 상태 - 명령 스킵" 로그 제거
  → 접근/이탈 감지 단계에서 `lastKnownLocked` 사전 필터링으로 불필요한 API 호출 차단

**코드 안전성 개선 (화이트박스 테스트 #3)**
- 타이머 재시작 시 cancel 누락 수정 (`sessionRefreshTimer`, `gpsPollTimer`)
- 선형 회귀 함수 force unwrap 제거 (`points.first!`, `points.last!`)
- `URL(string:)!` force unwrap 제거 → throw로 안전 처리
- AES 암호화/복호화 실패 시 빈 문자열 반환 → throws로 변경
- SQLite open/prepare 에러 체크 및 `db nil` guard 전반 적용
- BangcleCodec 테이블 로딩 bounds check, PKCS7 패딩 전체 바이트 검증
- `DateFormatter` 매 호출마다 생성되던 문제 → static으로 변경
- 신호 복구 시 신호 소실 알림 쿨다운 리셋

---

### v1.3 (build 8) — 2026-06-28

**안정성 개선**
- 주행 중 BLE 신호 끊김 시 알림 및 자동 잠금 스킵 (주행 중 오발 방지)
- 자동 잠금 API 실패(차량 통신 오류 등) 시 45초 후 1회 자동 재시도
- 움직임 감지(CoreMotion) 중복 콜백으로 BLE 스캔이 수십 번 반복 시작되던 버그 수정
- 타이머 재시작 시 기존 타이머 누수 방지
- 신호 소실 grace timer가 취소된 후에도 잠금이 실행되던 edge case 수정

**설정 개선**
- RSSI 임계값 역전(잠금 해제값 ≤ 잠금값) 저장 시 오류 표시 및 차단
- 지오펜스 반경 setter 범위 검증 추가 (50~500m 강제 클램핑)

**로그**
- 디버그 로깅 토글 제거 — 항상 로그 기록 (설정 메뉴 단순화)
- 신호 끊김 알림 문구 개선: "60초 후 자동으로 잠금됩니다"

**코드 품질**
- 미사용 변수(rssiLogTimer, rssiSamples) 제거
- silentReLogin 무한 재귀 방지 (isRelogging 플래그)

---

### v1.2.2 (build 7) — 2026-06-26

**백그라운드 안정화**
- iOS가 앱을 suspend할 때 BLE RSSI 폴링이 멈추던 문제 해결
  → `startUpdatingLocation()` (10m 정확도)으로 백그라운드 실행 유지
- BG 작업(UIBackgroundTask) 만료로 BLE가 끊길 때 오발 잠금 방지

**지오펜스 개선**
- GPS 갱신 시 지오펜스 진입 이벤트 중복 발생 수정 (2초 디바운스 + 동일 좌표 재등록 방지)
- 지오펜스 이탈 상태에서 불필요한 BLE 재연결 시도 차단
- **지오펜스 반경을 설정에서 직접 조정 가능** (50~500m, 기본 150m)

**버그 수정**
- 로그 분류 필터 바가 가려지는 문제 재수정 (재발 방지)
- Watch App Group 강제 언래핑 크래시 방지
- LogManager 멀티스레드 안전성 확보

---

### v1.2.1 (build 6) — 2026-06-26

- 위젯 App Group 권한 추가 및 표시 항목 개선
- 로그 필터에 BG 태그 추가

### v1.2 (build 5) — 2026-06-25

- 지오펜스 내부에서 서비스 시작 시 스캔 차단 버그 수정
- dead code 제거 및 stop() 상태 초기화

---

## 참고 / 원본 프로젝트

- Android 원본: [PoorGrammerA/BydAutoLock](https://github.com/PoorGrammerA/BydAutoLock)
- BYD API 분석: [jkaberg/pyBYD](https://github.com/jkaberg/pyBYD)
