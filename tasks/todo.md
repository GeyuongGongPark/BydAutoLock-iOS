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
