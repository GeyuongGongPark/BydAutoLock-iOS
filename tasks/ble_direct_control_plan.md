# BLE 직접 차량 제어 포팅 계획

**작성일**: 2026-08-22
**참고 원본**: [PoorGrammerA/BydBleAutoLock](https://github.com/PoorGrammerA/BydBleAutoLock) (MIT License, Android, 순수 Java BLE 코덱 PoC)
**검증 범위 주의**: 원본 저장소는 "한국 dkey 경로 + BYD ATTO 3" 조합에서만 검증됨. 다른 차종/지역은 원본도 미검증.

---

## 1. 배경 및 목표

### 현재 아키텍처 (변경하지 않음)
`AutoLockService.swift`는 BLE를 **근접 감지(RSSI 비콘)** 용도로만 쓴다. 차량과 GATT로 연결은 하지만(`discoverServices` 없음), 실제 잠금/해제는 100% REST API(`BydVehicleService.sendRemoteControl`, `commandType: "LOCKDOOR"/"OPENDOOR"`)로 나간다.

### 목표
차량과 BLE GATT로 직접 연결해 wake-up → 난수교환 → dkey 인증 → 암호화 제어 프레임을 주고받는 경로를 **추가**한다. 원본 프로젝트가 표방한 대로 "BLE 우선 제어, REST 대체"로 만든다 — REST 경로는 절대 제거하지 않고 폴백으로 유지한다.

### 핵심 원칙 (CLAUDE.md 최소 영향 원칙 적용)
- `AutoLockService`의 RSSI 필터링/쿨다운/예측해제 로직은 **절대 손대지 않는다**. `tasks/lessons.md`에 기록된 수십 개의 버그 픽스가 쌓여있는 코드다.
- 신규 기능은 완전히 격리된 새 클래스들로 만들고, `triggerCarAction()` 안에 "BLE 시도 → 실패/타임아웃 시 REST 폴백" 형태로만 끼워 넣는다.
- `StorageManager.isBleDirectControlEnabled` 같은 feature flag로 기본값 **off** — 문제 생기면 즉시 REST-only로 되돌릴 수 있게.

---

## 2. 가장 큰 리스크: dkey를 얻는 경로 자체가 없다

조사 결과, 이 앱이 쓰는 로그인(`app/account/login`, `signToken`/`encryToken`)과 원본이 dkey를 얻는 `watch/login/*` API는 **완전히 별도의 인증 도메인**이다. 지금 로그인 세션으로는 dkey를 얻을 수 없다.

원본의 Watch API 6단계 흐름 (전부 신규 구현 필요):

| 단계 | 엔드포인트 | 인증 |
|---|---|---|
| 서버 시간 | `watch/login/getServerCurrentTime` | countryCode만 |
| QR 생성 | `watch/login/create/qrcode` | countryCode만 |
| QR 상태확인 | `watch/login/check/qrcode` | countryCode만 (`codeStatus==2`까지 폴링) |
| 토큰 획득 | `watch/login/gain/token` | countryCode만 |
| 차량정보 획득 (BLE MAC, dkey, 지원기능) | `watch/login/gain/vehicle` | watch encryToken |
| 블루투스키 획득 (dkey/keyNumber 갱신) | `watch/login/gain/bluetooth` | watch encryToken |

**QR은 사용자가 공식 BYD 앱에서 직접 승인해야 한다.** 즉 이 기능은 "설정 한 번 켜면 끝"이 아니라 신규 온보딩 UX(QR 표시 → 공식 앱으로 승인 → 폴링 대기)가 필요하다.

---

## 3. Phase별 계획

### Phase 0 — 선행 조사 (코드 작성 전 필수)
- [ ] 실기기에서 공식 BYD 앱으로 QR 승인 흐름을 1회 수동 실행해보고, 이 코드가 최신 서버 스펙과 여전히 맞는지 확인 (원본 저장소가 오래됐으면 서버가 바뀌었을 수 있음)
- [ ] 로그인된 계정으로 QR 승인이 매번 필요한지, 1회만 필요한지 확인
- [ ] feature flag 이름/기본값 확정

### Phase 1 — Watch 자격증명 프로비저닝 (REST)
- [ ] `BydWatchKeyService.swift` 신규 — 위 6개 + 원격제어/상태조회 엔드포인트 매핑 (`BydVehicleService`와 별도 클래스. 인증 도메인이 다르므로 억지로 합치지 않음)
- [ ] QR 표시 UI 신규 (`CIFilter.qrCodeGenerator`로 생성)
- [ ] `codeStatus==2`까지 QR 상태 폴링
- [ ] `gain/token` → `gain/vehicle` → `gain/bluetooth` 순차 호출, dkey/keyNumber/BLE 정보 저장
- [ ] `StorageManager` Keychain 확장: `bleDkey`, `bleKeyNumber`, `watchEncryToken`, `watchSignToken`, `watchVin` (기존 `KC` enum 패턴 그대로 따름)
- [ ] mock 응답으로 각 단계 파싱 단위 테스트

### Phase 2 — 암호화 프리미티브
- [ ] `BleCrypto.swift` 신규 (REST용 `CryptoUtils`와 분리 — 용도가 다름)
  - `sha256` (CryptoKit)
  - `aesCbcEncryptNoPadding` (CommonCrypto)
  - `aesCmac` — RFC 4493 수동 구현 (CryptoKit에 CMAC 없음)
  - `crc8` (polynomial 0x07)
- [ ] 알려진 테스트 벡터로 검증 (아래 §5)

### Phase 3 — BLE 프레임 코덱
- [ ] `BleCodec.swift` — Java `BydBleCodec.java` 1:1 포팅
  - UUID 3개: Service `42594420-4155-544F-E0A9-E50E24DCCA9E`, Send `42590002-...`, Receive `42590003-...`
  - `createWakeUpFrame` / `createRandomExchangeFrame` / `createAuthenticationFrame` / `createControlFrame` / `parseRandomExchange` / `parseAuthenticationResult` / `parseControlXxx`
  - `functionId → controlCode` 매핑 (9001=0x05 unlock, 9002=0x07 lock, 9015/9011=0x06 트렁크, 9010=0x16 라이트, 9005=0x0A 라이트+경적 등)
- [ ] **Java와 다르게**: 원본은 세션 키(`appRandom`/`sessionIv`/`aesKey`/`cmacKey`)를 `static`으로 들고 있다 (Android 코드 특성상 싱글턴). Swift에선 세션 인스턴스 프로퍼티로 만들어 동시 세션/재시도 시 상태 오염을 원천 차단한다.
- [ ] Vector 테스트로 정확성 확증

### Phase 4 — 수신 프레임 조립기
- [ ] `BleFrameAssembler.swift` — 20바이트 프레임(헤더 2 + 페이로드 16 + CRC8 1 + 테일 2) 경계 검출
- [ ] 원본은 12000바이트 원형 버퍼(Android GC 회피 최적화)를 쓰지만, Swift/iOS에선 불필요한 오버엔지니어링 → 단순 `Data` append/prefix로 대체

### Phase 5 — GATT 연결 및 인증 세션
- [ ] **기존 `AutoLockService.didConnect()`에서 이미 만들어진 `CBPeripheral` GATT 연결을 그대로 재사용** — 별도 연결을 새로 만들지 않는다
- [ ] `discoverServices([serviceUUID])` → `didDiscoverServices` → `discoverCharacteristics([sendUUID, receiveUUID])` → `setNotifyValue(true, for: receiveCharacteristic)`
- [ ] `BleVehicleAuthSession.swift` — 상태머신 `idle → running → randomExchangeOK → authOK → authPass / failed` (원본의 200ms/180ms 지연은 우선 동일 적용, 실기기 테스트 후 튜닝)
- [ ] 컨트롤 프레임 전송 후 최대 3초 응답 대기 → 타임아웃 시 실패 처리 (원본과 동일한 성공 판정 기준)

### Phase 6 — 기존 트리거 로직과 통합
- [ ] `triggerCarAction()`에 feature flag on + `authPass` 상태일 때만 BLE 경로 삽입: BLE 프레임 전송 시도 → 3초 내 응답 오면 성공 처리(REST 스킵) → 실패/타임아웃이면 기존 REST 경로로 그대로 폴백
- [ ] `lastKnownLocked` 갱신, `scheduleVerifyAndNotify` 등 기존 검증 로직과의 관계 재검토 (BLE 응답 자체가 이미 실차 확인이므로 REST 폴링 검증을 스킵할지는 Open Question)

### Phase 7 — UI/설정
- [ ] `BluetoothSettingsView`에 "BLE 직접 제어" 토글 + 프로비저닝 상태 표시
- [ ] QR 프로비저닝 화면 신규
- [ ] `LogView` 태그 추가 (예: `"BLE-Ctrl"`)

### Phase 8 — 검증 (완료 전 필수, CLAUDE.md 4번 원칙)
- [ ] 유닛 테스트: crypto vector, codec vector, functionId 매핑 전부 통과
- [ ] 시뮬레이터는 BLE 미지원 → 파싱/암호화 로직은 단위 테스트로, 실제 송수신은 실기기로만 확인
- [ ] 실기기 체크리스트: wake-up 응답 수신 → random exchange 성공 → `authPass` 도달 → lock/unlock 프레임 전송 후 실차 반응 확인 → BLE 실패를 강제로 유발해 REST 폴백이 정상 동작하는지 확인
- [ ] "무응답을 성공으로 착각" 금지 — lessons.md의 `try?` 무조건 상태갱신 금지 원칙을 여기도 동일하게 적용 (응답 프레임 검증 성공시에만 `lastKnownLocked` 갱신)

### Phase 9 — 문서/교훈
- [ ] README.md/COMMUNITY_POST.md에 BydBleAutoLock 출처 크레딧 추가
- [ ] 실기기 테스트 결과를 `lessons.md`에 기록
- [ ] `todo.md` 체크리스트 갱신

---

## 4. 예상 신규/수정 파일

**신규**
- `BydAutoLock/API/BydWatchKeyService.swift`
- `BydAutoLock/API/BleCrypto.swift`
- `BydAutoLock/API/BleCodec.swift`
- `BydAutoLock/Service/BleFrameAssembler.swift`
- `BydAutoLock/Service/BleVehicleAuthSession.swift`
- `BydAutoLock/Views/WatchProvisioningView.swift` (QR 표시/승인 대기)
- `BydAutoLockTests/BleCodecTests.swift`, `BleCryptoTests.swift`

**수정**
- `BydAutoLock/Service/AutoLockService.swift` — `didConnect()`에 `discoverServices` 추가, `triggerCarAction()`에 BLE 우선 경로 삽입, `CBPeripheralDelegate` 확장(`didDiscoverServices`/`didDiscoverCharacteristicsFor`/`didUpdateValueFor`/`didWriteValueFor`)
- `BydAutoLock/Storage/StorageManager.swift` — dkey 등 Keychain 필드 추가, feature flag
- `BydAutoLock/Views/BluetoothSettingsView.swift` — 토글/상태 UI
- `README.md`, `COMMUNITY_POST.md` — 크레딧 추가

---

## 5. 알려진 테스트 벡터 (Swift 포팅 후 그대로 XCTest로 이식)

**RFC 4493 AES-CMAC (빈 메시지)**
```
key    = 2B7E151628AED2A6ABF7158809CF4F3C
message = "" (길이 0)
MAC    = BB1D6929E95937287FA37D129B756746
```

**BydBleCodec 프레임 벡터** (`BydBleCodecVectorTest.java` 원본)
```
dkey        = 00112233445566778899AABBCCDDEEFF
appRandom   = 1020304050607080
vehicleRandom(응답 payload "2AD601 1122334455667788 01 ...") = 1122334455667788

createRandomExchangeFrame(keyNumber=0, appRandom) 결과:
  5AA5D6 1020304050607080 00 FFFFFFFFFF 3C F5FA   (20바이트)

createAuthenticationFrame(dkey) 결과 (위 vehicleRandom/appRandom 세션 기준):
  5BB5 0396C4727C202D50B06A0477CF412BE F5FA        (20바이트)
```

**GATT UUID**
```
Service:  42594420-4155-544F-E0A9-E50E24DCCA9E
Send:     42590002-4155-544F-E0A9-E50E24DCCA9E
Receive:  42590003-4155-544F-E0A9-E50E24DCCA9E
```

이 벡터들이 Swift 포팅 결과와 바이트 단위로 일치해야 Phase 3가 완료된 것으로 본다. 실차 없이도 이 단계까지는 100% 검증 가능하다.

---

## 6. Open Questions (실기기/실환경에서만 확인 가능 — 미리 답을 추정하지 말 것)

1. 사용자 보유 차종(ATTO 3 / SEALION 7)에서 이 프로토콜이 동일하게 동작하는가? 원본은 ATTO 3 + 한국 dkey만 검증됨.
2. 차량이 advertisement 패킷에 Service UUID(`4259...`)를 노출하는가? 노출된다면 `scanForPeripherals(withServices:)`로 필터링 스캔 전환 가능 — `lessons.md`에 기록된 "백그라운드 스캔 차단" 문제를 개선할 기회.
3. Send characteristic의 write 속성이 with-response인지 without-response인지.
4. 이미 로그인된 계정으로 Watch QR 승인이 자동으로 되는지, 매번 공식 앱을 열어야 하는지.
5. 원본이 리버싱한 이 `watch/*` API를 BYD 서버가 지금도 동일하게 지원하는지 (원본 저장소가 이미 구식일 가능성).

---

## 7. 리스크와 완화

| 리스크 | 완화 |
|---|---|
| 서버측 API 변경/차단 | REST 폴백 유지로 완전 회귀 가능 |
| 오작동(문이 안 열림/잘못 잠김) | feature flag 기본값 off, 명시적 opt-in, 3초 타임아웃 후 반드시 REST 폴백 |
| 안정화된 RSSI 로직 훼손 | 신규 클래스로 완전 격리, 기존 코드는 `triggerCarAction()` 진입점 한 곳만 수정 |
| Watch API 별도 인증 도메인 관리 복잡도 증가 | `BydVehicleService`와 별도 클래스로 명확히 분리, 혼용하지 않음 |
