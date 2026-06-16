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

## 참고 / 원본 프로젝트

- Android 원본: [PoorGrammerA/BydAutoLock](https://github.com/PoorGrammerA/BydAutoLock)
- BYD API 분석: [jkaberg/pyBYD](https://github.com/jkaberg/pyBYD)
