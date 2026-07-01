# Lessons Learned

---

## 워크플로우 필수 순서

**모든 작업의 순서:**
1. `tasks/todo.md` — 작업 계획 먼저 작성
2. 코드 작업 실행
3. `tasks/lessons.md` — 교훈 기록
4. 그 다음 커밋 (코드 + .md 파일 함께)

**순서 이탈 패턴 주의**: 코드 작업 먼저 → .md 나중 → 빠뜨리기 쉬움. 항상 todo.md 먼저.

---

## iOS 백그라운드 BLE 패턴

**BG Task 만료 = BLE 끊김 → 신호 소실 오발 주의:**
- `UIBackgroundTask` expirationHandler가 호출될 때 iOS가 앱을 제한해 BLE 연결도 끊길 수 있음
- 이 끊김은 실제 신호 소실이 아니므로 잠금 실행 금지
- 해결: `isIntentionalDisconnect` 플래그를 expirationHandler에서 true로 설정 → `didDisconnectPeripheral`에서 체크

---

## 지오펜스 중복 콜백 패턴

**`registerGeofence()` 호출 시 중복 진입 이벤트 발생:**
- `requestState()` 콜백(`didDetermineState`)과 실제 진입 콜백(`didEnterRegion`)이 동시에 올 수 있음
- 동일 좌표 재등록 시 `didDetermineState`가 여러 번 호출됨
- 해결 1: 동일 좌표 재등록 방지 (`lastRegisteredLat/Lng` 비교)
- 해결 2: `fireEnterEvent()` 2초 디바운스로 중복 콜백 흡수

---

## iOS 백그라운드 앱 실행 유지 방법

**문제**: UIBackgroundTask는 ~30초 한계, 만료 후 앱 suspend → RSSI 폴링 타이머 멈춤

**해결**: `startUpdatingLocation()`으로 앱 suspend 차단
- `desiredAccuracy = kCLLocationAccuracyThreeKilometers`, `distanceFilter = 100` → 셀룰러 기지국 기반, GPS 칩 미사용, 배터리 절약
- `ThreeKilometers`로도 앱 생존 효과는 동일 (iOS가 "위치 사용 중" 앱으로 인식)
- BLE 신호 인식과 지오펜싱은 GPS accuracy와 무관 — 혼동하지 말 것
- 서비스 시작 시 활성화, 서비스 중지 시 반드시 비활성화 (`stopUpdatingLocation()`)
- 기존 지오펜스용 CLLocationManager를 공유해서 추가 인스턴스 없이 처리

**Android와의 차이**: Android ForegroundService처럼 항상 실행되는 공식 API가 iOS에 없음
→ startUpdatingLocation이 그나마 가장 신뢰성 있는 대안

---

## SwiftUI LogView 필터 바 레이아웃

**VStack + `if entries.isEmpty` 분기는 필터 바를 가린다:**
- `if-else`로 뷰 타입이 전환될 때 SwiftUI가 레이아웃을 재계산하면서 List가 VStack 전체를 차지
- `safeAreaInset(edge: .top)`도 실기기에서 기대대로 동작하지 않을 수 있음
- **해결**: List를 항상 고정 + 빈 상태는 `.overlay {}` 처리 → 뷰 타입 변환 없이 안정적

```swift
VStack(spacing: 0) {
    tagFilterBar  // 항상 최상단
    List(entries) { ... }
        .listStyle(.plain)
        .overlay {
            if entries.isEmpty { /* 빈 상태 UI */ }
        }
}
```

---

## 화이트박스 테스트 후 .md 갱신 필수

**커밋 전 반드시 순서 준수:**
1. 수정 완료 → `tasks/todo.md` 검토 섹션 추가 (완료 체크, 잔여 이슈 기록)
2. 교훈 → `tasks/lessons.md` 기록
3. 그 다음 커밋 (코드 + .md 함께)

**.md 갱신을 빠뜨리는 패턴**: 코드 수정에 집중하다 보고로 마무리하면 갱신 안 됨 → 코드 수정 직후 바로 .md 작성 습관 필요.

---

## CMMotionActivityManager 콜백 중복 방지

**문제**: `startActivityUpdates(to: .main)` 콜백이 짧은 시간에 수십 번 호출 → 각각 `Task { @MainActor }` 생성 → 큐에 쌓여서 모두 실행됨 (로그에서 51회 반복 관찰)

**해결**: Task 시작 시 `self.motionManager != nil` 체크로 이중 실행 차단. 첫 번째 Task에서 `motionManager = nil` 설정 → 이후 Task들은 guard에서 리턴:
```swift
Task { @MainActor in
    guard let self, self.motionManager != nil else { return }
    self.motionManager = nil
    manager.stopActivityUpdates()
    ...
}
```

---

## DispatchSourceTimer 재사용 시 반드시 cancel 먼저

**패턴**: `startXxx()` 함수에서 새 타이머를 만들기 전 기존 타이머 cancel 누락 → 타이머 누수
```swift
// 잘못된 패턴
private func startWatchdog() {
    let timer = DispatchSource.makeTimerSource(...)  // 기존 타이머 누수!
    ...
    watchdogTimer = timer
}

// 올바른 패턴
private func startWatchdog() {
    watchdogTimer?.cancel()  // 항상 먼저 취소
    let timer = DispatchSource.makeTimerSource(...)
    ...
    watchdogTimer = timer
}
```

---

## signalLossTimer 안전한 fire 조건 체크

**패턴**: DispatchSourceTimer의 이벤트 핸들러가 `Task { @MainActor }` 로 래핑될 때, cancel 후 Task가 큐에 남아 실행될 수 있음. 타이머 변수 자체가 nil인지 추가로 체크해야 함:
```swift
guard let self, self.signalLossTimer != nil, self.proximityState == .near else { return }
```

---

## 주행 중 BLE 신호 소실은 예외 처리 필요

**패턴**: 주행 중에는 BLE 신호가 자연스럽게 약해짐 → "차량 신호 끊김" 알림 불필요, 자동 잠금 불필요
- `handleSignalLoss()`에서 `isDriving` 체크로 알림/grace timer 스킵
- `evaluateProximity()`의 unlock 트리거에는 이미 `isDriving` 체크 있음

---

## lastKnownLocked로 중복 API 호출 차단

**문제**: BLE 20초 재연결 사이클마다 `isFirstRssiAfterConnect` → 접근/이탈 감지 → `triggerCarAction` 호출 → 내부에서 `lastKnownLocked` 체크로 스킵. 이 스킵 로그가 매 20초 무한 반복.

**해결**: `triggerCarAction` 호출 전 `evaluateProximity`/`processRSSI` 단계에서 미리 필터링:
```swift
// 이탈 감지 — 이미 잠긴 상태면 API 불필요
if storage.isAutoLockOnDeparture && lastKnownLocked != true {
    triggerCarAction(shouldUnlock: false, isManual: false)
}
// 접근 감지 — 이미 열린 상태면 API 불필요
if storage.isAutoUnlockOnApproach && !isDriving && !wasPredictive && lastKnownLocked != false {
    triggerCarAction(shouldUnlock: true, isManual: false)
}
// isFirstRssiAfterConnect — 이미 열린 상태면 proximityState만 변경
} else if lastKnownLocked == false {
    proximityState = .near  // API 호출 없이 상태만
}
```
- `lastKnownLocked == nil`(상태 모름)이면 조건을 통과해 API 호출 → 안전성 유지

---

## CryptoUtils throws 패턴

**빈 문자열 반환보다 throw가 안전:**
- `aesEncryptHex`/`aesDecryptUTF8` 실패 시 `""` 반환 → caller가 감지 불가 → 서버 오류로 느리게 전파됨
- throws로 변경 → 즉시 상위 caller로 전파, BydError로 통합됨
- `CryptoError` enum 별도 정의 (BydError와 분리 — actor 경계 없음)
- callers(postTokenSecure, login)는 이미 throws이므로 `try` 추가만으로 충분

---

## SQLite 에러 체크 패턴

**sqlite3 API는 에러를 무시하면 undefined behavior:**
- `sqlite3_open` 실패 시 `db = nil` → 이후 모든 API에 nil guard 추가
- `sqlite3_prepare_v2` 실패 시 bind/step 호출하면 crash 또는 데이터 오염
- 패턴: `guard sqlite3_prepare_v2(...) == SQLITE_OK else { return }` + `guard db != nil else { return }`

---

## NotificationManager 쿨다운 리셋 패턴

**신호 소실 알림 쿨다운은 신호 복구 시 리셋해야 함:**
- `lastSignalLostTime` 리셋 없이 60초 이내 재소실 시 두 번째 알림이 안 감
- `resetSignalLostCooldown()` 메서드를 추가하고 `processRSSI`에서 signalLossTimer 취소 시 호출

---

## 주행 종료 후 잠금 누락 패턴

**증상**: 주행 후 목적지 주차 → 차에서 내려도 자동 잠금 안 됨

**원인**: 지오펜스 이탈이 주행 종료 감지보다 먼저 발생
- 이탈 시점 → `isDriving = true`이므로 잠금 스킵
- 주행 종료 시점 → `isInsideGeofence = false`이므로 RSSI 폴링 없음 → 이탈 감지 불가
- 결과: 다음 GPS 폴링(5분)까지 잠금 불가

**해결**: `startDrivingDetection()`에서 주행 종료 시 지오펜스 외부이면 즉시 잠금 API 호출
```swift
if !driving && isGeofencingEnabled && !isInsideGeofence && isAutoLockOnDeparture {
    triggerCarAction(shouldUnlock: false, isManual: false)
}
```

---

## 로그 분석 선행의 중요성

**코드 분석만으로는 실제 발생 여부를 확인할 수 없음:**
- 정적 분석에서 찾은 버그 중 일부(stationaryTimer 중복 등)는 실제로는 이미 처리된 경우
- 로그를 먼저 확인하면 실제로 발생하는 버그에 집중할 수 있음
- 코드 분석 + 로그 분석을 함께 해야 우선순위가 명확해짐

---

## 에러 케이스 재사용 주의

**동일한 에러 타입이 다른 원인에서 사용되면 사용자에게 혼란스러운 문구가 표시됨:**
- `BydError.notLoggedIn`이 "세션 토큰 없음"과 "vehicleService nil(서비스 미시작)" 두 케이스에서 사용
- 서비스 미시작 상태에서 새로고침 → "로그인이 필요합니다" 표시 → 실제 원인과 다름
- 에러 케이스는 원인별로 분리하고 문구를 정확하게 매핑할 것

---

## 로그 공백 = 앱 suspend 지표

**Watchdog/Session 로그가 수 시간 공백이면 앱이 suspend된 것:**
- Watchdog은 5분, Session은 15분 주기 → 이 로그가 장시간 없으면 suspend 확인
- `startUpdatingLocation(ThreeKilometers)`는 suspend를 완전히 막지 못함
- 지오펜스 이벤트(CLRegionMonitoring)는 suspend 중에도 수신되어 앱을 깨우지만,
  그 사이 구간은 항상 로그 공백이 됨 (iOS 구조적 한계)
- 로그 분석 시 "로그가 없다"와 "suspend로 인한 공백"을 먼저 구분할 것

---

## SQLite 에러 체크는 원인 해결이 아님

**에러 체크 추가 ≠ 에러 방지:**
- `sqlite3_open` 실패 시 `db = nil` guard는 안전하게 처리하는 것이지, 실패 원인을 해결하는 게 아님
- `applicationSupportDirectory`는 `FileManager.urls(for:)`로 경로를 얻어도 실제 디렉토리가 존재함을 보장하지 않음
- SQLite DB 열기 전 반드시 `createDirectory(withIntermediateDirectories: true)` 먼저 호출할 것
- 화이트박스 테스트에서 에러 처리를 추가할 때 "왜 에러가 발생하는가"까지 분석해야 함

---

## BYD GPS API speed 신뢰 불가

**`gps.speed`는 실시간 값이 아님 — 주행 중에도 speed=0 반환:**
- BYD API GPS 응답의 speed 필드는 캐시된 값 → 주행 중에도 0으로 옴
- `gps.speed <= 5.0`으로 정지 여부 판단 → 주행 중에도 지오펜스 재등록하는 버그 발생
- 해결: CoreMotion `isDriving` 플래그를 기준으로 판단 (GPS speed는 사용하지 말 것)
- 주의: 신호등 등 속도 0인 경우도 있어 speed만으로 시동 꺼짐 판단 불가

---

## 비동기 재시도 후 상태 갱신 누락 패턴

**`try?` fire-and-forget 재시도 성공 여부와 상관없이 상태 갱신이 필요한 경우:**
- 자동 잠금 실패 → 45초 후 `try? await service.lockAuto()` 재시도
- 재시도 성공해도 `lastKnownLocked`가 이전 값으로 유지 → 다음 재연결 사이클에서 중복 API 호출
- 재시도 코드 작성 시 반드시 상태 갱신 라인 추가:
  ```swift
  try? await service.lockAuto(vin: vin, pin: pin)
  await MainActor.run { self.lastKnownLocked = true }  // 빠뜨리지 말 것
  ```

---

## guard 위치가 상태 업데이트보다 앞에 오면 안 되는 패턴

**상태 변수 업데이트는 early return 이전에 해야 하는 경우가 있음:**
- `guard isRunning, !isDriving else { return }` 이 `isInsideGeofence = true` 앞에 있으면
  → 주행 중 진입 이벤트 시 `isInsideGeofence`가 false로 유지됨
  → 이후 주행 종료 판단 시 "지오펜스 외부"로 오판 → 잘못된 자동 잠금 실행
- **원칙**: 조건에 따라 동작(BLE 재개 등)은 차단하되, 상태(isInsideGeofence)는 정확하게 반영해야 함
- **수정 패턴**:
  ```swift
  guard isRunning else { return }
  isInsideGeofence = true          // 상태는 먼저 업데이트
  guard !isDriving else { return } // 동작만 차단
  // BLE 재개 로직...
  ```

---

## rssiWindow BLE 사이클 간 클리어 → 예측 해제 불발 패턴

**증상**: 차에 접근해도 예측 사전 해제가 안 되고 `접근 감지`로만 해제됨 (1~3분 지연)

**원인**: ATTO 3 BLE가 20초마다 강제 끊김 → `handleSignalLoss()` → `rssiWindow.removeAll()`
→ 매 사이클 처음부터 RSSI 데이터 쌓기 → 20초 안에 `count >= 5` 못 채움 → 예측 조건 불충족

**해결**: `handleSignalLoss()`에서 `rssiWindow.removeAll()` 제거, 대신 시간 기반 필터링으로 교체
```swift
// processRSSI에서 count 기반 → 시간 기반
rssiWindow = rssiWindow.filter { now.timeIntervalSince($0.time) < Self.rssiWindowDuration }
// rssiWindowDuration = 60초
```
→ 여러 BLE 사이클에 걸쳐 데이터 누적 → `count >= 5` 빠르게 충족 → 예측 해제 활성화

**주의**: 이탈 후 낮은 RSSI 데이터가 window에 잔류하나, 재접근 시 기울기가 더 크게 계산돼 오히려 더 일찍 예측 해제됨 (오발 위험 아님)

---

## isStationary 상태에서 RSSI 폴링 재시작 버그

**증상**: `isStationary = true`로 BLE를 중단했는데도 RSSI 폴링이 다시 시작될 수 있음

**경로**: `stopBLEScan()` → `cancelPeripheralConnection()` → 비동기 `didDisconnectPeripheral` 콜백
→ `isRunning && isInsideGeofence`이면 `connect()` 재시도
→ 재연결 성공 → `didConnect()`에서 `isStationary` 체크 없이 RSSI 폴링 시작

**현황**: 배터리 낭비 수준의 영향, 심각하지 않아 미수정 상태로 남김
**수정 위치**: `didConnect()`에서 `guard !isStationary` 체크 추가하면 해결 가능

---

## iOS 백그라운드 BLE 스캔 차단 패턴

**`scanForPeripherals(withServices: nil)`은 백그라운드에서 차단됨 (iOS 7+ 공식 제한):**
- 서비스 UUID 없이 전체 스캔하면 앱이 백그라운드일 때 OS가 스캔 자체를 차단
- iOS 27 베타에서 이 제한이 더 엄격하게 적용되는 것으로 확인
- 로그 증상: `기기 탐색 스캔 시작`이 5분마다 반복되지만 `타겟 발견` 로그가 수 시간 동안 없음

**해결 패턴 (우선순위 순):**
1. `connectedPeripheral`이 있으면 → `connect()` (백그라운드 OK)
2. 저장된 UUID가 있으면 → `retrievePeripherals(withIdentifiers:)` → `connect()` (백그라운드 OK)
3. UUID 없으면 → `scanForPeripherals` (포그라운드 최초 연결 시에만 도달)

**peripheral 참조 유지 중요성:**
- `stopBLEScan()`에서 `connectedPeripheral = nil`을 하면 다음 `beginScanning()` 시 스캔 폴백으로 떨어짐
- `cancelPeripheralConnection()`은 하되 `connectedPeripheral = nil`은 하지 말 것 (서비스 완전 종료 시에만)
- peripheral UUID는 첫 `didDiscover`에서 `StorageManager`에 영구 저장할 것

---

## departureLockTimer 취소 누락 패턴

**신규 타이머 추가 시 반드시 취소해야 할 경로를 전부 체크할 것:**
- `handleSignalLoss()` — 신호 소실로 signalLossTimer 시작 시 departureLockTimer 동시 존재 → 중복 잠금
- `isDriving=true` 전환 시 — 주행 시작 후 타이머 만료 → 주행 중 자동 잠금 위험
- `stop()`, 접근 감지, 예측 접근 감지 경로에서도 취소

**체크리스트 (새 타이머 추가 시):**
1. 타이머 재생성 시 기존 cancel → `timer?.cancel()` 먼저
2. fire handler에서 `timer != nil` 체크 → Task 잔존 방지
3. 취소 경로: stop(), 목적 달성(반대 동작 감지), 상태 변경(isDriving, 신호소실) 모두 커버

---

## unlock 쿨다운으로 인한 이탈 잠금 차단 패턴

**증상**: unlock 직후 RSSI 급락(ATTO 3 BLE 특성) → 이탈 감지 → `unlock 쿨다운(30s)`에 차단 → 쿨다운 만료 후 재트리거 없음 → 잠금 미발동

**원인**: `triggerCarAction(shouldUnlock: false)` 내부에서 쿨다운 위반 시 그냥 `return` → 이탈이 기록되지 않고 사라짐

**해결**: 이탈 감지 시 쿨다운 잔여 시간을 계산 → `departureLockTimer`로 쿨다운 만료 후 잠금 예약
```swift
// evaluateProximity() 이탈 감지
let remaining = max(0, Self.postUnlockLockCooldown - Date().timeIntervalSince(lastAutoUnlockTime ?? .distantPast))
if remaining > 0 {
    scheduleDepartureLock(after: remaining)
} else {
    triggerCarAction(shouldUnlock: false, isManual: false)
}

// scheduleDepartureLock: 만료 시 proximityState == .far 재확인 후 실행
```

**타이머 취소 시점**: 접근 감지, 예측 접근 기울기 확인, stop() 호출

**화이트박스 주의점**: 예측 접근(`isPredictiveUnlockPending`) 경로에서도 취소 필요 — 접근 중인데 타이머 잔존하면 unlock 직후 잠금 발동 가능

---

## throws 추가 후 하위 오류 경로 누락 패턴

**에러를 throw로 변경했더라도 내부 단계별로 모두 커버됐는지 확인:**
- `aesDecryptUTF8`: AES 복호화 실패는 `throw` 처리했지만, 복호화 성공 후 UTF-8 디코딩 실패(`?? ""`)는 여전히 조용히 실패
- 패턴: `guard let result = ... else { throw Error }` — 중간 단계 변환 실패도 throw해야 함
- 빈 문자열 반환이 에러보다 나쁜 이유: 호출자가 성공으로 오해하고 잘못된 데이터로 진행

---

## 주행 중 지오펜스 반복 진입/이탈 패턴

**주행 중 지오펜스 재등록 → 현재 위치가 중심 → 바로 내부 감지:**
- 이동 중인 위치로 지오펜스를 재등록하면 해당 시점엔 내부, 이동 후엔 외부가 됨
- 로그 패턴: 지오펜스 등록 → 현재 상태: 내부 → 수십 초 후 이탈 → 반복
- 해결: `pollVehicleGPS()`에서 `!isDriving` 조건으로 주행 중 재등록 차단
- 해결: `didEnterGeofence()`에서 `guard !isDriving` 추가 (혹시 남은 콜백 무시)

---

