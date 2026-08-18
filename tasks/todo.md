# 코드/로그 검수 후 수정 계획

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
