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
- [ ] 빌드 확인
- [x] 수정 파일 목록
  - `AutoLockService.swift`: isIntentionalDisconnect 플래그, didEnterGeofence/didExitGeofence guard
  - `GeofenceManager.swift`: 동일 좌표 재등록 방지, fireEnterEvent 2초 디바운스
  - `LogManager.swift`: fetchLogs queue.sync 적용
  - `BydAutoLockWatch/WatchConnectivityManager.swift`: App Group guard let 수정
