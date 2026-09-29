# homebridge-byd 플러그인 개발 계획

## 목표
BYD 차량을 Apple HomeKit에 연동하는 Homebridge 플러그인 개발.
홈 앱 대시보드에서 차량 상태 확인 및 위치 기반 자동화 지원.

## 레포지토리
별도 레포: `homebridge-byd`
npm 패키지명: `homebridge-byd`

---

## 기술 스택

- **언어**: TypeScript
- **런타임**: Node.js 18+
- **프레임워크**: homebridge (HAP-NodeJS 기반)
- **암호화**: node:crypto (AES-128-CBC, MD5, SHA1)
- **BangcleCodec**: bangcle_tables.bin 재사용 (iOS 앱 번들에서 추출)

---

## 레포 구조

```
homebridge-byd/
  src/
    lib/
      BangcleCodec.ts      # iOS BangcleCodec.swift 포팅
      CryptoUtils.ts       # iOS CryptoUtils.swift 포팅
      BydApiClient.ts      # iOS BydVehicleService.swift 포팅
    accessories/
      LockAccessory.ts     # 도어 잠금/해제
      ClimateAccessory.ts  # 에어컨 Thermostat (ON/OFF + 온도 설정)
      BatteryAccessory.ts  # 배터리 잔량 (정보성)
    platform.ts            # Homebridge Platform 진입점
    index.ts               # 플러그인 등록
  assets/
    bangcle_tables.bin     # iOS 앱 번들에서 복사
  config.schema.json       # Homebridge UI 설정 스키마
  package.json
  tsconfig.json
```

---

## HomeKit 액세서리 매핑

| 액세서리 | HomeKit 서비스 | BYD 명령 | 홈 앱 표시 |
|---------|--------------|---------|----------|
| 도어 잠금 | LockMechanism | LOCKDOOR / OPENDOOR | 잠김/열림 |
| 에어컨 | Thermostat | OPENAIR / CLOSEAIR | ON/OFF + 온도 설정 |
| 배터리 | Battery | 상태 조회 (soc) | % 표시 |
| 트렁크 | Switch | OPENTRUNK / CLOSETRUNK | ON/OFF |

---

## config.schema.json 설정 항목

```json
{
  "username": "BYD 앱 계정 이메일",
  "password": "BYD 앱 계정 비밀번호",
  "pin": "차량 제어 비밀번호 (4자리)",
  "vin": "차량 VIN 번호",
  "region": "KR / EU / JP 등",
  "pollInterval": 60,         // 상태 폴링 간격 (초), 기본 60
  "acDuration": 15            // 에어컨 작동 시간 (분): 10 / 15 / 20 / 25 / 30 중 선택
}
```

---

## 포팅 핵심 과제 및 주의사항

### 1. BangcleCodec (최우선, 가장 복잡)
- 커스텀 AES CBC 변형 — 표준 암호화 라이브러리 사용 불가
- `bangcle_tables.bin`을 `fs.readFileSync`로 읽어 동일하게 사용
- encodeEnvelope / decodeEnvelope 동작이 Swift와 정확히 일치해야 함
- 검증: iOS 앱과 동일한 입력 → 동일한 출력 비교 테스트

### 2. CryptoUtils
- `md5Hex`: **반드시 UPPERCASE 반환** (lowercase면 서버 sign 검증 3002 에러)
- `sha1Mixed`: SHA1 후 홀수 인덱스 대문자, 짝수 인덱스 소문자 혼합 → 짝수 위치 '0' 제거
- `computeCheckcode`: MD5 결과를 [24:32] + [8:16] + [16:24] + [0:8] 순서로 재조합
- `aesEncryptHex`: AES-128-CBC, Zero IV, PKCS7 패딩, 결과는 UPPERCASE hex
- `aesDecryptUTF8`: 위 역방향
- `buildSignString`: 키 알파벳 오름차순 정렬 → `key=value&...&password=...`

### 3. BydApiClient
- 로그인: `/app/account/login` — pwdLoginKey = md5(md5(password))
- 차량 목록: `/app/account/getAllListByUserId`
- 차량 상태: Request → 1.5s 대기 → Result 최대 5회 폴링 (2s 간격)
  - `/vehicleInfo/vehicle/vehicleRealTimeRequest`
  - `/vehicleInfo/vehicle/vehicleRealTimeResult`
- HVAC 상태: `/control/getStatusNow`
- 원격 제어: Request → 2s 대기 → Result 최대 10회 폴링
  - `/control/remoteControl`
  - `/control/remoteControlResult`
- 세션 만료 코드: 1002, 1005, 1010 → 자동 재로그인 후 재시도
- 재로그인 중 재진입 방지: `isRelogging` 플래그

### 4. 폴링 전략
- 상태 폴링은 차량 tbox 호출 비용이 있으므로 너무 짧으면 안 됨
- 기본 60초 권장, 최소 30초로 제한
- Homebridge 재시작 시 즉시 1회 조회

---

## 개발 단계

### Phase 1 — BYD API 레이어
- [ ] 레포 초기화 (TypeScript + Homebridge 플러그인 템플릿)
- [ ] `bangcle_tables.bin` iOS 앱 번들에서 추출 → assets/에 복사
- [ ] `BangcleCodec.ts` 포팅
- [ ] `CryptoUtils.ts` 포팅
- [ ] `BydApiClient.ts` 포팅 (로그인 + 차량 목록 + 상태 조회 + 원격 제어)
- [ ] 단독 실행 테스트 스크립트 작성 (Homebridge 없이 API만 검증)

### Phase 2 — Homebridge 플러그인 구조
- [ ] `platform.ts`: BYDHomebridgePlatform 클래스
- [ ] `config.schema.json` 작성
- [ ] 액세서리 캐싱 (UUID 기반, 재시작 시 재등록 방지)
- [ ] 세션 토큰 파일 저장 (재시작 시 재로그인 최소화)

### Phase 3 — 액세서리 구현
- [ ] `LockAccessory.ts`: LockMechanism 서비스
- [ ] `ClimateAccessory.ts`: Switch 서비스 + 온도/시간 설정
- [ ] `BatteryAccessory.ts`: Battery 서비스 (폴링 기반 상태 업데이트)
- [ ] `TrunkAccessory.ts`: Switch 서비스

### Phase 4 — 로컬 테스트 및 배포
- [ ] Windows Homebridge에 로컬 설치 (`npm link`)
- [ ] 홈 앱 대시보드 확인
- [ ] 위치 자동화 테스트
- [ ] npm 배포 (선택)

---

## bangcle_tables.bin 추출 방법

iOS 앱 아카이브 또는 시뮬레이터 빌드에서 추출:
```
BydAutoLock.app/bangcle_tables.bin
```
해당 파일을 `homebridge-byd/assets/bangcle_tables.bin`에 복사.

---

---

## 사전 검증 체크리스트

### 개발 전 즉시 확인

- [x] `bangcle_tables.bin` 존재 확인 — 코드로 확인 완료
  - 소스: `BydAutoLock/Resources/bangcle_tables.bin`
  - 앱 번들: `build/BydAutoLock.xcarchive/.../BYD AutoLock.app/bangcle_tables.bin`
  - 플러그인 `assets/` 폴더에 복사해서 사용 가능
- [ ] Windows Homebridge 버전 확인 (`homebridge -V`) — 최신 권장
- [ ] Windows Node.js 버전 확인 (`node -V`) — 18+ 필요

### 코드로 사전 검증 완료된 항목

- [x] 에어컨 온도 설정 범위: **15~31도** (`celsiusToScale`: `max(1, min(17, (temp - 14.0)))`)
  - Thermostat `TargetTemperature` 범위를 15~31로 제한
- [x] `acDuration` → `timeSpan` 매핑 확인 완료
  - 10분→1, 15분→2, 20분→3, 25분→4, 30분→5
- [x] Thermostat에 필요한 모든 HvacStatus 필드 존재 확인
  - `interiorTemperature` → `CurrentTemperature`
  - `targetTemperature` (기본 22.0) → `TargetTemperature`
  - `isAcOn` → `CurrentHeatingCoolingState`
- [x] 배터리 폴링 API: **`fetchChargingStatus` 사용**으로 결정
  - `ChargingStatus.batteryPercentage` → `BatteryLevel`
  - `ChargingStatus.isCharging` → `ChargingState` (HomeKit 직접 매핑)
  - `/control/smartCharge/homePage` — vehicleRealTimeRequest 같은 폴링 구조 없음, 가벼운 단일 호출
- [x] 도어 잠금 판별 로직 확인
  - 4개 필드(`leftFront/rightFront/leftRear/rightRear DoorLock`) 모두 2 → 잠금
  - `hasAny`가 false(모두 0)이면 상태 불명 → `LockCurrentState: unknown`으로 처리
- [x] 세션 만료 코드: 1002, 1005, 1010 → 자동 재로그인 처리
- [x] 주행 중 판별: `powerGear == 3 || speed > 0` → 주행 중엔 잠금 명령 차단 권장

### API 동작 검증 (Phase 1 테스트 시 — 실차 필요)

- [ ] 차량 상태 폴링 빈도 제한 여부 확인
  - 30초 / 60초 간격으로 실험, 서버 차단 여부 확인
- [ ] 도어 잠금 필드 실제 반환값 확인 (raw 응답 출력)
  - 해제 시 값이 1인지 0인지 (코드 상 `hasAny = lf != 0` 이므로 0=불명, 1=해제 추정)
- [ ] `CLOSETRUNK` 지원 여부 확인 (전동 트렁크 없는 차종 실패 가능)

### 설계 결정

- [x] 에어컨 액세서리: **Thermostat** 결정
- [x] 에어컨 파라미터: Thermostat TargetTemperature + config `acDuration`
- [x] 배터리 폴링 API: **`fetchChargingStatus`** 결정

---

## 참고

- iOS 구현: `/Users/ggpark/Desktop/git/BYD/BydAutoLock/API/`
- pyBYD 레퍼런스: https://github.com/jkaberg/pyBYD
- Android 레퍼런스: https://github.com/GeyuongGongPark/BydAutoLock
- Homebridge 플러그인 개발 가이드: https://developers.homebridge.io
