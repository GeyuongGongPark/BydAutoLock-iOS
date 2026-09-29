# BYD Stats — iOS 앱 상세 플랜

## 개요

BYD 차량의 배터리 이력, 충전 세션, 주행 효율, 비용을 트래킹하는 iOS 통계 앱.
BYD 공식 앱에는 없거나 부족한 데이터 분석 기능을 제공.

---

## 데이터 소스

### BYD API 실시간 데이터 (pyBYD realtime.py 확인 기준)
| 필드 | 용도 | 비고 |
|------|------|------|
| `elec_percent` | 배터리 % — 충전/주행 세션 감지, 이력 그래프 | |
| `charge_state` / `is_charging` | 충전 세션 시작/종료 감지 | 권장 필드 |
| `gl` (W) | 순간 배터리 전력 — /1000 → kW | 양수=충전, 음수=방전 추정 |
| `rate` | 충전 속도 | 미충전 시 sentinel (-999, -9) |
| `speed` | 현재 속도 (km/h) | `isDriving` 대체: `speed > 0` |
| `power_gear` | PowerGear.ON(3)/OFF(1) | `isDriving` 대체 보조 |
| `temp_in_car` | 실내 온도 | 공조 상태 참고 |
| `total_mileage` | 누적 주행거리 (km) | 세션 간 델타로 주행거리 추정 |
| `full_hour` / `full_minute` | 충전 완료까지 남은 시간 | |

> **참고**: `isDriving` 직접 필드 없음. `speed > 0` OR `power_gear == .ON` 조합으로 판단.

### BYD `getEnergyConsumption` 별도 API (추가 발견)
| 데이터 | 설명 |
|--------|------|
| `selfGraph` | **7일 롤링 소비 그래프** — 날짜별 kWh/100km |
| `cumulativeEnergyConsumption` | 라이프타임 평균 전비, 총 주행거리 |
| `nearestEnergyConsumption` | 최근 50km — EV 소비, 드라이빙 모드 분포 (일반/전기/공조/기타 %) |

→ 7일 그래프는 로컬 계산 없이 서버에서 바로 가져올 수 있음.

### GPS
- 차량 GPS: 에러 6051로 사용 불가
- **대안: iOS CoreLocation** — 폰이 차 안에 있을 때 위치 기록
- 위치 기반 기능은 CoreLocation 사용, 없으면 거리 수동 입력

### 차종별 배터리 용량 (kWh 계산 기준)
| 차종 | 배터리 용량 |
|------|------------|
| 아토 3 | 60.48 kWh |
| 돌핀 Standard | 44.9 kWh |
| 돌핀 Extended | 60.4 kWh |
| 씰 | 82.56 kWh |
| 씨라이언 7 | 82.56 kWh |
| 씨라이언 6 | 87.23 kWh |

---

## 핵심 기능

### 1. 배터리 이력 그래프
- 시간축 X, 배터리 % Y — Swift Charts LineChart
- 구간 색상 구분: 충전 중(초록), 주행 중(파랑), 주차(회색)
- 기간 필터: 24시간 / 7일 / 30일 / 전체
- 7일 소비 그래프는 `getEnergyConsumption` API 직접 활용 가능 (로컬 계산 불필요)

### 2. 충전 세션 트래킹
- 세션 감지: `charge_state == .CHARGING` 구간 자동 감지
- 기록 항목:
  - 시작/종료 시간
  - 시작 배터리 % → 종료 배터리 %
  - 충전량 (kWh) = (SOC 증가 × 배터리 용량) / 100
  - 평균 충전 전력 (kW) — `gl` 필드 기반
  - 충전 시간
  - 추정 비용 = 충전 kWh × 설정 전기요금(원/kWh)
  - 위치 (CoreLocation, 옵션)
- 충전 세션 목록 + 월별 합계

### 3. 주행 세션 트래킹
- 세션 감지: `speed > 0` OR `power_gear == .ON` 구간
- 기록 항목:
  - 시작/종료 시간
  - 소비 배터리 %
  - 소비 에너지 (kWh)
  - 주행 거리 (CoreLocation GPS 또는 수동 입력)
  - 전비 (km/kWh) — 거리 입력 시
- 주행 세션 목록 + 월별 합계

### 4. 월별 비용 통계
- 월별 충전 총량(kWh), 충전 횟수, 추정 비용
- 전년 동월 비교 (데이터 있을 경우)
- Swift Charts BarChart

### 5. 대시보드 (메인 화면)
- 현재 배터리 %, 충전 중 여부
- 오늘 통계: 충전량, 주행 거리, 소비 에너지
- 이번 달 충전 비용 누적
- 최근 충전 세션 요약

---

## 백그라운드 데이터 수집

### 전략
별도 앱이라 BLE 백그라운드 없음 → 두 가지 조합:

```
1. 앱 포어그라운드 (정밀)
   - 5분 간격 폴링
   - 실시간 세션 감지

2. BGAppRefreshTask (백그라운드, 불규칙)
   - iOS가 허용할 때 실행 (15분~수 시간 간격)
   - 데이터 포인트 저장
   - 세션 경계 추정
```

### 한계 및 대응
- BGAppRefreshTask는 실행 시점을 보장 못 함
- → 충전 중일 때는 알림(UNUserNotificationCenter)으로 포어그라운드 유도
- → 주행 중 트래킹은 앱이 열려있을 때만 정밀, 백그라운드는 추정

---

## 앱 구조

```
BydStats/
├─ App/
│   └─ BydStatsApp.swift
│
├─ Views/
│   ├─ DashboardView.swift          — 메인 대시보드
│   ├─ BatteryHistoryView.swift     — 배터리 이력 그래프
│   ├─ ChargingSessionsView.swift   — 충전 세션 목록/통계
│   ├─ DrivingSessionsView.swift    — 주행 세션 목록/통계
│   └─ SettingsView.swift           — 계정, 차종, 전기요금 설정
│
├─ Services/
│   ├─ BydApiClient.swift           — BYD API 통신 (현재 앱 로직 참고)
│   ├─ DataCollector.swift          — 폴링 + 세션 감지 메인 로직
│   ├─ SessionDetector.swift        — 충전/주행 세션 경계 감지
│   └─ BackgroundTaskManager.swift  — BGAppRefreshTask 등록/실행
│
└─ Models/ (SwiftData)
    ├─ DataPoint.swift              — 단일 폴링 스냅샷
    ├─ ChargingSession.swift        — 충전 세션
    └─ DrivingSession.swift         — 주행 세션
```

---

## SwiftData 모델

```swift
// 폴링 스냅샷
@Model class DataPoint {
    var timestamp: Date
    var batteryPercent: Int
    var isCharging: Bool
    var isDriving: Bool
    var chargingPowerKw: Double?
    var hvacOn: Bool
}

// 충전 세션
@Model class ChargingSession {
    var startTime: Date
    var endTime: Date?
    var startSoc: Int
    var endSoc: Int
    var energyKwh: Double          // (endSoc - startSoc) × 배터리용량 / 100
    var durationMinutes: Int
    var estimatedCostKrw: Double   // energyKwh × 요금단가
    var latitude: Double?
    var longitude: Double?
}

// 주행 세션
@Model class DrivingSession {
    var startTime: Date
    var endTime: Date?
    var startSoc: Int
    var endSoc: Int
    var energyKwh: Double          // 소비 에너지
    var distanceKm: Double?        // GPS or 수동 입력
    var efficiencyKmPerKwh: Double? // distanceKm / energyKwh
}
```

---

## 설정 항목

| 설정 | 설명 |
|------|------|
| BYD 계정 (ID/PW) | API 로그인용 |
| 차종 선택 | 배터리 용량 kWh 계산 기준 |
| 전기요금 단가 (원/kWh) | 기본값 180원, 심야 120원 |
| 심야 요금제 시간대 | 23:00~09:00 (한전 기준) |
| 폴링 간격 | 5분 / 10분 / 15분 |
| GPS 트래킹 허용 | CoreLocation 사용 여부 |

---

## 기술 스택

| 항목 | 선택 |
|------|------|
| UI | SwiftUI |
| 데이터 저장 | SwiftData (iOS 17+) |
| 차트 | Swift Charts |
| 백그라운드 | BGAppRefreshTask |
| 위치 | CoreLocation (차량 GPS 대신) |
| 최소 iOS | iOS 17 |

---

## 단계별 구현 순서

1. **BydApiClient** — 로그인, 실시간 데이터 폴링 (현재 iOS 앱 코드 참고)
2. **SwiftData 모델** — DataPoint, ChargingSession, DrivingSession
3. **SessionDetector** — 충전/주행 세션 경계 감지 알고리즘
4. **DataCollector** — 폴링 루프 + SessionDetector 연동
5. **DashboardView** — 현재 상태 + 오늘 요약
6. **BatteryHistoryView** — Swift Charts 라인 그래프
7. **ChargingSessionsView** — 세션 목록 + 월별 합계
8. **DrivingSessionsView** — 세션 목록 + 전비
9. **BGAppRefreshTask** — 백그라운드 수집 등록
10. **SettingsView** — 계정, 차종, 요금 설정

---

## 미결 사항

- [x] ~~isDriving 필드 확인~~ → 없음. `speed > 0` OR `power_gear == .ON` 으로 대체
- [x] ~~충전 전력(kW) 필드 확인~~ → `gl` (순간 배터리 전력 W), `rate` (충전 속도) 확인됨
- [x] ~~별도 레포 vs 현재 레포 타겟 추가~~ → 별도 레포로 결정
- [ ] `gl` 필드 양수/음수 기준 실 차량 로그로 검증 필요 (충전=양수? 방전=음수?)
- [ ] `rate` 필드 단위 확인 (kW? 퍼센트/시간?)
- [ ] BGAppRefreshTask 실행 빈도가 충분한지 실 사용 검증 필요
