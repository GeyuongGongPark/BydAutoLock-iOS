# 캠핑 모드 시뮬레이션 — Android 차량 앱 플랜

## 배경

- BYD 씨라이언 7: 차량 자체 캠핑 모드 있음 → 대상 아님
- **타겟 차종: 아토 3, 돌핀 등 캠핑 모드 없는 차종**
- 해당 차종 인포테인먼트(DiLink): APK 사이드로딩 수월
- 차량 내 Android 앱으로 캠핑 모드 시뮬레이션 제공

## 구현 방식

BYD 서버 API(OPENAIR 등)를 차량 내 앱에서 직접 호출.
Android Service로 28분마다 재호출 → iOS 백그라운드 제약 없음.

## 구현 범위

### 가능한 것
- 공조 유지 — OPENAIR 28분마다 재호출 (Android Foreground Service)
- 배터리 임계값 감시 — 실시간 데이터 폴링
- 최대 지속 시간 제한
- 차량 스피커/화면 알림

### 불가능한 것
- CPD(아동보호 잠금) 해제
- ECU 레벨 캠핑 모드 진입
- 씨라이언 7 수준의 디스플레이 절전/전력 최적화

---

## 사용자 설정

| 설정 | 기본값 | 범위 |
|------|--------|------|
| 목표 온도 | 24°C | 16~30°C |
| 종료 배터리 % | 30% | 10~50% |
| 최대 지속 시간 | 8시간 | 1~12시간 |
| 공조 재호출 간격 | 28분 | 고정 |

---

## 동작 흐름

```
사용자: 캠핑 모드 시작
  │
  ├─ 1. 사전 체크
  │     - 배터리 % > 종료 임계값+5%
  │     - 차량 온라인 (인포테인먼트 네트워크)
  │
  ├─ 2. Foreground Service 시작
  │     - 상태바 알림으로 서비스 유지 (Android 요구사항)
  │
  ├─ 3. OPENAIR(목표 온도) 호출
  │
  ├─ 4. 루프
  │     ├─ [5분마다] 배터리 % 폴링
  │     │   ├─ 임계값 이하 → CLOSEAIR + 화면 알림 + 서비스 종료
  │     │   └─ 정상 → 계속
  │     ├─ [28분마다] OPENAIR 재호출
  │     └─ 최대 시간 초과 → CLOSEAIR + 화면 알림 + 서비스 종료
  │
  └─ 사용자 수동 종료 → CLOSEAIR + 서비스 종료
```

---

## 앱 구조

```
BydCamp (Android APK)
├─ MainActivity — 메인 화면 (차량 터치스크린 최적화 UI)
├─ CampingService — Android Foreground Service (핵심 루프)
├─ BydApiClient — BYD 서버 API 통신 (Android 레퍼런스 참고)
├─ SettingsActivity — 계정 로그인 + 설정
└─ VehicleStatusPoller — 배터리 % 폴링
```

## UI 방향 (차량 터치스크린)

- 큰 버튼 중심 (운전석에서 손 뻗어서 탭)
- 현재 상태: 배터리 %, 경과 시간, 설정 온도
- 시작/종료 버튼 크게
- 복잡한 설정은 최소화

---

## 개발 레퍼런스

- Android BYD API 구현: https://github.com/GeyuongGongPark/BydAutoLock
- BYD API 프로토콜: https://github.com/jkaberg/pyBYD
- iOS 앱 기존 구현 (OPENAIR 파라미터 등): BydVehicleService.swift

## 배포 방식

- APK 직접 사이드로딩 (아토 3, 돌핀)
- GitHub Releases로 APK 배포
- 업데이트는 수동 (차량 내 자동 업데이트 불가)

---

## 단계별 구현 순서

1. BydApiClient — BYD 서버 로그인 + OPENAIR/CLOSEAIR + 실시간 데이터 폴링
2. CampingService — Foreground Service + 28분 루프
3. SettingsActivity — 계정 로그인, VIN 선택, 캠핑 설정
4. MainActivity — 메인 UI
5. 실차 테스트 (아토 3 or 돌핀)
