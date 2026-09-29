# BYD 서드파티 앱 구상

## 기반 데이터 (pyBYD issue #20 기준)

| 데이터 영역 | 사용 가능한 필드 수 |
|------------|------------------|
| 실시간 차량 데이터 | 94개 (배터리, 타이어, 도어, 윈도우, 충전 상태 등) |
| HVAC (공조) | 26개 매핑 완료, 14개 미매핑 |
| GPS | 1개 (requestSerial만, 위치는 오류) |
| 충전 정보 | 6개 |
| 제어 commandType | LOCKDOOR, OPENDOOR, OPENAIR, CLOSEAIR, OPENWINDOW, CLOSEWINDOW, OPENTRUNK, CLOSETRUNK, FINDCAR, FLASHLIGHTNOWHISTLE, BATTERYHEAT |

---

## 앱 아이디어

### 1. BYD Widget — 홈/잠금화면 위젯

**핵심 가치**: 앱 열지 않고 차량 상태 한눈에

구현 내용:
- 배터리 %, 충전 중 여부, 도어 잠금 상태 위젯
- 타이어 압력 이상 시 경고 위젯
- 잠금화면 컴플리케이션 (iOS 16+)
- 홈 화면 Small/Medium/Large 위젯

기술 스택: iOS WidgetKit, AppIntent (위젯에서 버튼 탭으로 잠금/해제)

난이도: 낮음 — 데이터 폴링 + 위젯 렌더링

차별화: BYD 공식 앱에 위젯 없거나 제한적

---

### 2. BYD Charge — 충전 스케줄러

**핵심 가치**: 전기요금 저렴한 시간대에 자동 충전

구현 내용:
- 심야 요금제 시간대 설정 (예: 23:00~07:00)
- 목표 배터리 % 설정
- 설정된 시간에 충전 시작/종료 알림
- 충전 완료 시 알림
- 충전 이력 및 추정 절약 비용 표시

기술 스택: iOS Background Tasks, 로컬 알림

난이도: 중간
- BYD API에 충전 시작/종료 commandType 여부 불명확 (확인 필요)
- 데이터 수집(충전 상태 폴링)은 가능

한계: 충전 원격 시작 commandType이 없으면 알림만 제공하는 형태로 제한

---

### 3. BYD Camp — 캠핑 모드 전용 앱

**핵심 가치**: 차박 특화 제어 + 모니터링

구현 내용:
- 공조 유지 (28분마다 OPENAIR 재호출)
- 배터리 % 실시간 모니터링
- 배터리 임계값 알림
- 경과 시간 표시
- V2L 전력 소비 추정 (설정 기반)
- 날씨 API 연동 — 외부 온도 기반 자동 온도 제안

기술 스택: iOS Background Tasks, WeatherKit

난이도: 중간 (camping-mode-plan.md 참고)

비고: 현재 BYD AutoLock 앱 내 기능으로도 통합 가능

---

### 4. BYD Watch — Apple Watch 전용 앱

**핵심 가치**: 손목에서 즉시 제어, 폰 꺼낼 필요 없음

구현 내용:
- 잠금/해제/트렁크/에어컨 Haptic 버튼
- 배터리 % 컴플리케이션
- Watch Face 직접 표시
- 독립 실행 (iPhone 없이 Watch만으로 LTE 제어)

기술 스택: watchOS, WatchConnectivity

난이도: 중간
- 현재 BYD AutoLock Watch 앱이 이미 존재 → 기능 확장 형태

차별화: 독립 LTE Watch 지원 여부 (현재 앱은 iPhone 연동 필요한지 확인 필요)

---

### 5. BYD HomeKit — Apple 홈 앱 연동

**핵심 가치**: Siri로 자연어 제어, 자동화 연동

구현 내용:
- 차량을 HomeKit 액세서리로 등록
- 도어 잠금 → HomeKit Lock 액세서리
- 에어컨 → HomeKit Thermostat 액세서리
- "집에 도착하면 에어컨 켜기" 자동화
- Siri: "이봐 Siri, 차 잠가줘"

기술 스택: HomeKit (HMAccessory), HomeKitBridger 또는 Homebridge 플러그인

난이도: 높음
- HomeKit 인증 요구 (MFi) or Homebridge로 우회
- Homebridge 플러그인 형태가 현실적: homebridge-byd

차별화: 전혀 없는 영역, HomeKit 생태계와 결합하면 자동화 가능성 무한

---

### 6. BYD Stats — 주행/충전 통계 앱

**핵심 가치**: 배터리 효율, 에너지 소비 트래킹

구현 내용:
- 배터리 % 변화 이력 그래프
- 충전 세션 기록 (충전량, 시간, 위치)
- 주행 효율 추정 (배터리 소비 / 거리)
- 월별 충전 비용 추정

기술 스택: Swift Charts, CoreData or SwiftData

난이도: 중간
- GPS 에러(6051)로 위치 기반 기능 제한
- 배터리 % 폴링 이력 로컬 저장 방식으로 구현 가능

---

## 우선순위 추천

| 앱 | 실현 가능성 | 유용성 | 차별화 | 추천 |
|----|-----------|--------|--------|------|
| BYD Widget | 높음 | 높음 | 중간 | ★★★ |
| BYD Camp | 높음 | 중간 | 높음 | ★★★ |
| BYD Watch 확장 | 높음 | 높음 | 중간 | ★★★ |
| BYD Stats | 중간 | 중간 | 중간 | ★★ |
| BYD Charge | 중간 | 높음 | 높음 | ★★ (API 확인 필요) |
| BYD HomeKit | 낮음 | 높음 | 최고 | ★★ (난이도 높음) |

## 단기 실행 가능 조합

**현재 BYD AutoLock 앱 확장**:
- 캠핑 모드 시뮬레이션 (camping-mode-plan.md)
- WidgetKit 위젯 추가
- Watch 앱 기능 확장

**별도 앱으로 분리**:
- Homebridge 플러그인 (Node.js) — HomeKit 연동
- BYD Stats (데이터 수집 관심 있을 경우)
