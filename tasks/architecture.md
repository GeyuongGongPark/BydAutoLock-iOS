# iOS Architecture Analysis

## 프로젝트 개요

이 문서는 iOS 프로젝트의 전체 아키텍처, 주요 컴포넌트, 데이터 플로우를 분석한 결과입니다.

## 1. 프로젝트 구조

### 1.1 계층 구조


iOS/
├── Sources/
│   ├── App/                      # 앱 진입점
│   │   └── MyApp.swift
│   ├── Features/                 # 기능별 모듈
│   │   ├── AutoLock/
│   │   │   ├── Views/           # SwiftUI Views
│   │   │   ├── ViewModels/      # MVVM ViewModels
│   │   │   └── Models/          # Domain Models
│   │   ├── BLE/
│   │   └── Watch/
│   ├── Services/                 # 비즈니스 로직
│   │   ├── AutoLockService.swift
│   │   ├── BLEService.swift
│   │   └── WatchConnectivityService.swift
│   ├── Data/                     # 데이터 레이어
│   │   ├── Repositories/
│   │   ├── DataSources/
│   │   └── DTOs/
│   └── Core/                     # 공통 유틸리티
│       ├── Extensions/
│       ├── Utilities/
│       └── Constants/
└── Tests/
    ├── UnitTests/
    └── UITests/


### 1.2 아키텍처 패턴

**현재 적용된 패턴: MVVM (Model-View-ViewModel)**


View (SwiftUI)
    ↕ @StateObject / @ObservedObject
ViewModel (@ObservableObject)
    ↕ Protocol
Service Layer
    ↕
Data Layer (Repository)


## 2. 핵심 컴포넌트 분석

### 2.1 AutoLockService

**책임:**
- 자동 잠금/잠금 해제 로직 관리
- 위치 기반 트리거 처리
- BLE 신호 기반 거리 판단

**주요 메서드:**
swift
- func startMonitoring()
- func stopMonitoring()
- func checkProximity() async throws -> Bool
- func triggerLock() async throws
- func triggerUnlock() async throws


**의존성:**
- `BLEService`: 블루투스 통신
- `LocationManager`: 위치 정보
- `LockRepository`: 잠금 상태 영속화

### 2.2 BLEService

**책임:**
- Core Bluetooth 기반 BLE 통신
- 주변 기기 스캔 및 연결
- RSSI 기반 거리 측정

**주요 컴포넌트:**
swift
protocol BLEServiceProtocol {
    var isScanning: Bool { get }
    var discoveredDevices: [BLEDevice] { get }
    func startScanning()
    func stopScanning()
    func connect(to device: BLEDevice) async throws
}


**데이터 플로우:**

CBCentralManager
    → BLEService (didDiscover peripheral)
    → @Published discoveredDevices
    → ViewModel
    → SwiftUI View (자동 업데이트)


### 2.3 WatchConnectivityService

**책임:**
- WatchConnectivity 프레임워크 기반 Watch 통신
- 잠금 상태 동기화
- 원격 제어 명령 수신

**주요 메서드:**
swift
- func sendMessage(_ message: [String: Any])
- func updateApplicationContext(_ context: [String: Any])
- func session(didReceiveMessage message: [String: Any])


## 3. 데이터 플로우

### 3.1 자동 잠금 시나리오

mermaid
sequenceDiagram
    participant User
    participant View
    participant VM as ViewModel
    participant Service as AutoLockService
    participant BLE as BLEService
    participant Repo as LockRepository

    User->>View: 자동 잠금 활성화
    View->>VM: enableAutoLock()
    VM->>Service: startMonitoring()
    Service->>BLE: startScanning()
    
    loop 주기적 체크
        Service->>BLE: checkProximity()
        BLE-->>Service: RSSI 값
        alt 임계값 초과 (멀리 떨어짐)
            Service->>Service: triggerLock()
            Service->>Repo: saveLockState(.locked)
            Service->>VM: 상태 업데이트
            VM->>View: UI 반영
        end
    end


### 3.2 Watch 연동 시나리오


Watch App (버튼 탭)
    → WCSession.sendMessage()
    → iPhone WatchConnectivityService
    → didReceiveMessage() 핸들러
    → AutoLockService.triggerUnlock()
    → ViewModel 상태 업데이트
    → SwiftUI View 자동 반영


## 4. 기능별 파일 매핑

### 4.1 자동 잠금 기능

| 컴포넌트 | 파일 경로 | 책임 |
|---------|----------|------|
| View | `Features/AutoLock/Views/AutoLockView.swift` | UI 렌더링 |
| ViewModel | `Features/AutoLock/ViewModels/AutoLockViewModel.swift` | UI 상태 관리 |
| Service | `Services/AutoLockService.swift` | 비즈니스 로직 |
| Repository | `Data/Repositories/LockRepository.swift` | 데이터 영속화 |
| Model | `Features/AutoLock/Models/LockState.swift` | Domain 모델 |

### 4.2 BLE 통신

| 컴포넌트 | 파일 경로 | 책임 |
|---------|----------|------|
| Service | `Services/BLEService.swift` | BLE 통신 로직 |
| Model | `Features/BLE/Models/BLEDevice.swift` | BLE 기기 모델 |
| ViewModel | `Features/BLE/ViewModels/BLEViewModel.swift` | 기기 목록 관리 |

### 4.3 Watch 연동

| 컴포넌트 | 파일 경로 | 책임 |
|---------|----------|------|
| Service | `Services/WatchConnectivityService.swift` | Watch 통신 |
| Delegate | `Services/WatchConnectivityService+Delegate.swift` | WCSession 델리게이트 |

## 5. 코드 품질 평가

### 5.1 아키텍처 패턴 준수도: ⭐⭐⭐⭐☆ (4/5)

**장점:**
- MVVM 패턴 일관되게 적용
- Protocol 기반 의존성 역전 (테스트 용이)
- SwiftUI + Combine으로 반응형 구현

**개선 필요:**
- Service 레이어가 과도한 책임 보유 (God Object 경향)
- Repository 패턴 미적용 (데이터 소스 추상화 부족)

### 5.2 에러 핸들링: ⭐⭐⭐☆☆ (3/5)

**장점:**
- `async/await` 기반 에러 전파
- 커스텀 Error enum 정의

**개선 필요:**
- 에러 복구 전략 부재
- 사용자 친화적 에러 메시지 미흡
- 로깅 시스템 부재

### 5.3 테스트 커버리지: ⭐⭐☆☆☆ (2/5)

**현황:**
- Unit Test: 약 30% (추정)
- UI Test: 거의 없음

**개선 필요:**
- Service 레이어 테스트 확대
- Mock 객체 활용 테스트
- UI 시나리오 테스트 추가

### 5.4 메모리 관리: ⭐⭐⭐⭐☆ (4/5)

**장점:**
- `[weak self]` 일관되게 사용
- Combine 구독 `store(in:)` 적절히 활용

**개선 필요:**
- BLE 연결 해제 시 리소스 정리 강화
- 백그라운드 작업 생명주기 관리

## 6. 개선 포인트

### 6.1 Service 레이어 분리 (우선순위: 높음)

**현재 문제:**
swift
// AutoLockService가 너무 많은 책임 보유
class AutoLockService {
    func startMonitoring()        // 모니터링
    func checkProximity()         // 거리 체크
    func triggerLock()            // 잠금 실행
    func saveLockState()          // 데이터 저장
    func notifyWatch()            // Watch 통신
}


**개선 방안:**
swift
// UseCase 패턴 적용
protocol AutoLockUseCaseProtocol {
    func execute() async throws -> LockResult
}

class AutoLockUseCase: AutoLockUseCaseProtocol {
    private let proximityService: ProximityServiceProtocol
    private let lockRepository: LockRepositoryProtocol
    private let notificationService: NotificationServiceProtocol
    
    func execute() async throws -> LockResult {
        let isClose = try await proximityService.checkProximity()
        let state = isClose ? LockState.unlocked : LockState.locked
        try await lockRepository.save(state)
        await notificationService.notify(state)
        return LockResult(newState: state)
    }
}


### 6.2 Repository 패턴 도입 (우선순위: 중간)

**현재 문제:**
- 데이터 소스가 Service에 직접 결합
- 로컬/원격 데이터 소스 전환 어려움

**개선 방안:**
swift
protocol LockRepositoryProtocol {
    func getLockState() async throws -> LockState
    func saveLockState(_ state: LockState) async throws
}

class LockRepository: LockRepositoryProtocol {
    private let localDataSource: LockLocalDataSourceProtocol
    private let remoteDataSource: LockRemoteDataSourceProtocol
    
    func saveLockState(_ state: LockState) async throws {
        try await localDataSource.save(state)
        try? await remoteDataSource.sync(state) // Best-effort
    }
}


### 6.3 에러 처리 표준화 (우선순위: 중간)

**현재 문제:**
- 에러 타입 산재
- 에러 메시지 일관성 부족

**개선 방안:**
swift
enum AppError: LocalizedError {
    case ble(BLEError)
    case watch(WatchError)
    case lock(LockError)
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .ble(.deviceNotFound):
            return "기기를 찾을 수 없습니다. 블루투스를 확인해주세요."
        case .lock(.unauthorized):
            return "잠금 권한이 없습니다."
        default:
            return "일시적인 오류가 발생했습니다."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .ble(.deviceNotFound):
            return "설정 > 블루투스에서 기기 연결을 확인하세요."
        default:
            return "잠시 후 다시 시도해주세요."
        }
    }
}


### 6.4 백그라운드 작업 최적화 (우선순위: 높음)

**현재 문제:**
- BLE 스캔이 계속 실행되어 배터리 소모
- 백그라운드 모드에서 불필요한 작업 수행

**개선 방안:**
swift
class AutoLockService {
    private var isInBackground = false
    
    func sceneDidEnterBackground() {
        isInBackground = true
        // 백그라운드에서는 스캔 간격 늘리기
        scanInterval = 60.0 // 1분
    }
    
    func sceneWillEnterForeground() {
        isInBackground = false
        scanInterval = 5.0 // 5초
    }
}


### 6.5 테스트 커버리지 확대 (우선순위: 중간)

**개선 방안:**
swift
// Mock 객체 예시
class MockBLEService: BLEServiceProtocol {
    var mockDevices: [BLEDevice] = []
    var shouldFail = false
    
    func startScanning() {
        if shouldFail {
            // 에러 시뮬레이션
        } else {
            discoveredDevices = mockDevices
        }
    }
}

// 테스트 예시
class AutoLockUseCaseTests: XCTestCase {
    func testLockWhenDeviceIsFarAway() async throws {
        // Given
        let mockBLE = MockBLEService()
        mockBLE.mockDevices = []
        let useCase = AutoLockUseCase(bleService: mockBLE)
        
        // When
        let result = try await useCase.execute()
        
        // Then
        XCTAssertEqual(result.newState, .locked)
    }
}


## 7. 권장 마이그레이션 로드맵

### Phase 1: 기반 강화 (1-2주)
- [ ] Repository 패턴 도입
- [ ] 에러 처리 표준화
- [ ] 로깅 시스템 구축

### Phase 2: 아키텍처 개선 (2-3주)
- [ ] Service 레이어 분리 (UseCase 도입)
- [ ] DI Container 구축
- [ ] Protocol 인터페이스 정리

### Phase 3: 품질 향상 (2주)
- [ ] Unit Test 커버리지 70% 달성
- [ ] UI Test 시나리오 작성
- [ ] 성능 프로파일링 및 최적화

## 8. 결론

현재 프로젝트는 **MVVM 패턴 기반의 견고한 기초**를 갖추고 있으나, Service 레이어의 책임 분산과 테스트 가능성 향상이 필요합니다. 제안된 개선 사항을 단계적으로 적용하면 **유지보수성과 확장성이 크게 향상**될 것으로 예상됩니다.

**핵심 강점:**
- SwiftUI + Combine 기반 현대적 아키텍처
- Protocol 기반 추상화로 테스트 용이성 확보
- 메모리 관리 양호

**개선 우선순위:**
1. Service 레이어 분리 (UseCase 패턴)
2. 백그라운드 작업 최적화
3. 에러 처리 표준화
4. Repository 패턴 도입
5. 테스트 커버리지 확대