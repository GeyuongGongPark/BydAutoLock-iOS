# Lessons Learned

---

## 워크플로우 필수 순서

**커밋 전 반드시 .md 업데이트 먼저:**
1. `tasks/todo.md` — 완료 항목 체크 및 검토 섹션 추가
2. `tasks/lessons.md` — 새로 얻은 교훈 기록
3. 그 다음 커밋 (코드 + .md 파일 함께)

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
- `desiredAccuracy = kCLLocationAccuracyNearestTenMeters`, `distanceFilter = 10` → GPS 사용, 배터리 소모 있음
- 배터리보다 안정성이 중요한 경우 정확도를 높임 (사용자 판단에 따름)
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

## 로그 분석 선행의 중요성

**코드 분석만으로는 실제 발생 여부를 확인할 수 없음:**
- 정적 분석에서 찾은 버그 중 일부(stationaryTimer 중복 등)는 실제로는 이미 처리된 경우
- 로그를 먼저 확인하면 실제로 발생하는 버그에 집중할 수 있음
- 코드 분석 + 로그 분석을 함께 해야 우선순위가 명확해짐

---

