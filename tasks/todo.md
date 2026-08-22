# 코드/로그 검수 후 수정 계획

## BLE 직접 차량 제어 포팅 (계획 단계, 2026-08-22)

**상세 계획**: [tasks/ble_direct_control_plan.md](./ble_direct_control_plan.md)
**참고 원본**: [PoorGrammerA/BydBleAutoLock](https://github.com/PoorGrammerA/BydBleAutoLock) — 한국 dkey + ATTO 3에서만 검증된 PoC

**목표**: 현재 "BLE RSSI 근접감지 + REST API 제어" 구조에 "BLE GATT 직접 인증/제어, 실패 시 REST 폴백" 경로 추가. 기존 RSSI/쿨다운/예측해제 로직은 손대지 않음.

- [ ] Phase 0 — 선행 조사 (실기기 QR 승인 흐름 재현, 서버 스펙 최신성 확인)
- [x] Phase 1 — Watch 자격증명 프로비저닝 REST 클라이언트 (`BydWatchKeyService`, QR UI) — 구현 완료, **빌드/실기기 미검증** (아래 검토 참고)
- [x] Phase 2 — 암호화 프리미티브 (`BleCrypto`: SHA-256/AES-CBC-NoPadding/AES-CMAC/CRC8) — 구현 + **독립 Python 재구현으로 알고리즘 검증 완료** (아래 검토 참고)
- [x] Phase 3 — BLE 프레임 코덱 (`BleCodec`) — 구현 + 원본 테스트 벡터 전부 이식 + 알고리즘 검증 완료
- [x] Phase 4 — 수신 프레임 조립기 (`BleFrameAssembler`) — 방어적 최소 구현 완료 (아래 참고)
- [ ] Phase 5 — GATT 연결/인증 세션 오케스트레이션 (`BleVehicleAuthSession`, 기존 `didConnect()` 재사용)
- [ ] Phase 6 — `triggerCarAction()`에 BLE 우선 경로 통합 (feature flag)
- [ ] Phase 7 — UI/설정 (토글, QR 프로비저닝 화면)
- [ ] Phase 8 — 검증 (유닛 테스트 + 실기기 체크리스트)
- [ ] Phase 9 — 문서/크레딧/lessons.md 기록

**미해결 질문(실기기 확인 전까지 답 추정 금지)**: 보유 차종 호환성, advertisement에 Service UUID 노출 여부, write-with/without-response, QR 승인 매번 필요 여부, 서버 API 최신성 — 상세는 계획 문서 §6 참조.

### Phase 1 구현 결과 (2026-08-22)

- [x] `BydAutoLock/API/BydWatchKeyService.swift` 신규 — actor, 5개 엔드포인트(`createQrCode`/`getQrCodeStatus`/`getToken`/`getVehicleConfig`/`getWatchBlueInfo`) + `syncServerTime`/`buildQrCodeContent`/`extractBleInfo` 정적 헬퍼
- [x] `BydAutoLock/Views/WatchProvisioningView.swift` 신규 — QR 표시(CIFilter) → 2초 폴링 → token/vehicle/bluetooth 순차 호출 → Storage 저장
- [x] `BydAutoLock/Storage/StorageManager.swift` — Watch 토큰/dkey(Keychain) + 페어링 상태/BLE 정보(UserDefaults) 필드 추가, `hasBleDkey`/`clearWatchCredentials()` 추가
- [x] `BydAutoLock/Views/BluetoothSettingsView.swift` — "BLE 직접 제어 등록" 진입점(Section) + `.sheet`로 `WatchProvisioningView` 연결
- [x] `BydAutoLockTests/BydWatchKeyServiceTests.swift` — QR 콘텐츠 왕복 검증(암호화→복호화 평문 일치), `extractBleInfo` 3가지 경로(정상/`cfVechicle` 중첩/누락) 검증
- [x] Watch 계정용 원격제어 엔드포인트(`watch/control/*`)는 계획대로 스코프 제외 — 메인 계정으로 이미 REST 제어 가능

**⚠️ 미검증 — 다음 작업 시 반드시 확인**:
- 이 세션(Windows)에는 Xcode/swift 툴체인이 없어 `xcodegen generate` / `xcodebuild` / `xcodebuild test`를 실행하지 못했다. 코드는 원본 Java 소스를 원문 대조하며 작성했고, 정적으로 재검토했지만 **실제 빌드 확인은 못 했다.**
- Mac에서 반드시: `xcodegen generate` → `BydAutoLockTests` 빌드+실행(`BydWatchKeyServiceTests` 통과 확인) → 실기기에서 QR 생성/승인/dkey 획득까지 1회 실행.
- Phase 0(실기기 조사)과 Phase 1의 실기기 검증(§검증 3번)은 아직 아무것도 확인되지 않은 상태.

### Phase 2 + 3 구현 결과 (2026-08-22)

- [x] `BydAutoLock/API/BleCrypto.swift` 신규 — `crc8`, `randomBytes`(SecRandomCopyBytes), `sha256`(CryptoKit), `aesCbcEncryptNoPadding`, `aesCmac`(RFC4493, CommonCrypto AES-ECB 기반)
- [x] `BydAutoLock/API/BleCodec.swift` 신규 — GATT UUID 3개, wake/random-exchange/auth/control 프레임 생성, 응답 파싱, `functionId → controlCode` 매핑. **원본과 차이**: 세션 상태(appRandom/sessionIv/aesKey/cmacKey)를 Java의 `static`에서 인스턴스 프로퍼티로 변경 — 계획에서 결정한 대로.
- [x] `BydAutoLockTests/BleCryptoTests.swift`, `BleCodecTests.swift` 신규 — 원본 `BydBleCodecVectorTest.java`/`BydPureJavaCodecTest.java`의 **모든 테스트 벡터를 그대로 이식** (RFC4493 CMAC, CRC8, wake/random/auth 프레임 전체 와이어 값, functionId 매핑, GATT UUID)
- [x] **독립 재구현 검증**: Swift와 별개로 Python(pycryptodome)으로 CRC8/AES-CMAC/SHA256 세션키파생/프레임조립 로직을 처음부터 다시 구현해서 같은 원본 테스트 벡터 9개 전부와 대조 — **전부 일치 확인.** (Windows 환경엔 Xcode가 없어 Swift 자체를 실행할 수 없으므로, 알고리즘이 맞는지를 실행 가능한 방법으로 확인한 것 — Swift 문법 컴파일 여부와는 별개 검증임)

### Phase 4 관련 발견 — 보류 이유

원본 Android 저장소에는 두 개의 서로 다른 BLE 구현이 존재한다:
- `com.poorgrammera.bydblekeycontrol.blecodec.*` (`BydBleCodec`/`BydBleCrypto`) — **한국 dkey + ATTO 3에서 검증된, 테스트 벡터가 있는 경로.** Phase 2/3가 포팅한 것이 이것.
- `com.poorgrammera.bydautolock.service.*` (`WatchStyleBleFrameAssembler`/`BydWatchStyleBleManager`/`BleVehicleAuthSession` 등) — "Watch-style" 이라는 별도 패키지의 다른 구현. `WatchStyleBleFrameAssembler`의 헤더 상수(`HEADER_A`/`HEADER_B`)를 디코딩해보면 `0x5AA5`/`0x5BB5` — 이건 **우리가 보내는 프레임의 헤더**(wake/random-exchange, 암호화 프레임)이지, `BydBleCodec`가 파싱하는 **차량 응답의 첫 바이트**(`0x2A`/`0x2B`/`0x24`)가 아니다.

즉 `WatchStyleBleFrameAssembler`가 검증된 `BydBleCodec` 경로에서 실제로 쓰이는 컴포넌트인지 확인되지 않았다 — 다른 인증 방식(예: 다른 지역의 dkey 프로토콜)을 위한 별개 구현일 가능성이 있다. 확인 없이 그대로 포팅하면 실제로는 안 맞는 프레이밍 로직을 들여오는 위험이 있어 보류했다.

**대안**: CoreBluetooth의 GATT notify는 TCP 스트림과 달리 "한 번의 `didUpdateValueFor` = 한 번에 보낸 값 전체"가 기본 시맨틱이라, 차량이 매번 정확히 20바이트를 한 프레임으로 notify한다면 별도 조립 로직 없이 `characteristic.value`를 그대로 `BleCodec`에 넘기면 될 가능성이 높다. Phase 5(GATT 세션)에서 방어적으로 최소한의 길이/경계 체크만 추가하고, "여러 프레임이 한 notify에 합쳐져 오는지" 여부는 실기기 로그로 확인 후 필요하면 그때 조립기를 추가하는 방향을 제안한다.

### Phase 4 구현 결과 (2026-08-22)

사용자가 "방어적인 최소 조립기를 지금 만들기"를 선택 — `WatchStyleBleFrameAssembler`를 포팅하지 않고, 원본과 무관한 **새 설계**로 구현:

- [x] `BydAutoLock/Service/BleFrameAssembler.swift` 신규 — Android의 12000바이트 원형버퍼 대신 단순 `[UInt8]` 버퍼. 프레임 경계는 고정 길이 대신 **`F5 FA` 종단 마커 스캔**으로 찾음 (앱이 보내는 프레임에서 확인된 유일하게 일관된 신호). 200바이트 초과 시 오염된 것으로 보고 버퍼 초기화. `append([UInt8])`/`append(Data)` 두 오버로드 + `reset()`.
- [x] `BydAutoLockTests/BleFrameAssemblerTests.swift` — 완전한 프레임 1개/연속 2개/두 notify로 분할/다음 프레임 조각 보존/오버플로우 복구/`reset()` 격리 총 7개 케이스
- [x] **독립 검증**: Swift와 별개로 Python으로 같은 조립 알고리즘을 재구현해서 7개 테스트 케이스 전부 대조 — 전부 일치. 이 과정에서 직접 작성한 테스트 하나(`testResetDropsBufferedPartialFrame`)의 **기대값 자체가 잘못 계산된 걸 발견**해서 수정함 (아래 lessons.md 참고).
- [x] "차량 응답이 정말 F5FA로 끝나는지"는 실기기 미확인 — 파일 상단 doc comment에 명시, Phase 8에서 재확인 필요.

---

## 재연결 즉시 unlock 오발동 수정 (2026-08-19)

**증상**: 로그에서 이중 unlock (예측 해제 + 재연결 즉시 unlock 동시), lock 후 55초 뒤 재연결로 즉시 열림
- [x] P1-1: 재연결 즉시 unlock 경로에 `isPredictiveUnlockPending` 체크 추가
- [x] P1-2: `lastKnownLocked == nil` (상태 불명)인 경우에만 즉시 unlock 허용. `true`이면 EMA 경로 위임
- [x] 화이트박스 검토 — 6개 시나리오 모두 정상
- [x] lessons.md 업데이트

---

## 화이트박스 테스트 수정 (2026-08-19)

- [x] P0-1: `static let signalLossGracePeriod` Dead Code 제거
- [x] P0-2: `static let predictiveMinSlope` Dead Code 제거
- [x] P1-1: `stop()`에 `isInsideGeofence = false` 추가
- [x] P1-2: `scheduleVerifyAndNotify` 최종 실패 시 `lastKnownLocked = nil` 리셋
- [x] P1-3: `.poweredOn` 핸들러에서 `isStationary=true`이면 `startStationaryTimer()` 스킵
- [x] P2-3: `sendLowBattery` 사운드 `.default`로 수정
- [x] lessons.md 업데이트

---

## 주행 중 지오펜스 진입 시 BLE 재개 누락 버그 수정 (2026-08-19)

**증상**: 가까이 가도 안 열리고 멀어져도 안 잠김 (ATTO 3 로그 분석)
**원인**: 주행 중 지오펜스 진입 → `isDriving=true`로 BLE 재개 차단 → 주행 종료 시 BLE 재개 복구 경로 없음

- [x] `AutoLockService.swift` 주행 종료 핸들러에 `isInsideGeofence=true` 케이스 추가
  - 주행 종료 + 지오펜스 내부 → 즉시 BLE 재개 (기존에는 pollVehicleGPS → registerGeofence → didEnterGeofence 재호출까지 대기)
- [x] 화이트박스 테스트 — beginRssiPollingBGTask(guard), startRssiTimer(cancel 후 재시작), beginScanning(연결 중이면 스킵) 모두 안전
- [x] lessons.md 업데이트

---

## SEALION 7 차종별 파라미터 조정 (2026-08-18)

- [x] `makeProfile(for:)` SEALION 7 파라미터 조정
  - `signalLossGracePeriod`: 60 → 90초 (BLE 재연결 불규칙, 잘못된 잠금 방지)
  - `predictiveMinSlope`: 0.5 → 0.8 (기울기 최대 2.7 dBm/s, 노이즈 필터링 강화)
  - `rssiWindowDuration`: 60 유지
- [x] ATTO 3 파라미터 — 기울기 최대 2.0 dBm/s, 기본값(0.5) 유지 (충분)
- [x] 빌드 확인 — 상수값 변경만, 컴파일 에러 없음
- [x] lessons.md 업데이트

---

## 분석 근거
- 코드 정적 분석 (3개 서브에이전트)
- 실제 로그 분석: byd_log_20260626_093153, byd_log_20260626_093647

---

## P1 - 로그에서 명확히 재현된 버그

- [x] **1. BG Task 종료 → 신호 소실 잠금 오발 방지**
- [x] **2. 지오펜스 중복 진입 이벤트 수정**

---

## P2 - 코드 분석에서 확인된 버그

- [x] **3. stationaryTimer 중복 생성 방지** — 실제 중복 없음, 수정 불필요

---

## 자동 잠금/해제 검증 기능 (A+B) — 완료

- [x] NotificationManager — sendLockFailed 추가
- [x] AutoLockService — scheduleVerifyAndNotify 추가
- [x] 빌드 확인 / lessons.md 업데이트

---

## Siri App Intents 추가

**배경**: 트렁크 제어 + 양손에 짐을 든 상황 → 음성 제어 필요

### 구현 계획

- [x] **Step 1: AutoLockService — 트렁크 수동 제어 함수 추가**
  - `manualOpenTrunk()`, `manualCloseTrunk()` (UI 버튼용)

- [x] **Step 2: BydAutoLock/Intents/BydAppIntents.swift 생성**
  - Intent 목록: 잠금, 잠금 해제, 트렁크 열기, 트렁크 닫기, 에어컨 켜기, 에어컨 끄기
  - 각 Intent 내부에서 StorageManager + BydVehicleService로 독립 API 호출
  - 세션 만료 시 자격증명으로 자동 재로그인 (setCredentials 활용)
  - AppShortcutsProvider (iOS 16.4+) — Siri 자동 제안 등록

- [x] **Step 3: MainView — 트렁크 버튼 추가**
  - 수동 제어 카드에 트렁크 열기/닫기 버튼 추가

- [x] **Step 4: xcodegen generate + 빌드 확인**

- [x] **Step 5: lessons.md 교훈 기록**

---

## 검토 (완료 후 작성)

### Siri App Intents 작업 결과
- `BydAppIntents.swift` 신규 생성 — 6개 Intent + BydShortcutsProvider
- `BydVehicleService`가 actor라 `makeServiceContext()`를 `async`로 선언 필요 (빌드 에러 수정)
- `AppShortcutsProvider` phrases 전부 `\(.applicationName)` 포함 필수 (빌드 에러 수정)
- `MainView.swift` quickActionsCard에 트렁크 열기/닫기 버튼 행 추가 (sed 오류 → Edit 수정)
- `project.yml` 버전 1.5.5 → 1.5.6, build 18 → 19 동기화
- 빌드 성공 확인
