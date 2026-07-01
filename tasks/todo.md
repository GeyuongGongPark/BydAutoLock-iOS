# 코드/로그 검수 후 수정 계획

## 분석 근거
- 코드 정적 분석 (3개 서브에이전트)
- 실제 로그 분석: byd_log_20260626_093153, byd_log_20260626_093647

---

## P1 - 로그에서 명확히 재현된 버그

- [x] **1. BG Task 종료 → 신호 소실 잠금 오발 방지**
  - 로그 패턴: `[BG] RSSI 폴링 Background Task 종료` → 즉시 `BLE 연결 끊김` → `신호 소실. 즉시 안전 잠금 실행.` → 1초 내 재연결
  - 원인: BG Task 만료 시 iOS가 앱 suspend → BLE 끊김인데, 실제 신호 소실과 동일하게 처리
  - 수정: `isIntentionalDisconnect` 플래그 추가, expirationHandler에서 true 설정, `didDisconnectPeripheral`에서 체크 후 handleSignalLoss 스킵
  - 파일: `AutoLockService.swift`

- [x] **2. 지오펜스 중복 진입 이벤트 수정**
  - 로그 패턴: GPS 갱신 1회에 `지오펜스 진입. BLE 재개.` 가 2번씩 발생, BLE 재연결 시도도 중복
  - 원인: `registerGeofence()` 반복 호출 + `didDetermineState()`와 `didEnterRegion()` 중복 콜백
  - 수정: 동일 좌표 재등록 방지(`lastRegisteredLat/Lng`) + `fireEnterEvent()` 2초 디바운스
  - 파일: `GeofenceManager.swift`

---

## P2 - 코드 분석에서 확인된 버그

- [x] **3. stationaryTimer 중복 생성 방지**
  - 코드 확인 결과: `startStationaryTimer()`가 이미 `stationaryTimer?.cancel()` 선행 호출 → 실제 중복 없음
  - 별도 수정 불필요

- [x] **4. stop() 이후 지오펜스 콜백으로 인한 스캔 재개 방지**
  - 원인: `stop()` 후에도 `didEnterGeofence()` 콜백이 오면 `beginScanning()` 재실행
  - 수정: `didEnterGeofence()`, `didExitGeofence()` 시작에 `guard isRunning else { return }` 추가
  - 파일: `AutoLockService.swift`

- [x] **5. LogManager fetchLogs 스레드 안전성**
  - 원인: `log()`는 background queue 비동기, `fetchLogs()`는 queue 무시하고 직접 DB 접근
  - 수정: `fetchLogs()`를 `queue.sync`로 감쌈
  - 파일: `LogManager.swift`

- [x] **6. WatchConnectivityManager(Watch) App Group 강제 언래핑 수정**
  - 원인: `UserDefaults(suiteName:)!` 강제 언래핑 → App Group 권한 없으면 크래시
  - 수정: `guard let` 으로 안전하게 처리
  - 파일: `BydAutoLockWatch/WatchConnectivityManager.swift`

---

---

## 백그라운드 안정화 (근본 문제 해결)

**원인**: iOS는 `UIBackgroundTask` 만료 후 앱을 suspend → RSSI 폴링 타이머 멈춤 → 잠금/해제 불가

**해결**: `startUpdatingLocation()` (정확도 최저, 이동 필터 최대)으로 앱 suspend 차단
- `desiredAccuracy = kCLLocationAccuracyThreeKilometers` → GPS 거의 안 씀
- `distanceFilter = CLLocationDistanceMax` → 콜백 최소화
- 서비스 실행 중에만 활성화, 중지 시 해제

- [x] **7. GeofenceManager에 keepAlive 메서드 추가**
  - `startBackgroundKeepAlive()` / `stopBackgroundKeepAlive()`
  - `desiredAccuracy = kCLLocationAccuracyThreeKilometers`, `distanceFilter = CLLocationDistanceMax`
  - `didUpdateLocations` 빈 콜백 추가
  - 파일: `GeofenceManager.swift`

- [x] **8. AutoLockService start/stop에서 keepAlive 연동**
  - `start()`: 지오펜싱 여부 무관하게 `geofenceManager.setup()` + `startBackgroundKeepAlive()` 항상 호출
  - `stop()`: `stopBackgroundKeepAlive()` 호출
  - 파일: `AutoLockService.swift`

- [x] **9. 지오펜스 이탈 후 BLE 재연결/RSSI 폴링 차단**
  - 원인: `didDisconnectPeripheral`에서 `isInsideGeofence` 체크 없이 무조건 `connect()` 호출
  - 수정: 이탈 상태에서 재연결 시도 스킵 + `didConnect`에서도 RSSI 폴링 스킵
  - 파일: `AutoLockService.swift`

## 검토
- [ ] 빌드 확인 (로그 필터 포함)
- [x] 수정 파일 목록
  - `AutoLockService.swift`: isIntentionalDisconnect 플래그, didEnterGeofence/didExitGeofence guard
  - `GeofenceManager.swift`: 동일 좌표 재등록 방지, fireEnterEvent 2초 디바운스
  - `LogManager.swift`: fetchLogs queue.sync 적용
  - `BydAutoLockWatch/WatchConnectivityManager.swift`: App Group guard let 수정

---

## v1.2.2 추가 작업

- [x] **지오펜스 반경 사용자 조정**
  - `StorageManager.swift`: `geofenceRadius` 키 + 프로퍼티 (기본 150m, 50~500m)
  - `GeofenceManager.swift`: 하드코딩 radius 제거 → StorageManager 참조
  - `ThresholdSettingsView.swift`: 슬라이더 UI 추가 (지오펜싱 활성화 시 표시)

- [x] **v1.2.2 build 7 버전업**
  - `project.yml` 수정 → xcodegen generate

- [x] **로그 분류 필터 바 재수정**
  - VStack + List overlay 방식으로 변경 (safeAreaInset 실기기 미동작 확인)
  - List를 항상 고정, 빈 상태는 overlay 처리

- [x] **릴리즈 노트 작성**
  - `README.md`에 ## 릴리즈 노트 섹션 추가

## 검토
- [x] 빌드 확인 (로그 필터 실기기 동작 확인)

---

## 화이트박스 테스트 #2 (v1.2.2 기준)

### 수정 완료
- [x] **watchdogTimer cancel 누락** — `startWatchdog()` 시작 전 기존 타이머 취소 추가
- [x] **signalLossTimer race condition** — guard에 `self.signalLossTimer != nil` 추가
- [x] **LogView init 메인스레드 블로킹** — `State(initialValue: [])` 빈 배열로 초기화
- [x] **BydVehicleService silentReLogin 무한 재귀** — `isRelogging` 플래그 추가
- [x] **ThresholdSettingsView RSSI 역전 저장** — `unlockRssi > lockRssi` 검증 + Alert
- [x] **StorageManager geofenceRadius setter 범위 검증 누락** — `max(50, min(500, ...))` 클램핑
- [x] **MainView refreshVehicleStatus 중복 호출** — `guard !isRefreshing` 추가
- [x] **주행 중 신호 소실 알림/잠금** — `isDriving` 시 handleSignalLoss 스킵
- [x] **알림 텍스트 misleading** — "60초 후 자동으로 잠금됩니다"로 수정
- [x] **rssiLogTimer/rssiSamples dead code** — 미사용 변수 및 참조 제거

### 로그 분석 #1 (byd_log_20260628) 수정

- [x] **Motion 이벤트 폭발적 중복 발생** (최대 51회 반복)
  - 원인: `startMotionUpdates()` 콜백마다 `Task { @MainActor }` 생성 → 큐에 적재
  - 수정: `self.motionManager != nil` guard 추가 → 첫 Task에서 nil 처리 후 이후 차단
- [x] **자동 잠금 API 실패 시 재시도 없음** (6002 통신 오류)
  - 수정: catch 블록에서 자동 잠금 실패 시 45초 후 1회 재시도 추가 (재접근 시 취소)

### 잔여 이슈 (설계 의도 또는 실용적 영향 낮음)
- [ ] **LogView reload() 메인스레드 동기 블로킹** — fetchLogs()가 queue.sync 사용. 실용적 영향 작음 (500건 SQLite 읽기 수 ms 수준)
- [ ] **GeofenceManager ignoringExitUntil 10초 실제 이탈 손실** — 설계 의도 (spurious exit 차단). 시속 18km/h 이상 이탈 시에만 문제
- [ ] **onSessionUpdated/onSessionExpired 콜백 메인스레드** — 호출 측(AutoLockService)이 Task { @MainActor } 로 처리 중이므로 사실상 안전
- [ ] **willRestoreState에서 targetMac nil 가능** — 앱 killed 후 복원 시 발생, 드문 케이스

---

## 화이트박스 테스트 #3 (전체 코드 검수)

### 수정 완료
- [x] **1. startSessionRefresh() cancel 누락** — `sessionRefreshTimer?.cancel()` 추가
- [x] **2. startGpsPoll() cancel 누락** — `gpsPollTimer?.cancel()` 추가
- [x] **3 & 7. linearRegressionSlope/Predict force unwrap** — `guard let first/last` 로 안전하게
- [x] **4. BydVehicleService URL force unwrap** — `URL(string:)!` → `guard let url` + throw
- [x] **5. LogManager.openDatabase() 에러 무시** — `sqlite3_open` 결과 체크 및 db=nil
- [x] **6. BangcleCodec readU16/readU32 bounds check** — `guard offset+N <= bytes.count` 추가
- [x] **8 & 9. BydVehicleService login userId nil** — `guard let uid/sign/encry` + throw, silentReLogin 자동 해결
- [x] **10. CryptoUtils 빈 문자열 반환** — `aesEncryptHex/aesDecryptUTF8` throws 추가, callers try로 변경
- [x] **11. LogManager insertLog prepare 미체크** — `sqlite3_prepare_v2` 결과 == SQLITE_OK 검증
- [x] **12. LogEntry.formattedTime DateFormatter 매번 생성** — static let으로 변경
- [x] **13. NotificationManager signalLost 쿨다운 미리셋** — `resetSignalLostCooldown()` + processRSSI에서 호출
- [x] **14. BangcleCodec pkcs7Unpad 부분 검증** — `allSatisfy { $0 == last }` 추가
- [x] **15. ThresholdSettingsView init+onAppear 이중 초기화** — 중복 `onAppear { loadFromStorage() }` 제거

### 검토
- [ ] 빌드 확인

---

## v1.4 (build 9)

### 로그 분석 #2 개선

- [x] **"이미 닫힘/열림 상태 - 명령 스킵" 로그 스팸 제거**
  - 원인: BLE 20초 재연결마다 `isFirstRssiAfterConnect` → 접근/이탈 감지 → `triggerCarAction` 호출 → `lastKnownLocked` 체크로 스킵 로그 반복
  - 수정 1: `processRSSI` isFirstRssiAfterConnect — `lastKnownLocked == false`이면 API 없이 `proximityState = .near`만
  - 수정 2: `evaluateProximity` 접근 감지 — `lastKnownLocked != false` 조건 추가
  - 수정 3: `evaluateProximity` 이탈 감지 — `lastKnownLocked != true` 조건 추가
  - 수정 4: `triggerCarAction` 중복 스킵 — 로그 제거, 방어적 처리만 유지

### 백그라운드 동작 최적화

- [x] **`fetch` 백그라운드 모드 제거**
  - `UIBackgroundModes`에 `fetch` 선언만 있고 `performFetchWithCompletionHandler` 구현 없음
  - `Info.plist` + `project.yml` 양쪽에서 제거

- [x] **GPS accuracy 낮춤 (배터리 절약)**
  - `kCLLocationAccuracyNearestTenMeters` → `kCLLocationAccuracyThreeKilometers` (셀룰러 기지국 기반)
  - `distanceFilter` 10m → 100m
  - BLE 신호 인식, 지오펜싱과 무관 — 앱 suspend 방지 목적만

### 검토
- [x] 수정 파일: `AutoLockService.swift`, `GeofenceManager.swift`, `Info.plist`, `project.yml`

---

## 로그 분석 #3 (byd_log_20260629) — 주행 관련 버그

### 수정 완료

- [x] **주행 종료 후 잠금 안 됨**
  - 원인: 지오펜스 이탈(13:11:42) → 이 시점 isDriving=true → 잠금 스킵. 주행 종료(13:11:59) → isInsideGeofence=false → RSSI 폴링 없어 이탈 감지 불가. 결과: 다음 GPS 폴링(5분)까지 잠금 불가.
  - 수정: `startDrivingDetection()` — 주행 종료 시 `!isInsideGeofence`이면 즉시 GPS 폴링 + 자동 잠금 API 호출
  - 파일: `AutoLockService.swift`

- [x] **주행 중 지오펜스 반복 "내부" 감지**
  - 원인: BYD GPS API가 실시간 speed를 반환하지 않음 (주행 중에도 speed=0). `gps.speed <= 5.0` 조건 통과 → 현재 위치(이동 중)로 지오펜스 재등록 → 즉시 내부 판정 → 잠시 후 외부로 전환 반복.
  - 수정 1: `pollVehicleGPS()` — `!isDriving` 조건 추가로 주행 중 지오펜스 재등록 차단
  - 수정 2: `didEnterGeofence()` — `guard !isDriving`을 `isInsideGeofence = true` 이후로 이동 (BLE 재개만 차단, 상태는 정확하게 유지)
  - 파일: `AutoLockService.swift`

- [x] **didEnterGeofence guard 위치 버그 (화이트박스 발견)**
  - 원인: `guard isRunning, !isDriving else { return }`가 `isInsideGeofence = true` 보다 앞에 있어 주행 중 진입 이벤트 시 상태 미갱신
  - 시나리오: 주행 중 목적지 도착 → 진입 이벤트 무시 → `isInsideGeofence = false` 유지 → 주행 종료 시 `!isInsideGeofence` 조건 충족 → 실제로는 내부인데 자동 잠금 오실행
  - 수정: `isInsideGeofence = true` 먼저 세팅 → 그 다음 `guard !isDriving` (BLE 재개만 차단)
  - 파일: `AutoLockService.swift`

### 검토
- [x] 수정 파일: `AutoLockService.swift`

---

## 로그 누락 버그 수정

- [x] **LogManager applicationSupportDirectory 미생성으로 로그 전체 누락**
  - 원인: `FileManager.urls(for:)`는 경로만 반환, 디렉토리 실제 생성 보장 안 함 → `sqlite3_open` 실패 → `db = nil` → 모든 로그 무시
  - 화이트박스 테스트 #3에서 `sqlite3_open` 에러 체크는 추가했으나 실패 원인(디렉토리 미존재) 자체를 해결하지 않았음
  - 수정: `sqlite3_open` 전 `FileManager.createDirectory(withIntermediateDirectories: true)` 추가
  - 파일: `LogManager.swift`

- [x] **LogView 빈 상태 문구 오류**
  - "디버그 로깅이 활성화되어 있고" 문구 → v1.3에서 토글 제거됐으나 잔존 → 테스터 혼란 유발
  - 수정: 해당 문구 제거
  - 파일: `LogView.swift`

---

## 가상 테스트 — 자동 잠금/해제 로직

- [x] **시나리오 1~8 전체 검토 완료** (접근/이탈/신호소실/재연결/주행중/쿨다운 등)

- [x] **재시도 후 lastKnownLocked 미업데이트 버그 (가상 테스트 발견)**
  - 원인: 자동 잠금 실패 → 45초 재시도 성공 후 `lastKnownLocked` 갱신 누락 → 이후 재연결 사이클에서 중복 잠금 API 호출 가능
  - 수정: 재시도 성공 후 `await MainActor.run { self.lastKnownLocked = true }` 추가
  - 파일: `AutoLockService.swift`

---

## 로그 누락 케이스 분석

- [x] LogManager 전체 코드 흐름 검토 — 로그가 실제로 안 쌓이는 경로 찾기

### 분석 결과 (byd_log_20260629_185532)

- [x] **앱 suspend로 인한 로그 공백 (구조적 한계)**
  - Watchdog(5분)/Session(15분) 로그가 수 시간 동안 없음 → 앱 완전 suspend 확인
  - `startUpdatingLocation(ThreeKilometers)`가 모든 상황에서 suspend를 막지 못함
  - iOS 구조적 제한 — 코드 버그 아님. 지오펜스 이벤트 사이 구간은 로그 공백이 됨

- [x] **이 로그는 v1.3 이전 버전** — "신호 소실. 즉시 안전 잠금 실행." 메시지로 확인
  - v1.4에서 수정된 버그들(주행 중 지오펜스 재등록 등)이 그대로 관찰됨

- [x] **5011 에러 스팸** — 테스터 PIN 미설정 상태에서 자동 잠금/해제 반복 시도

### 잔여
- [ ] v1.4.1 버전에서도 suspend 발생하는지 추가 로그 필요

---

## 화이트박스 테스트 — 이번 세션 변경분

- [x] BydVehicleService.swift — BydError.serviceNotRunning 케이스 검토 (이상 없음)
- [x] AutoLockService.swift — fetchVehicleStatus 변경 검토 (이상 없음)
- [x] BydError switch 처리 누락 여부 확인 — exhaustive switch 없음, localizedDescription 사용으로 자동 처리

---

## 차량 상태 새로고침 오류 문구 수정

- [x] BLE 미연결 상태에서 새로고침 시 "로그인이 필요합니다" → "차량과 연결해 주세요"로 수정
  - 원인: `fetchVehicleStatus`에서 `vehicleService == nil`이면 `BydError.notLoggedIn` throw
  - 수정: `BydError.serviceNotRunning` 케이스 추가 + `fetchVehicleStatus`에서 해당 에러 사용
  - 파일: `BydVehicleService.swift`, `AutoLockService.swift`

---

## iOS 27 베타 대응 (브랜치: ios27)

### 문제 분석

- **로그 증거**: `byd_log_20260630_095743_ATTO_3_BYD_BLE3.txt` 에서 22:27~07:31 (약 9시간) 동안
  지오펜스 내부 + Watchdog 5분 주기 정상 동작 + `기기 탐색 스캔 시작` 반복에도 `타겟 발견` 0건
- **근본 원인**: `beginScanning()`에서 `connectedPeripheral == nil`이면 `scanForPeripherals(withServices: nil)` 호출
  → iOS 백그라운드에서 `withServices: nil` 스캔은 **원칙적으로 차단** (iOS 7+ 공식 제한)
  → iOS 27 베타에서 이 제한이 더 엄격하게 적용됨
- **연쇄 문제**: `stopBLEScan()`이 `connectedPeripheral = nil`로 초기화 → 다음 `beginScanning()` 시 스캔 폴백

### 해결 방향

`scanForPeripherals` 의존을 최소화하고, `connect()` 기반 재연결로 전환:
1. **Peripheral UUID 영구 저장** — 한 번이라도 연결한 peripheral의 UUID를 `StorageManager`에 저장
2. **`retrievePeripherals(withIdentifiers:)` fallback** — UUID가 있으면 스캔 없이 직접 `connect()` (백그라운드에서도 동작)
3. **`stopBLEScan()`에서 `connectedPeripheral` 참조 유지** — `connectedPeripheral = nil` 제거
4. **`stop()`에서 명시적 nil 처리** — 서비스 완전 종료 시에만 nil 초기화

### 수정 항목

- [x] **1. StorageManager — `peripheralUUID` 프로퍼티 추가**
  - 파일: `StorageManager.swift`

- [x] **2. AutoLockService — `didDiscover`에서 UUID 저장**
  - `storage.peripheralUUID = peripheral.identifier.uuidString`
  - 파일: `AutoLockService.swift`

- [x] **3. AutoLockService — `stopBLEScan()`에서 `connectedPeripheral = nil` 제거**
  - `cancelPeripheralConnection()` 유지, `connectedPeripheral = nil` 제거
  - 파일: `AutoLockService.swift`

- [x] **4. AutoLockService — `stop()`에서 `connectedPeripheral = nil` 추가**
  - `stopBLEScan()` 호출 후 명시적 nil 처리
  - 파일: `AutoLockService.swift`

- [x] **5. AutoLockService — `beginScanning()`에 UUID fallback 추가**
  - `connectedPeripheral == nil`이면 `storage.peripheralUUID`로 `retrievePeripherals` → `connect()` 시도
  - 실패 시 기존 스캔으로 폴백 (처음 연결 시에만)
  - 파일: `AutoLockService.swift`

### 검토
- [x] 빌드 확인 (BUILD SUCCEEDED)
- [x] 실기기 테스트 — `재연결 시도` 105회 정상 동작, 9시간 공백 → 38분으로 개선 확인

---

## 예측 사전 해제 지연 개선 (ios27 브랜치)

### 문제 분석

- **증상**: 차에 접근해도 자동 해제까지 1~3분 소요
- **원인 1**: ATTO 3 BLE가 20초마다 강제 끊김 → `handleSignalLoss()` → `rssiWindow.removeAll()`
  → 매 사이클 처음부터 데이터 쌓기 → `rssiWindow.count >= 5` 조건 못 채움 → 예측 사전 해제 불발
- **원인 2**: iOS 27 백그라운드에서 `connect()` 응답 자체가 1~3분 걸리는 케이스 존재 (OS 한계)

### 해결 방향

`rssiWindow`를 연결 끊김 시 클리어하지 않고, **시간 기반(60초)** 으로만 오래된 데이터 제거
→ 여러 BLE 연결 사이클에 걸쳐 데이터 누적 → 예측 해제 조건 충족 빨라짐

### 수정 항목

- [ ] **1. `handleSignalLoss()`에서 `rssiWindow.removeAll()` 제거**
  - 파일: `AutoLockService.swift`

- [ ] **2. `processRSSI()`에서 count 기반 → 시간 기반 필터링으로 교체**
  - `rssiWindowSize = 10` 상수 → `rssiWindowDuration: TimeInterval = 60` 으로 교체
  - `if rssiWindow.count > rssiWindowSize` → `rssiWindow.filter { 60초 이내 }` 로 변경
  - 파일: `AutoLockService.swift`

### 검토
- [x] 화이트박스 테스트 — 이상값 필터 영향 없음, 이탈 후 재접근 시 오발 없음
- [x] 빌드 확인 (BUILD SUCCEEDED)

---

## 이탈 시 잠금 실패 수정 (ios27 브랜치)

### 문제 분석 (byd_log_20260701_095237)

- **케이스 1 (23:11:59)**: 재연결 unlock → 5초 후 이탈 감지 → `unlock 쿨다운(30s)` 차단 → 쿨다운 만료 후 재접근 → 잠금 미발동
- **케이스 2 (07:37:51)**: unlock → 7초 후 이탈 감지 → `unlock 쿨다운(30s)` 차단 → BLE 20s 사이클 반복으로 신호소실타이머 리셋 → 잠금 미발동

**패턴**: unlock 직후 BLE 신호가 일시 급락(ATTO 3 특성) → 이탈 감지는 맞지만 쿨다운에 막힘 → 쿨다운 만료 후 재트리거 없음

### 해결 방향

이탈 감지 시 쿨다운 중이면 즉시 차단하는 대신, 쿨다운 만료 시점에 잠금 실행 예약 (`departureLockTimer`)

### 수정 항목

- [x] **1. `departureLockTimer` 변수 추가**
  - `private var departureLockTimer: DispatchSourceTimer?`

- [x] **2. `evaluateProximity()` — 이탈 감지 시 쿨다운 체크 후 예약**
  - `triggerCarAction` 직접 호출 대신: 쿨다운 잔여 시간 계산 → 잔여 > 0이면 `scheduleDepartureLock(after:)`, 아니면 즉시 실행

- [x] **3. `evaluateProximity()` — 접근/예측접근 감지 시 `departureLockTimer` 취소**
  - 다시 접근하면 예약된 잠금 취소 (접근 감지 + 예측 접근 기울기 확인 경로 양쪽)

- [x] **4. `scheduleDepartureLock(after:)` 메서드 추가**
  - 쿨다운 만료 후 실행, `proximityState == .far` 재확인 후 `triggerCarAction`

- [x] **5. `stop()`에서 `departureLockTimer` 취소**

### 화이트박스 테스트
- [x] 타이머 fire handler에서 `departureLockTimer != nil` 체크 → cancel 후 Task 잔존 방지
- [x] `scheduleDepartureLock()` 시작 시 기존 타이머 cancel 먼저 → 중복 방지
- [x] 예측 접근 경로에서도 타이머 취소 추가 (화이트박스에서 발견)
- [x] 이탈 → departureLockTimer + 이후 신호소실 → signalLossTimer 동시 존재 가능하나 양쪽 모두 `lastKnownLocked != true` 체크로 중복 API 차단 → 안전
- [x] 재이탈 감지 중복 불가 — 이탈 시 proximityState=.far, 다음 evaluateProximity에서 wasNear=false → 이탈 경로 진입 불가

### 검토
- [x] 빌드 확인 (BUILD SUCCEEDED)

---

## 화이트박스 테스트 #4 (main 브랜치 전체 코드)

### 수정 완료

- [x] **1. departureLockTimer — handleSignalLoss() 취소 누락**
  - 신호 소실 시 signalLossTimer(60s) + departureLockTimer 동시 존재 → 중복 잠금 API 호출
  - 수정: `handleSignalLoss()` 초반에 `departureLockTimer?.cancel()` 추가
  - 파일: `AutoLockService.swift`

- [x] **2. departureLockTimer — isDriving=true 전환 시 취소 누락**
  - 주행 시작 후 타이머 만료 → 주행 중 자동 잠금 위험
  - 수정: `startDrivingDetection()`에서 `isDriving=true` 분기에 취소 추가
  - 파일: `AutoLockService.swift`

- [x] **3. didDisconnectPeripheral — isStationary=true인데 connect() 재시도**
  - 정지 중 BLE 끊김 → 불필요한 connect 재시도 → 배터리 낭비 + BLE 상태 불일치
  - 수정: `didDisconnectPeripheral()`에서 `isStationary` 체크 추가
  - 파일: `AutoLockService.swift`

- [x] **4. aesDecryptUTF8 — UTF-8 디코딩 실패 시 빈 문자열 반환**
  - `?? ""`로 조용히 실패 → 상위 호출자가 에러 감지 불가, JSON 파싱 실패로 느리게 전파
  - 수정: `guard let str = String(data:encoding:) else { throw CryptoError.decryptionFailed }`
  - 파일: `CryptoUtils.swift`

### 미수정 (설계 의도 / 낮은 영향)
- rssiWindow 유지 후 오판 가능성 → 의도된 동작, 기울기 계산으로 안전
- fetchLogs 메인 스레드 블로킹 → 기존 알려진 이슈, 500건 SQLite 수 ms 수준
- lockAuto fire-and-forget 에러 무시 → 의도된 설계, 45초 재시도 존재
- stationaryTimer didExitGeofence 취소 누락 → 미미한 상태 불일치, 실제 영향 없음

### 검토
- [x] 빌드 확인 (BUILD SUCCEEDED)
