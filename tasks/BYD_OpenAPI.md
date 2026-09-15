# BYD Auto OpenAPI
## 차량 시스템 하드웨어 추상화 계층(HAL) SDK 개발 매뉴얼
**bydauto-openapi.jar 디컴파일 기반 인터페이스 상세 분석**

버전: V1.0 | 날짜: 2026-07-02 | 출처: JAR 패키지 디컴파일 분석

---

## 목차
1. 개요
2. SDK 아키텍처 설계
3. 빠른 시작
4. 핵심 기반 클래스 및 인터페이스
   - 4.1 IBYDAutoDevice
   - 4.2 IBYDAutoListener & IBYDAutoEvent
   - 4.3 AbsBYDAutoDevice
   - 4.4 BYDAutoDeviceManager
   - 4.5 BYDAutoConstants
5. 디바이스 모듈 API 상세
   - 5.1 공조(AC) 5.2 오디오(Audio) 5.3 차체(Bodywork) 5.4 충전(Charging) 5.5 도어락(DoorLock) 5.6 에너지 관리(Energy) 5.7 엔진(Engine) 5.8 변속기(Gearbox) 5.9 계기판(Instrument) 5.10 조명(Light) 5.11 멀티미디어(Multimedia) 5.12 어라운드뷰(Panorama) 5.13 PM2.5 5.14 레이더(Radar) 5.15 안전벨트(SafetyBelt) 5.16 센서(Sensor) 5.17 시스템 설정(Setting) 5.18 속도(Speed) 5.19 주행 통계(Statistic) 5.20 시간(Time) 5.21 타이어(Tyre)
6. 전역 상수 참조표
7. 모범 사례 및 주의사항

---

## 1. 개요

BYD Auto OpenAPI는 비야디(BYD) 차량 시스템이 외부에 제공하는 하드웨어 추상화 계층(HAL) SDK로, 차량 각 서브시스템의 제어 및 상태 조회 기능을 캡슐화한 것입니다. 서드파티 애플리케이션 개발자는 이 SDK를 통해 안전하고 표준화된 방식으로 공조, 속도, 충전, 도어/윈도우, 멀티미디어 등의 차량 하드웨어 리소스에 접근할 수 있습니다.

본 문서는 bydauto-openapi.jar(패키징 날짜 2020-03-13, 총 78개 class 파일)를 디컴파일 분석하여 작성되었으며, `android.hardware.bydauto` 패키지 하위의 전체 20개 차량 디바이스 서브시스템에 대한 완전한 API 정의, 상수 열거형, 리스너 콜백 및 사용 예제를 다룹니다.

> **중요 안내**: 이 JAR 패키지는 컴파일 타임 Stub 패키지로, 모든 메서드 바디는 `RuntimeException("Stub!")`을 발생시킵니다. 실제 동작 로직은 BYD 차량 ROM이 디바이스 단에서 AIDL / JNI를 통해 주입하여 구현합니다. 개발자는 이 JAR를 `compileOnly` 의존성으로 추가하기만 하면 컴파일이 가능하며, 런타임에는 시스템이 실제 구현을 제공합니다.

### 1.1 적용 시나리오
- 차량 내비게이션, 음성 비서 등 시스템 앱과 차량 하드웨어 간 상호작용
- 서드파티 차량용 앱의 실시간 속도, 배터리, 타이어 압력 등 데이터 조회
- 스마트 콕핏 애플리케이션의 공조, 멀티미디어, 윈도우 등 제어
- 커넥티드카(T-Box) 애플리케이션의 차량 상태 조회 및 클라우드 업로드

### 1.2 지원 차종
Bodywork 모듈에는 BYD의 F 시리즈, S 시리즈, e 시리즈, 왕조 시리즈(친/탕/송) 및 이후 출시된 여러 연료·하이브리드(HEV)·순수 전기(EV) 차종을 포괄하는 풍부한 차종 상수가 정의되어 있습니다. 구체적인 모델 상수는 5.3절 차체 모듈 설명을 참고하시기 바랍니다.

---

## 2. SDK 아키텍처 설계

BYD Auto OpenAPI는 **옵저버 패턴 + 디바이스 매니저 패턴**을 채택한 계층형 아키텍처로, 전체적으로 3개 계층(최상위 인터페이스 계층, 추상 구현 계층, 구체적 디바이스 계층)으로 구성됩니다.

| 계층 | 패키지 경로 | 핵심 클래스 | 역할 설명 |
|---|---|---|---|
| 최상위 인터페이스 계층 | `android.hardware` | `IBYDAutoDevice`, `IBYDAutoListener`, `IBYDAutoEvent` | 디바이스, 리스너, 이벤트의 통합 인터페이스 계약 정의 |
| 추상 구현 계층 | `android.hardware.bydauto` | `AbsBYDAutoDevice`, `BYDAutoDeviceManager`, `BYDAutoConstants` | 공용 디바이스 기능, 매니저, 전역 상수 제공 |
| 구체적 디바이스 계층 | `android.hardware.bydauto.*` | 각 `XXXDevice` / `AbsXXXListener` | 20개 서브시스템의 구체적인 API 및 콜백 정의 |

### 2.1 핵심 설계 패턴

**싱글턴 패턴 (Singleton)**
각 구체적인 디바이스 클래스는 `getInstance(Context)` 정적 메서드를 제공하며, 시스템이 디바이스 인스턴스의 생명주기를 통합 관리하므로 개발자가 직접 생성할 필요가 없습니다.

**옵저버 패턴 (Observer)**
각 디바이스에는 `AbsXXXListener` 추상 리스너가 함께 제공됩니다. 개발자는 리스너를 상속하여 콜백 메서드를 구현하면 해당 디바이스의 실시간 상태 변화 이벤트를 구독할 수 있습니다. `registerListener()` / `unregisterListener()`를 통해 구독을 관리합니다.

**디바이스 매니저 패턴 (Manager)**
`BYDAutoDeviceManager`는 전역 디바이스 관리 진입점으로, 디바이스의 추가/제거/활성화/비활성화 및 디바이스 간 통합 데이터 읽기/쓰기를 담당합니다.

---

## 3. 빠른 시작

### 3.1 환경 요구사항
- **Android API Level**: 차량용 Android 시스템(일반적으로 Android 4.4 이상)에서 실행 권장
- **개발 의존성**: `bydauto-openapi.jar`를 `compileOnly` / `provided` 의존성으로 프로젝트에 추가
- **런타임**: 이 JAR는 Stub 패키지이므로, 반드시 BYD 차량 시스템 환경에서 실행되어야 하며 시스템이 실제 구현을 주입합니다

### 3.2 의존성 추가
```gradle
// build.gradle (Module: app)
dependencies {
    compileOnly files('libs/bydauto-openapi.jar')
}
```

### 3.3 디바이스 인스턴스 획득
```java
import android.hardware.bydauto.ac.BYDAutoAcDevice;
import android.hardware.bydauto.speed.BYDAutoSpeedDevice;

BYDAutoAcDevice acDevice = BYDAutoAcDevice.getInstance(context);
BYDAutoSpeedDevice speedDevice = BYDAutoSpeedDevice.getInstance(context);
```

### 3.4 디바이스 상태 조회
```java
// 공조 On/Off 상태 조회
int acState = acDevice.getAcStartState();

// 현재 차속 조회 (km/h)
double speed = speedDevice.getCurrentSpeed();

// 가속 페달 깊이 조회 (0-100)
int accel = speedDevice.getAccelerateDeepness();
```

### 3.5 상태 리스너 등록
```java
acDevice.registerListener(new AbsBYDAutoAcListener() {
    @Override public void onAcStarted() { /* 공조 켜짐 */ }
    @Override public void onAcStoped() { /* 공조 꺼짐 */ }
    @Override public void onTemperatureChanged(int area, int value) {
        // 온도 변경됨
    }
    @Override public void onDataChanged(IBYDAutoEvent event) {
        // 공용 데이터 변경 콜백
    }
});
```

---

## 4. 핵심 기반 클래스 및 인터페이스

### 4.1 IBYDAutoDevice

- **패키지 경로**: `android.hardware.IBYDAutoDevice`
- **타입**: 공용 인터페이스 (Interface)
- **역할**: 모든 차량 디바이스 클래스의 최상위 인터페이스로, 디바이스 유형 식별, 이벤트 전달, 리스너 등록의 표준 계약을 정의합니다.

| 메서드 시그니처 | 반환값 | 설명 |
|---|---|---|
| `int getType()` | int | 디바이스 유형 식별자 조회, `BYDAutoConstants`의 `DEVICE` 상수에 대응 |
| `boolean postEvent(int devType, int evtType, int val, Object data)` | boolean | int 타입 값 이벤트를 시스템에 전달 |
| `boolean postEvent(int devType, int evtType, double val, Object data)` | boolean | double 타입 값 이벤트를 시스템에 전달 |
| `boolean postEvent(int devType, int evtType, byte[] val, Object data)` | boolean | byte 배열 타입 값 이벤트를 시스템에 전달 |
| `boolean onPostEvent(IBYDAutoEvent event)` | boolean | 시스템이 콜백하는 이벤트 분배 진입점 |
| `void registerListener(IBYDAutoListener l)` | void | 공용 리스너 등록 |
| `void unregisterListener(IBYDAutoListener l)` | void | 공용 리스너 해제 |

### 4.2 IBYDAutoListener & IBYDAutoEvent

`IBYDAutoListener`는 모든 디바이스 리스너의 최상위 인터페이스로, 다음 메서드 하나만 선언합니다.

```java
void onDataChanged(IBYDAutoEvent event)
```

각 디바이스의 `AbsXXXListener`는 모두 이 인터페이스를 상속하며, 이를 기반으로 세분화된 상태 변경 콜백(예: `onAcStarted`, `onSpeedChanged` 등)을 확장합니다.

`IBYDAutoEvent`는 이벤트 객체 인터페이스로, 이벤트가 담고 있는 모든 정보를 캡슐화합니다.

| 메서드 | 반환값 | 설명 |
|---|---|---|
| `int getDeviceType()` | int | 이벤트 발생 디바이스 유형 |
| `int getEventType()` | int | 이벤트 유형 식별자 |
| `int getValue()` | int | 정수 값 (이벤트가 int 값을 담고 있는 경우) |
| `double getDoubleValue()` | double | 부동소수점 값 (이벤트가 double 값을 담고 있는 경우) |
| `Object getData()` | Object | 부가 데이터 객체 |
| `void setData(Object data)` | void | 부가 데이터 설정 |

> **팁**: 실제 개발에서는 공용 이벤트 처리나 디버깅이 필요한 경우에만 `onDataChanged`를 사용하고, 그 외에는 각 디바이스 전용의 `AbsXXXListener` 세분화 콜백을 우선 사용할 것을 권장합니다.

### 4.3 AbsBYDAutoDevice

- **패키지 경로**: `android.hardware.bydauto.AbsBYDAutoDevice`
- **타입**: 추상 클래스, `IBYDAutoDevice` 구현
- **역할**: 모든 구체적인 디바이스에 공용 하위 레벨 데이터 읽기/쓰기 기능을 제공하며, int, double, byte[] 및 배열 타입을 지원하는 set/get 계열 오버로드 메서드를 포함합니다.

| 메서드 시그니처 | 설명 |
|---|---|
| `int set(int device, int event, int value)` | 지정 디바이스의 지정 이벤트에 int 값 쓰기 |
| `int set(int device, int event, double value)` | 지정 디바이스의 지정 이벤트에 double 값 쓰기 |
| `int set(int device, int event, byte[] value)` | 지정 디바이스의 지정 이벤트에 byte 배열 쓰기 |
| `int set(int device, int[] event, int[] params)` | int 배열 일괄 쓰기 |
| `int set(int device, int[] event, double[] params)` | double 배열 일괄 쓰기 |
| `int get(int device, int event)` | 지정 이벤트의 int 값 읽기 |
| `int[] getIntArray(int device, int[] event)` | int 배열 일괄 읽기 |
| `byte[] getBuffer(int device, int event)` | byte 배열 읽기 |
| `double getDouble(int device, int event)` | double 값 읽기 |
| `double[] getDoubleArray(int device, int[] event)` | double 배열 일괄 읽기 |

### 4.4 BYDAutoDeviceManager

- **패키지 경로**: `android.hardware.bydauto.BYDAutoDeviceManager`
- **타입**: 추상 클래스
- **역할**: 전역 디바이스 매니저로, 디바이스의 추가/제거, 활성화/비활성화 및 통합 읽기/쓰기 인터페이스를 제공합니다. 싱글턴 패턴을 통해 획득합니다.

| 메서드 시그니처 | 설명 |
|---|---|
| `static BYDAutoDeviceManager getInstance(Context con)` | 매니저 싱글턴 인스턴스 획득 |
| `abstract void addDevice(IBYDAutoDevice device)` | 시스템에 커스텀 디바이스 등록 |
| `abstract void removeDevice(IBYDAutoDevice device)` | 시스템에서 디바이스 제거 |
| `int enableDevice(IBYDAutoDevice device)` | 지정 디바이스 활성화 |
| `int disableDevice(IBYDAutoDevice device)` | 지정 디바이스 비활성화 |
| `int setInt(int device, int event, int value)` | 통합 int 쓰기 |
| `int getInt(int device, int event)` | 통합 int 읽기 |
| `int setDouble(int device, int event, double value)` | 통합 double 쓰기 |
| `double getDouble(int device, int event)` | 통합 double 읽기 |
| `int setIntArray(int device, int[] event, int[] value)` | 통합 int 배열 쓰기 |
| `int[] getIntArray(int device, int[] event)` | 통합 int 배열 읽기 |
| `byte[] getBuffer(int device, int event)` | 통합 byte 배열 읽기 |
| `int setDoubleArray(int device, int[] event, double[] value)` | 통합 double 배열 쓰기 |
| `double[] getDoubleArray(int device, int[] event)` | 통합 double 배열 읽기 |

### 4.5 BYDAutoConstants

- **패키지 경로**: `android.hardware.bydauto.BYDAutoConstants`
- **타입**: 공용 클래스
- **역할**: SDK에서 사용되는 전역 상수 및 디바이스 유형 식별자를 정의합니다.

**명령 반환 코드 상수**

| 상수명 | 값 | 설명 |
|---|---|---|
| `BYDAUTO_COMMAND_RESULT_SUCCESS` | 0 | 명령 실행 성공 |
| `BYDAUTO_COMMAND_RESULT_FAILED` | -2147482648 (0x80000020) | 명령 실행 실패 |
| `BYDAUTO_COMMAND_RESULT_TIMEOUT` | -2147482646 (0x80000022) | 명령 실행 타임아웃 |
| `BYDAUTO_COMMAND_RESULT_BUSY` | -2147482647 (0x80000021) | 디바이스 사용 중이라 명령 거부됨 |
| `BYDAUTO_COMMAND_RESULT_INVALID_VALUE` | -2147482645 (0x80000023) | 전달된 파라미터 값이 유효하지 않음 |
| `UNKNOWN_ERROR` | Integer.MIN_VALUE | 알 수 없는 오류 |

---

## 5. 디바이스 모듈 API 상세

다음은 20개 차량 디바이스 서브시스템의 전체 API를 하나씩 상세히 소개합니다. 각 모듈은 다음의 통일된 명명 규칙을 따릅니다.
- 디바이스 클래스: `BYDAutoXXXDevice`
- 리스너: `AbsBYDAutoXXXListener`

### 5.1 공조 (AC)

- **패키지 경로**: `android.hardware.bydauto.ac`
- **디바이스 클래스**: `BYDAutoAcDevice`
- **리스너**: `AbsBYDAutoAcListener`
- **디바이스 유형 상수**: `BYDAUTO_DEVICE_AC = 1000`

**주요 메서드**

| 메서드 | 반환값 | 설명 |
|---|---|---|
| `int start(int setSource)` | int | 공조 켜기 |
| `int stop(int setSource)` | int | 공조 끄기 |
| `int getAcStartState()` | int | 공조 On/Off 상태 조회 |
| `int startRearAc(int setSource)` | int | 후방 공조 켜기 |
| `int stopRearAc(int setSource)` | int | 후방 공조 끄기 |
| `int getRearAcStartState()` | int | 후방 공조 상태 조회 |
| `int setAcControlMode(int setSource, int mode)` | int | 제어 모드 설정 (자동/수동) |
| `int getAcControlMode()` | int | 제어 모드 조회 |
| `int setAcCycleMode(int setSource, int mode)` | int | 순환 모드 설정 (내기순환/외기순환) |
| `int getAcCycleMode()` | int | 순환 모드 조회 |
| `int setAcVentilationState(int setSource, int state)` | int | 환기 상태 설정 |
| `int getAcVentilationState()` | int | 환기 상태 조회 |
| `int setAcTemperatureControlMode(int setSource, int mode)` | int | 온도 제어 모드 설정 |
| `int getAcTemperatureControlMode()` | int | 온도 제어 모드 조회 |
| `int setAcDefrostState(int setSource, int area, int state)` | int | 김서림 제거(디프로스트) 상태 설정 (앞/뒤) |
| `int getAcDefrostState(int area)` | int | 지정 영역 디프로스트 상태 조회 |
| `int getAcCompressorManualSign()` | int | 컴프레서 수동 플래그 조회 |
| `int getAcCompressorMode()` | int | 컴프레서 모드 조회 |
| `int getAcWindModeManualSign()` | int | 풍향 수동 플래그 조회 |
| `int setAcWindMode(int setSource, int mode)` | int | 풍향 모드 설정 |
| `int getAcWindMode()` | int | 풍향 모드 조회 |
| `int getAcWindLevelManualSign()` | int | 풍량 수동 플래그 조회 |
| `int setAcWindLevel(int setSource, int level)` | int | 풍량 단계 설정 (0-7) |
| `int getAcWindLevel()` | int | 풍량 단계 조회 |
| `int getTemperatureUnit()` | int | 온도 단위 조회 (섭씨/화씨) |
| `int setAcTemperature(int type, int value, int tempSource, int unit)` | int | 온도 값 설정 |
| `int getTemprature(int area)` | int | 지정 영역 온도 조회 |

**주요 상수**

| 상수명 | 값 | 설명 |
|---|---|---|
| `AC_POWER_OFF` / `AC_POWER_ON` | 0 / 1 | 공조 On/Off 상태 |
| `AC_CTRLMODE_AUTO` / `AC_CTRLMODE_MANUAL` | 0 / 1 | 자동/수동 제어 모드 |
| `AC_CYCLEMODE_OUTLOOP` / `AC_CYCLEMODE_INLOOP` | 0 / 1 | 외기순환/내기순환 |
| `AC_TEMPERATURE_UNIT_OC` / `AC_TEMPERATURE_UNIT_OF` | 1 / 0 | 섭씨/화씨 |
| `AC_WINDLEVEL_0` ~ `AC_WINDLEVEL_7` | 0~7 | 풍량 단계 |
| `AC_TEMP_IN_CELSIUS_MIN` / `MAX` | 17 / 33 | 실내 온도 설정 범위(°C) |
| `AC_TEMP_OUT_CELSIUS_MIN` / `MAX` | -40 / 50 | 실외 온도 표시 범위(°C) |
| `AC_DEFROST_AREA_FRONT` / `AC_DEFROST_AREA_REAR` | 1 / 2 | 전면 디프로스트/후면 디프로스트 영역 |
| `AC_WINDMODE_FACE` / `FOOT` / `DEFROST` / ... | 1/3/5/... | 풍향: 페이스/풋/디프로스트 등 7종 |

### 5.2 오디오 (Audio)

- **패키지 경로**: `android.hardware.bydauto.audio`
- **디바이스 클래스**: `BYDAutoAudioDevice`
- **디바이스 유형 상수**: `BYDAUTO_DEVICE_AUDIO = 1002`

Audio 디바이스는 기능이 비교적 단순하며, 주로 계기판이나 센터 콘솔에 현재 오디오 재생 진행 상황과 전체 재생 시간을 보고하는 데 사용됩니다.

| 메서드 | 반환값 | 설명 |
|---|---|---|
| `int sendAudioPlayingTime(int h, int m, int s)` | int | 현재 재생 시간 보고 |
| `int sendAudioTotalTime(int h, int m, int s)` | int | 오디오 전체 재생 시간 보고 |

> **참고**: 시간 파라미터 범위 - 시(hour) 0-23, 분(minute) 0-59, 초(second) 0-59

### 5.3 차체 (Bodywork)

- **패키지 경로**: `android.hardware.bydauto.bodywork`
- **디바이스 클래스**: `BYDAutoBodyworkDevice`
- **리스너**: `AbsBYDAutoBodyworkListener`
- **디바이스 유형 상수**: `BYDAUTO_DEVICE_BODYWORK = 1001`

Bodywork 모듈은 가장 정보가 풍부한 모듈 중 하나로, 윈도우, 도어, 스티어링휠, 파워 레벨(전원 단계), 차종 식별 등을 포괄합니다.

**주요 메서드**

| 메서드 | 반환값 | 설명 |
|---|---|---|
| `int getWindowState(int area)` | int | 지정 윈도우 상태 조회 (열림/닫힘) |
| `int getDoorState(int area)` | int | 지정 도어 상태 조회 |
| `int getAutoSystemState()` | int | 차량 시스템 상태 조회 (정상/경계/경계 시작) |
| `double getSteeringWheelValue(int type)` | double | 스티어링휠 각도 또는 회전 속도 조회 |
| `int getPowerLevel()` | int | 전원 단계 조회 (OFF/ACC/ON) |
| `int getBatteryVoltageLevel()` | int | 배터리 전압 등급 조회 (낮음/정상) |
| `String getAutoVIN()` | String | 차량 VIN 코드 조회 |
| `int getMoonRoofConfig()` | int | 선루프 설정 유형 조회 |
| `int getFuelElecLowPower()` | int | 연료/전기 저전력 상태 조회 |
| `int getAlarmState()` | int | 도난 경보 상태 조회 |
| `int getWindowOpenPercent(int area)` | int | 윈도우 개방 비율 조회 (0-100) |
| `int getAutoModelName()` | int | 차종 코드 조회 |
| `int getBatteryCapacity()` | int | 배터리 용량 조회 |

**윈도우/도어 영역 상수**

| 상수명 | 값 | 설명 |
|---|---|---|
| `BODYWORK_CMD_WINDOW_LEFT_FRONT` | 1 | 좌측 앞 윈도우 |
| `BODYWORK_CMD_WINDOW_RIGHT_FRONT` | 2 | 우측 앞 윈도우 |
| `BODYWORK_CMD_WINDOW_LEFT_REAR` | 3 | 좌측 뒤 윈도우 |
| `BODYWORK_CMD_WINDOW_RIGHT_REAR` | 4 | 우측 뒤 윈도우 |
| `BODYWORK_CMD_DOOR_LEFT_FRONT` | 1 | 좌측 앞 도어 |
| `BODYWORK_CMD_DOOR_RIGHT_FRONT` | 2 | 우측 앞 도어 |
| `BODYWORK_CMD_DOOR_LEFT_REAR` | 3 | 좌측 뒤 도어 |
| `BODYWORK_CMD_DOOR_RIGHT_REAR` | 4 | 우측 뒤 도어 |
| `BODYWORK_CMD_DOOR_HOOD` | 5 | 보닛(엔진룸 커버) |
| `BODYWORK_CMD_DOOR_LUGGAGE_DOOR` | 6 | 트렁크 도어 |

### 5.4 충전 (Charging)

- **패키지 경로**: `android.hardware.bydauto.charging`
- **디바이스 클래스**: `BYDAutoChargingDevice`
- **리스너**: `AbsBYDAutoChargingListener`
- **디바이스 유형 상수**: `BYDAUTO_DEVICE_CHARGING = 1009`

Charging 모듈은 신에너지 차종의 핵심 모듈로, 충전 커넥터 상태, 충전 전력, 충전 유형, 예약 충전, 방전 요청 등을 포괄합니다.

| 메서드 | 반환값 | 설명 |
|---|---|---|
| `int getChargerFaultState()` | int | 충전기 고장 상태 조회 |
| `int getChargerWorkState()` | int | 충전기 작동 상태 조회 |
| `double getChargingCapacity()` | double | 충전된 용량 조회 (kWh) |
| `int getChargingType()` | int | 충전 유형 조회 (AC/DC/GB 등) |
| `int[] getChargingRestTime()` | int[] | 남은 충전 시간 조회 [시, 분] |
| `int getChargingCapState(int type)` | int | 충전 커버(캡) 상태 조회 (AC/DC) |
| `int getChargingPortLockRebackState()` | int | 충전 포트 락 피드백 상태 조회 |
| `int getDischargeRequestState()` | int | 방전 요청 상태 조회 |
| `int getChargerState()` | int | 충전기 연결 상태 조회 |
| `int getChargingGunState()` | int | 충전 커넥터(건) 연결 상태 조회 |
| `double getChargingPower()` | double | 실시간 충전 전력 조회 (kW) |
| `int getBatteryManagementDeviceState()` | int | 배터리 관리 장치(BMS) 상태 조회 |
| `int getChargingScheduleEnableState()` | int | 예약 충전 활성화 상태 조회 |
| `int getChargingScheduleState()` | int | 예약 충전 상태 조회 |
| `int getChargingGunNotInsertedState()` | int | 충전 커넥터 미삽입 상태 조회 |
| `int[] getChargingScheduleTime()` | int[] | 예약 충전 시간 조회 [시, 분] |

**충전 유형 상수**

| 상수명 | 값 | 설명 |
|---|---|---|
| `CHARGING_TYPE_DEFAULT` | 1 | 기본 충전 |
| `CHARGING_TYPE_AC` | 2 | 교류(AC) 충전 |
| `CHARGING_TYPE_VTOG` | 3 | VTOG 충전 |
| `CHARGING_TYPE_GB_DC` | 4 | 국가표준(GB) 직류(DC) 충전 |
| `CHARGING_TYPE_GB_NON_DC` | 5 | 국가표준(GB) 비직류 충전 |
| `CHARGING_GUN_STATE_CONNECTED_NONE` | 1 | 충전 커넥터 미연결 |
| `CHARGING_GUN_STATE_CONNECTED_AC` | 2 | AC 충전 커넥터 연결됨 |
| `CHARGING_GUN_STATE_CONNECTED_DC` | 3 | DC 충전 커넥터 연결됨 |
| `CHARGING_GUN_STATE_CONNECTED_AC_DC` | 4 | AC/DC 모두 연결됨 |
| `CHARGING_GUN_STATE_CONNECTED_VTOL` | 5 | VTOL 방전 커넥터 연결됨 |

### 5.5 도어락 (DoorLock)

- **패키지 경로**: `android.hardware.bydauto.doorlock`
- **디바이스 클래스**: `BYDAutoDoorLockDevice`
- **리스너**: `AbsBYDAutoDoorLockListener`
- **디바이스 유형 상수**: `BYDAUTO_DEVICE_DOOR_LOCK = 1041`

| 메서드 | 반환값 | 설명 |
|---|---|---|
| `int getDoorLockStatus(int area)` | int | 지정 영역 도어락 상태 조회 |

**영역 상수**

| 상수명 | 값 | 설명 |
|---|---|---|
| `DOOR_LOCK_AREA_LEFT_FRONT` | 1 | 좌측 앞 도어락 |
| `DOOR_LOCK_AREA_RIGHT_FRONT` | 3 | 우측 앞 도어락 |
| `DOOR_LOCK_AREA_LEFT_REAR` | 2 | 좌측 뒤 도어락 |
| `DOOR_LOCK_AREA_RIGHT_REAR` | 4 | 우측 뒤 도어락 |
| `DOOR_LOCK_AREA_BACK` | 5 | 트렁크락 |
| `DOOR_LOCK_AREA_CHILDLOCK_LEFT` | 6 | 좌측 차일드락 |
| `DOOR_LOCK_AREA_CHILDLOCK_RIGHT` | 7 | 우측 차일드락 |
| `DOOR_LOCK_STATE_UNLOCK` / `LOCK` / `INVALID` | 1/2/0 | 잠금해제/잠금/무효 |

### 5.6 에너지 관리 (Energy)

- **패키지 경로**: `android.hardware.bydauto.energy`
- **디바이스 클래스**: `BYDAutoEnergyDevice`
- **리스너**: `AbsBYDAutoEnergyListener`
- **디바이스 유형 상수**: `BYDAUTO_DEVICE_ENERGY = 1006`

Energy 모듈은 차량의 동력 모드, 주행 모드, 도로 표면 모드 및 발전 상태를 조회하는 데 사용되며, HEV/PHEV/EV 차종의 핵심 상태 진입점입니다.

| 메서드 | 반환값 | 설명 |
|---|---|---|
| `int getEnergyMode()` | int | 에너지 모드 조회 (EV/HEV/연료 등) |
| `int getOperationMode()` | int | 주행 모드 조회 (에코/스포츠) |
| `int getPowerGenerationState()` | int | 발전 상태 조회 |
| `int getPowerGenerationValue()` | int | 발전 전력 값 조회 |
| `int getRoadSurfaceMode()` | int | 도로 표면 모드 조회 |

**에너지 모드 상수**

| 상수명 | 값 | 설명 |
|---|---|---|
| `ENERGY_MODE_STOP` | 0 | 정지 |
| `ENERGY_MODE_EV` | 1 | 순수 전기(EV) 모드 |
| `ENERGY_MODE_FORCE_EV` | 2 | 강제 EV 모드 |
| `ENERGY_MODE_HEV` | 3 | 하이브리드(HEV) 모드 |
| `ENERGY_MODE_FUEL` | 4 | 연료(내연기관) 모드 |
| `ENERGY_MODE_KEEP` | 5 | 유지 모드 |
| `ENERGY_OPERATION_ECONOMY` | 1 | 에코 주행 |
| `ENERGY_OPERATION_SPORT` | 2 | 스포츠 주행 |
| `ENERGY_ROAD_SURFACE_COMMON` | 1 | 일반 도로 |
| `ENERGY_ROAD_SURFACE_SNOW` | 2 | 설원 |
| `ENERGY_ROAD_SURFACE_MUDDY` | 3 | 진흙길 |
| `ENERGY_ROAD_SURFACE_SAND` | 4 | 모래길 |

### 5.7 엔진 (Engine)

- **패키지 경로**: `android.hardware.bydauto.engine`
- **디바이스 클래스**: `BYDAutoEngineDevice`
- **리스너**: `AbsBYDAutoEngineListener`
- **디바이스 유형 상수**: `BYDAUTO_DEVICE_ENGINE = 1012`

| 메서드 | 반환값 | 설명 |
|---|---|---|
| `double getEngineDisplacement()` | double | 엔진 배기량 조회 (L) |
| `String getEngineCode()` | String | 엔진 모델 코드 조회 |
| `int getEnginePower()` | int | 엔진 출력 조회 (kW) |
| `int getEngineSpeed()` | int | 엔진 회전수 조회 (rpm) |
| `int getEngineCoolantLevel()` | int | 냉각수 레벨 상태 조회 |
| `int getOilLevel()` | int | 엔진 오일 레벨 조회 |

**엔진 모델 상수 예시**

| 상수명 | 모델 |
|---|---|
| `ENGINE_TYPE1` | 371QA |
| `ENGINE_TYPE2` | 473QB |
| `ENGINE_TYPE5` | 476ZQA |
| `ENGINE_TYPE6` | 483QA |
| `ENGINE_TYPE10` | 488QA |
| `ENGINE_TYPE15` | 471ZQA |

### 5.8 변속기 (Gearbox)

- **패키지 경로**: `android.hardware.bydauto.gearbox`
- **디바이스 클래스**: `BYDAutoGearboxDevice`
- **리스너**: `AbsBYDAutoGearboxListener`
- **디바이스 유형 상수**: `BYDAUTO_DEVICE_GEARBOX = 1011`

| 메서드 | 반환값 | 설명 |
|---|---|---|
| `int getGearboxType()` | int | 변속기 유형 조회 (MT/AT/CVT/DCT) |
| `int getGearboxAutoModeType()` | int | 오토 모드 조회 (P/R/N/D/M/S) |
| `int getGearboxManualModeLevel()` | int | 수동 모드 현재 단수 조회 |
| `String getGearboxCode()` | String | 변속기 모델 코드 조회 |
| `int getBrakeFluidLevel()` | int | 브레이크액 레벨 조회 |
| `int getParkBrakeSwitch()` | int | 파킹 브레이크 스위치 상태 조회 |
| `int getBrakePedalState()` | int | 브레이크 페달 상태 조회 |

**변속단 상수**

| 상수명 | 값 | 설명 |
|---|---|---|
| `GEARBOX_AUTO_MODE_P` | 1 | 주차(P) |
| `GEARBOX_AUTO_MODE_R` | 2 | 후진(R) |
| `GEARBOX_AUTO_MODE_N` | 3 | 중립(N) |
| `GEARBOX_AUTO_MODE_D` | 4 | 전진(D) |
| `GEARBOX_AUTO_MODE_M` | 5 | 수동 모드 |
| `GEARBOX_AUTO_MODE_S` | 6 | 스포츠 모드 |
| `GEARBOX_TYPE_MT` | 0 | 수동변속기 |
| `GEARBOX_TYPE_AT` | 2 | 자동변속기 |
| `GEARBOX_TYPE_CVT` | 3 | 무단변속기 |
| `GEARBOX_TYPE_DCT` | 4 | 듀얼클러치변속기 |

### 5.9 계기판 (Instrument)

- **패키지 경로**: `android.hardware.bydauto.instrument`
- **디바이스 클래스**: `BYDAutoInstrumentDevice`
- **리스너**: `AbsBYDAutoInstrumentListener`
- **디바이스 유형 상수**: `BYDAUTO_DEVICE_INSTRUMENT = 1007`

Instrument 모듈은 SDK에서 상수가 가장 풍부한 모듈로, 계기판과의 상호작용을 담당하며 고장 정보, 정비 알림, 내비게이션 안내, 멀티미디어 상태, 단위 설정 등을 포함합니다.

| 메서드 | 반환값 | 설명 |
|---|---|---|
| `int getMalfunctionInfo(int typeName)` | int | 지정 유형 고장 정보 조회 |
| `int getUnit(int unitName)` | int | 지정 단위 설정 조회 |
| `int setUnit(int unitName, int unitValue)` | int | 단위 설정 |
| `int getMaintenanceInfo(int typeName)` | int | 정비 정보 조회 |
| `int setMaintenanceInfo(int typeName, int infoValue)` | int | 정비 정보 설정 |
| `int sendMusicState(int state)` | int | 음악 재생 상태를 계기판에 전송 |
| `int sendMusicPlaybackProgress(int progress)` | int | 재생 진행률 전송 (0-100) |
| `int sendMusicSource(int source)` | int | 음악 소스 전송 |
| `int getAlarmBuzzleState()` | int | 경보 부저 상태 조회 |
| `double getExternalChargingPower()` | double | 외부 접속 충전 전력 조회 |
| `int sendSimpleGuidanceInfo(int simpleType, int distance)` | int | 간단 내비게이션 안내 정보 전송 |
| `int sendCameraGuidanceInfo(int cameraType, int distance, int state)` | int | 카메라(단속) 안내 정보 전송 |
| `int sendSafeGuidanceInfo(int safeType, int distance, int state)` | int | 안전 운전 안내 정보 전송 |
| `int sendRestRouteInfo(int h, int m, long mileage)` | int | 남은 경로 정보 전송 |
| `int sendNextPathName(String name)` | int | 다음 경로명 전송 |
| `int sendAddressInfo(int target, String address)` | int | 주소 정보 전송 (집/회사) |
| `int sendMusicName(String name)` | int | 곡명을 계기판에 전송 |
| `int getNaviDestinationCommand()` | int | 내비게이션 목적지 명령 조회 |
| `int sendAutoNaviStatus(int status)` | int | 내비게이션 상태 전송 |
| `int getRoadNameCheckState()` | int | 도로명 확인 상태 조회 |

**고장 유형 상수 (MALFUNCTION_*)**

| 상수명 | 값 | 설명 |
|---|---|---|
| `MALFUNCTION_INSTRUMENT_DISPLAY` | 1 | 계기판 디스플레이 고장 |
| `MALFUNCTION_MACHINE_OIL_LOW_PRESSURE` | 2 | 오일 압력 낮음 |
| `MALFUNCTION_PARKING_BRAKE` | 3 | 파킹 브레이크 고장 |
| `MALFUNCTION_CHARGING_SYSTEM` | 4 | 충전 시스템 고장 |
| `MALFUNCTION_ENGINE` | 5 | 엔진 고장 |
| `MALFUNCTION_ABS_SYSTEM` | 6 | ABS 시스템 고장 |
| `MALFUNCTION_ESP` | 7 | ESP 고장 |
| `MALFUNCTION_QUICK_AIR_LEAK` | 8 | 급속 공기 누출 |
| `MALFUNCTION_HIGH_WATER_TEMPERATURE` | 9 | 수온 과열 |
| `MALFUNCTION_ELECTRIC_PARKING_BRAKE` | 10 | 전자식 파킹 브레이크 고장 |
| `MALFUNCTION_SRS` | 11 | 에어백(SRS) 고장 |
| `MALFUNCTION_EPS` | 12 | 전동 파워 스티어링(EPS) 고장 |
| `MALFUNCTION_TYRE_PRESSURE` | 13 | 타이어 압력 고장 |
| `MALFUNCTION_SVS` | 14 | SVS 고장 |
| `MALFUNCTION_HIGH_MOTOR_TEMPERATURE` | 15 | 모터 과열 |
| `MALFUNCTION_BATTERY` | 16 | 배터리 고장 |
| `MALFUNCTION_HIGH_BATTERY_TEMPERATURE` | 17 | 배터리 과열 |
| `MALFUNCTION_POWER_SYSTEM` | 18 | 동력 시스템 고장 |
| `MALFUNCTION_OK` | 19 | 시스템 정상 |
| `MALFUNCTION_EV` | 20 | EV 시스템 고장 |
| `MALFUNCTION_HEV` | 21 | HEV 시스템 고장 |
| `MALFUNCTION_SMART_KEY` | 22 | 스마트키 고장 |
| `MALFUNCTION_FRONT_BELT` | 23 | 전방 안전벨트 고장 |

### 5.10 조명 (Light)

- **패키지 경로**: `android.hardware.bydauto.light`
- **디바이스 클래스**: `BYDAutoLightDevice`
- **리스너**: `AbsBYDAutoLightListener`
- **디바이스 유형 상수**: `BYDAUTO_DEVICE_LIGHT = 1004`

| 메서드 | 반환값 | 설명 |
|---|---|---|
| `int getLightStatus(int type)` | int | 지정 조명 상태 조회 |
| `int getLightAutoStatus()` | int | 오토 헤드라이트 상태 조회 |
| `int getAFSSwitch()` | int | AFS(어댑티브 헤드램프) 스위치 상태 조회 |

**조명 유형 상수**

| 상수명 | 값 | 설명 |
|---|---|---|
| `LIGHT_OFF` / `LIGHT_ON` | 0 / 1 | 꺼짐/켜짐 |
| `LIGHT_SIDE` | 1 | 차폭등 |
| `LIGHT_LOW_BEAM` | 2 | 하향등(로우빔) |
| `LIGHT_HIGH_BEAM` | 3 | 상향등(하이빔) |
| `LIGHT_LEFT_TURN_SIGNAL` | 4 | 좌측 방향지시등 |
| `LIGHT_RIGHT_TURN_SIGNAL` | 5 | 우측 방향지시등 |
| `LIGHT_FRONT_FOG` | 6 | 전방 안개등 |
| `LIGHT_REAR_FOG` | 7 | 후방 안개등 |
| `LIGHT_FOOT` | 8 | 풋 조명등 |
| `LIGHT_GROUP_LEFT` / `LIGHT_GROUP_RIGHT` | 0 / 1 | 좌측 조명그룹/우측 조명그룹 |

### 5.11 멀티미디어 (Multimedia)

- **패키지 경로**: `android.hardware.bydauto.multimedia`
- **디바이스 클래스**: `BYDAutoMultimediaDevice`
- **리스너**: `AbsBYDAutoMultimediaListener`
- **디바이스 유형 상수**: `BYDAUTO_DEVICE_MULTIMEDIA` (SDK 내 명시적 독립 상수 미정의, 멀티미디어 클래스에서 직접 사용)

Multimedia 모듈은 차량용 멀티미디어 시스템에 대한 제어 및 상태 조회 기능을 제공하며, 라디오, CD/DVD, USB, 블루투스, 로컬 음원/영상 등 다양한 소스를 지원합니다.

| 메서드 | 반환값 | 설명 |
|---|---|---|
| `int getMediaType()` | int | 현재 미디어 유형 조회 |
| `int getPlayMode()` | int | 재생 모드 조회 |
| `int getPlayState()` | int | 재생 상태 조회 (재생/일시정지/정지) |
| `MediaInfo getPlayMediaInfo()` | MediaInfo | 현재 재생 중인 미디어 정보 조회 |
| `int controlMedia(int mode, int action, MediaControlParam param)` | int | 미디어 재생 제어 |

**미디어 유형 상수**

| 상수명 | 값 | 설명 |
|---|---|---|
| `MULTIMEDIA_TYPE_AM` | 0 | AM 라디오 |
| `MULTIMEDIA_TYPE_FM` | 1 | FM 라디오 |
| `MULTIMEDIA_TYPE_CD` | 2 | CD |
| `MULTIMEDIA_TYPE_VCD` | 3 | VCD |
| `MULTIMEDIA_TYPE_DVD` | 4 | DVD |
| `MULTIMEDIA_TYPE_TV` | 5 | TV |
| `MULTIMEDIA_TYPE_AUX` | 7 | AUX 입력 |
| `MULTIMEDIA_TYPE_LOCAL_AUDIO` | 8 | 로컬 오디오 |
| `MULTIMEDIA_TYPE_LOCAL_VIDEO` | 9 | 로컬 비디오 |
| `MULTIMEDIA_TYPE_USB_AUDIO` | 10 | USB 오디오 |
| `MULTIMEDIA_TYPE_USB_VIDEO` | 11 | USB 비디오 |
| `MULTIMEDIA_TYPE_SD_AUDIO` | 12 | SD 오디오 |
| `MULTIMEDIA_TYPE_SD_VIDEO` | 13 | SD 비디오 |
| `MULTIMEDIA_TYPE_HD_AUDIO` | 14 | 고음질 오디오 |
| `MULTIMEDIA_TYPE_HD_VIDEO` | 15 | 고화질 비디오 |
| `MULTIMEDIA_TYPE_BT` | 16 | 블루투스 뮤직 |
| `MULTIMEDIA_TYPE_ROBOT` | 17 | 음성 로봇(비서) |

**재생 제어 액션 상수**

| 상수명 | 값 | 설명 |
|---|---|---|
| `ACTION_ENTER` | 0 | 진입 |
| `ACTION_PLAY` | 1 | 재생 |
| `ACTION_PAUSE` | 2 | 일시정지 |
| `ACTION_PLAY_PRE` | 3 | 이전 곡 |
| `ACTION_PLAY_NEXT` | 4 | 다음 곡 |
| `ACTION_SET_PLAY_PATTERN` | 5 | 재생 모드 설정 |
| `ACTION_AUTO_SEARCH` | 6 | 자동 검색 |
| `ACTION_PLAY_PRE_FREQ` | 7 | 이전 주파수 |
| `ACTION_PLAY_NEXT_FREQ` | 8 | 다음 주파수 |
| `ACTION_CANCEL_RADIO_SEARCH` | 9 | 라디오 검색 취소 |

### 5.12 어라운드뷰 (Panorama)

- **패키지 경로**: `android.hardware.bydauto.panorama`
- **디바이스 클래스**: `BYDAutoPanoramaDevice`
- **리스너**: `AbsBYDAutoPanoramaListener`
- **디바이스 유형 상수**: `BYDAUTO_DEVICE_PANORAMA = 1031`

| 메서드 | 반환값 | 설명 |
|---|---|---|
| `int getPanoWorkState()` | int | 어라운드뷰 작동 상태 조회 |
| `int getPanoOutputState()` | int | 어라운드뷰 출력 상태 조회 |
| `int getPanoOutputSignal()` | int | 출력 신호 유형 조회 (CVBS/LVDS) |
| `int getBackLineConfig()` | int | 후방 보조선 설정 조회 |
| `int getPanoramaOnlineState()` | int | 어라운드뷰 시스템 온라인 상태 조회 |
| `int getPanoRotation()` | int | 화면 회전 방향 조회 |
| `int getDisplayMode()` | int | 디스플레이 모드 조회 |

**디스플레이 모드 상수**

| 상수명 | 값 | 설명 |
|---|---|---|
| `DISPLAY_MODE_PANORAMA` | 0 | 어라운드뷰 모드 |
| `DISPLAY_MODE_FULL_SCREEN` | 1 | 전체화면 모드 |
| `DISPLAY_MODE_WIDGET` | 3 | 위젯 모드 |
| `DISPLAY_MODE_RF_REVERSE` | 4 | 우측 전방 후진 모드 |
| `DISPLAY_MODE_REVERSE` | 5 | 후진 모드 |
| `PANORAMA_OUTPUT_OFF` | 1 | 출력 끄기 |
| `PANORAMA_OUTPUT_FRONT` | 2 | 전방 뷰 |
| `PANORAMA_OUTPUT_REAR` | 3 | 후방 뷰 |
| `PANORAMA_OUTPUT_LEFT` | 4 | 좌측 뷰 |
| `PANORAMA_OUTPUT_RIGHT` | 5 | 우측 뷰 |
| `PANORAMA_OUTPUT_COMPOSE` | 6 | 합성 뷰 |

### 5.13 PM2.5

- **패키지 경로**: `android.hardware.bydauto.pm2p5`
- **디바이스 클래스**: `BYDAutoPM2p5Device`
- **리스너**: `AbsBYDAutoPM2p5Listener`
- **디바이스 유형 상수**: `BYDAUTO_DEVICE_PM2P5 = 1008`

| 메서드 | 반환값 | 설명 |
|---|---|---|
| `int getPM2p5OnlineState()` | int | PM2.5 센서 온라인 상태 조회 |
| `int[] getPM2p5CheckState()` | int[] | 검사 상태 조회 [실내, 실외] |
| `int[] getPM2p5Value()` | int[] | PM2.5 수치 조회 [실내, 실외] |
| `int[] getPM2p5Level()` | int[] | 공기질 등급 조회 [실내, 실외] |

**공기질 등급 상수**

| 상수명 | 값 | 설명 |
|---|---|---|
| `PM2P5_LEVEL_INVALID` | 0 | 무효 |
| `PM2P5_LEVEL_EXCELLENT` | 1 | 매우 좋음 |
| `PM2P5_LEVEL_GOOD` | 2 | 좋음 |
| `PM2P5_LEVEL_LOW_GRADE` | 3 | 경도 오염 |
| `PM2P5_LEVEL_MIDDLE` | 4 | 중등도 오염 |
| `PM2P5_LEVEL_HEAVY` | 5 | 심각한 오염 |
| `PM2P5_LEVEL_SERIOUS` | 6 | 매우 심각한 오염 |

### 5.14 레이더 (Radar)

- **패키지 경로**: `android.hardware.bydauto.radar`
- **디바이스 클래스**: `BYDAutoRadarDevice`
- **리스너**: `AbsBYDAutoRadarListener`
- **디바이스 유형 상수**: `BYDAUTO_DEVICE_RADAR = 1025`

| 메서드 | 반환값 | 설명 |
|---|---|---|
| `int getRadarProbeState(int area)` | int | 지정 영역 레이더 프로브 상태 조회 |
| `int[] getAllRadarProbeStates()` | int[] | 전체 레이더 프로브 상태 조회 |
| `int getReverseRadarSwitchState()` | int | 후방 주차 레이더 스위치 상태 조회 |

**레이더 영역 상수**

| 상수명 | 값 | 설명 |
|---|---|---|
| `RADAR_AREA_LEFT_FRONT` | 1 | 좌측 전방 |
| `RADAR_AREA_RIGHT_FRONT` | 2 | 우측 전방 |
| `RADAR_AREA_LEFT_REAR` | 3 | 좌측 후방 |
| `RADAR_AREA_RIGHT_REAR` | 4 | 우측 후방 |
| `RADAR_AREA_LEFT` | 5 | 좌측 |
| `RADAR_AREA_RIGHT` | 6 | 우측 |
| `RADAR_AREA_FRONT_LEFT_MID` | 7 | 전방 좌중앙 |
| `RADAR_AREA_FRONT_RIGHT_MID` | 8 | 전방 우중앙 |

**프로브 상태 상수**

| 상수명 | 값 | 설명 |
|---|---|---|
| `RADAR_PROBE_STATE_ABNORMAL` | 0 | 비정상 |
| `RADAR_PROBE_STATE_SAFE` | 1 | 안전 거리 |
| `RADAR_PROBE_STATE_GREEN` | 2 | 녹색 경고 |
| `RADAR_PROBE_STATE_YELLOW` | 3 | 황색 경고 |
| `RADAR_PROBE_STATE_RED` | 4 | 적색 경고 |

### 5.15 안전벨트 (SafetyBelt)

- **패키지 경로**: `android.hardware.bydauto.safetybelt`
- **디바이스 클래스**: `BYDAutoSafetyBeltDevice`
- **리스너**: `AbsBYDAutoSafetyBeltListener`
- **디바이스 유형 상수**: `BYDAUTO_DEVICE_SAFETY_BELT = 1042`

| 메서드 | 반환값 | 설명 |
|---|---|---|
| `int getSafetyBeltStatus(int area)` | int | 지정 좌석 안전벨트 상태 조회 |
| `int getPassengerStatus(int area)` | int | 지정 좌석 탑승자 감지 상태 조회 |

**상수**

| 상수명 | 값 | 설명 |
|---|---|---|
| `SAFETY_BELT_AREA_MAIN` | 1 | 운전석 |
| `SAFETY_BELT_AREA_DEPUTY` | 2 | 조수석 |
| `SAFETY_BELT_STATE_UNLOCK` / `LOCK` / `INVALID` | 0/1/2 | 미착용/착용/무효 |
| `SAFETY_BELT_PASSENGER_STATE_NOBODY` / `SOMEBODY` / `INVALID` | 0/1/2 | 미탑승/탑승/무효 |

### 5.16 센서 (Sensor)

- **패키지 경로**: `android.hardware.bydauto.sensor`
- **디바이스 클래스**: `BYDAutoSensorDevice`
- **리스너**: `AbsBYDAutoSensorListener`
- **디바이스 유형 상수**: `BYDAUTO_DEVICE_SENSOR = 1043`

| 메서드 | 반환값 | 설명 |
|---|---|---|
| `int getLightIntensity()` | int | 주변광 강도 등급 조회 (1-5) |

**조도 강도 등급**

| 상수명 | 값 | 설명 |
|---|---|---|
| `LIGHT_INTENSITY_LEVEL1` | 1 | 가장 어두움 |
| `LIGHT_INTENSITY_LEVEL2` | 2 | 어두운 편 |
| `LIGHT_INTENSITY_LEVEL3` | 3 | 적당함 |
| `LIGHT_INTENSITY_LEVEL4` | 4 | 밝은 편 |
| `LIGHT_INTENSITY_LEVEL5` | 5 | 가장 밝음 |

### 5.17 시스템 설정 (Setting)

- **패키지 경로**: `android.hardware.bydauto.setting`
- **디바이스 클래스**: `BYDAutoSettingDevice`
- **리스너**: `AbsBYDAutoSettingListener`
- **디바이스 유형 상수**: `BYDAUTO_DEVICE_SETTING = 1023`

Setting은 API가 가장 풍부한 모듈 중 하나로, 공조 터널 순환, 에너지 회수 강도, SOC 목표값, 스티어링 파워, 사이드미러 접이, 시트 열선/통풍, 무드등, 과속 자동잠금, 언어 설정 등 대량의 차량 설정을 포괄합니다.

**주요 메서드 (일부)**

| 메서드 | 반환값 | 설명 |
|---|---|---|
| `int setACBTWind(int value)` | int | 공조 터널 순환 설정 |
| `int getACBTWind()` | int | 공조 터널 순환 상태 조회 |
| `int setEnergyFeedback(int value)` | int | 에너지 회수 강도 설정 |
| `int getEnergyFeedback()` | int | 에너지 회수 강도 조회 |
| `int setSOCTarget(int value)` | int | SOC 목표값 설정 (15-70) |
| `int getSOCTarget()` | int | SOC 목표값 조회 |
| `int setSteerAssis(int value)` | int | 스티어링 보조 모드 설정 |
| `int getSteerAssis()` | int | 스티어링 보조 모드 조회 |
| `int setPM25Power(int value)` | int | PM2.5 전원 설정 |
| `int getPM25Power()` | int | PM2.5 전원 상태 조회 |
| `int setBackHomeLightDelayValue(int value)` | int | 웰컴 라이트(집 밝히기) 지연 설정 |
| `int getBackHomeLightDelayValue()` | int | 웰컴 라이트 지연 조회 |
| `int setLockOff(int value)` | int | 잠금 해제 도어 수 설정 |
| `int getLockOff()` | int | 잠금 해제 도어 설정 조회 |
| `int setOverspeedLock(int value)` | int | 과속 자동잠금 설정 |
| `int getOverspeedLock()` | int | 과속 자동잠금 상태 조회 |
| `int setLanguage(int value)` | int | 시스템 언어 설정 |
| `int getLanguage()` | int | 시스템 언어 조회 |
| `int hasFeature(String feature)` | int | 차량의 특정 기능 지원 여부 조회 |
| `int getEngineOilLevel()` | int | 엔진 오일 레벨 조회 |
| `int setBackDoorOpenedHeight(int height)` | int | 전동 테일게이트 개방 높이 설정 (15-100) |
| `int getBackDoorOpenedHeight()` | int | 전동 테일게이트 개방 높이 조회 |

**언어 상수**

| 상수명 | 값 | 설명 |
|---|---|---|
| `SET_LANGUAGE_SIMPLE_CHINESE` | 1 | 중국어 간체 |
| `SET_LANGUAGE_COMPLEX_CHINESE` | 2 | 중국어 번체 |
| `SET_LANGUAGE_ENGLISH` | 3 | 영어 |
| `SET_LANGUAGE_RUSSIAN` | 4 | 러시아어 |
| `SET_LANGUAGE_ARABIC` | 5 | 아랍어 |

**기능(Feature) 조회 상수**

| 상수명 | 기능 설명 |
|---|---|
| `FEATURE_BACK_DOOR` | 전동 테일게이트 |
| `FEATURE_DRIVER_SEAT_HEATING` | 운전석 시트 열선 |
| `FEATURE_DRIVER_SEAT_VENTILATING` | 운전석 시트 통풍 |
| `FEATURE_PASSENGER_SEAT_HEATING` | 조수석 시트 열선 |
| `FEATURE_PASSENGER_SEAT_VENTILATING` | 조수석 시트 통풍 |
| `FEATURE_FOUR_WHEEL_DRIVE` | 4륜구동 사양 |
| `FEATURE_INSIDE_LIGHT` | 실내 조명 |
| `FEATURE_INTERIOR_ATMOSPHERE_LAMP` | 실내 무드등 |
| `FEATURE_OVERSPEED_LOCKING` | 과속 자동잠금 |
| `FEATURE_REARVIEW_MIRROR_FOLLOW_UP` | 사이드미러 연동(오토폴딩 등) |

### 5.18 속도 (Speed)

- **패키지 경로**: `android.hardware.bydauto.speed`
- **디바이스 클래스**: `BYDAutoSpeedDevice`
- **리스너**: `AbsBYDAutoSpeedListener`
- **디바이스 유형 상수**: `BYDAUTO_DEVICE_SPEED = 1013`

| 메서드 | 반환값 | 설명 |
|---|---|---|
| `double getCurrentSpeed()` | double | 현재 차속 조회 (km/h, 0.0-282.0) |
| `int getAccelerateDeepness()` | int | 가속 페달 깊이 비율 조회 (0-100) |
| `int getBrakeDeepness()` | int | 브레이크 페달 깊이 비율 조회 (0-100) |

### 5.19 주행 통계 (Statistic)

- **패키지 경로**: `android.hardware.bydauto.statistic`
- **디바이스 클래스**: `BYDAutoStatisticDevice`
- **리스너**: `AbsBYDAutoStatisticListener`
- **디바이스 유형 상수**: `BYDAUTO_DEVICE_STATISTIC = 1014`

Statistic 모듈은 차량의 누적 주행 데이터, 에너지 소비 통계, 순간 연비/전비, 주행 가능 거리 등 핵심 정보를 제공합니다.

| 메서드 | 반환값 | 설명 |
|---|---|---|
| `int getTotalMileageValue()` | int | 총 주행 거리 조회 (km) |
| `double getTotalFuelConValue()` | double | 누적 연료 소비량 조회 (L) |
| `double getTotalElecConValue()` | double | 누적 전력 소비량 조회 (kWh) |
| `double getDrivingTimeValue()` | double | 누적 주행 시간 조회 (h) |
| `double getLastFuelConPHMValue()` | double | 지난 100km당 연비 조회 (L/100km) |
| `double getTotalFuelConPHMValue()` | double | 전체 평균 100km당 연비 조회 |
| `double getLastElecConPHMValue()` | double | 지난 100km당 전비 조회 (kWh/100km) |
| `double getTotalElecConPHMValue()` | double | 전체 평균 100km당 전비 조회 |
| `int getElecDrivingRangeValue()` | int | 순수 전기 주행 가능 거리 조회 (km) |
| `int getFuelDrivingRangeValue()` | int | 연료 주행 가능 거리 조회 (km) |
| `int getFuelPercentageValue()` | int | 연료 잔량 비율 조회 (0-100) |
| `double getElecPercentageValue()` | double | 배터리 잔량 비율 조회 (0.0-100.0) |
| `int getKeyBatteryLevel()` | int | 스마트키 배터리 잔량 상태 조회 |
| `int getEVMileageValue()` | int | EV 모드 주행 거리 조회 |
| `int getWaterTemperature()` | int | 엔진 수온 조회 (°C) |
| `double getInstantElecConValue()` | double | 순간 전비 조회 |
| `double getInstantFuelConValue()` | double | 순간 연비 조회 |

### 5.20 시간 (Time)

- **패키지 경로**: `android.hardware.bydauto.time`
- **디바이스 클래스**: `BYDAutoTimeDevice`
- **리스너**: `AbsBYDAutoTimeListener`
- **디바이스 유형 상수**: `BYDAUTO_DEVICE_TIME = 1024`

| 메서드 | 반환값 | 설명 |
|---|---|---|
| `int setDate(int year, int month, int day, int weekday)` | int | 날짜 설정 |
| `int setTime(int hour, int minute, int second)` | int | 시간 설정 |
| `int[] getTime()` | int[] | 현재 시간 조회 [년,월,일,시,분,초,요일,시간대] |
| `int setTimeFormat(int value)` | int | 시간 형식 설정 (12시간제/24시간제) |
| `int getTimeFormat()` | int | 시간 형식 조회 |

**시간 상수**

| 상수명 | 값 | 설명 |
|---|---|---|
| `TIME_FORMAT_24H_OFF` | 0 | 12시간제 |
| `TIME_FORMAT_24H_ON` | 1 | 24시간제 |
| `TIME_YEAR_MIN` / `MAX` | 2001 / 2255 | 연도 유효 범위 |
| `TIME_MONTH_MIN` / `MAX` | 1 / 12 | 월 유효 범위 |
| `TIME_DAY_MIN` / `MAX` | 1 / 31 | 일 유효 범위 |
| `TIME_HOUR_MIN` / `MAX` | 0 / 23 | 시(hour) 유효 범위 |
| `TIME_MINUTE_MIN` / `MAX` | 0 / 59 | 분(minute) 유효 범위 |
| `TIME_SECOND_MIN` / `MAX` | 0 / 59 | 초(second) 유효 범위 |

### 5.21 타이어 (Tyre)

- **패키지 경로**: `android.hardware.bydauto.tyre`
- **디바이스 클래스**: `BYDAutoTyreDevice`
- **리스너**: `AbsBYDAutoTyreListener`
- **디바이스 유형 상수**: `BYDAUTO_DEVICE_TYRE = 1016`

| 메서드 | 반환값 | 설명 |
|---|---|---|
| `int getTyreSystemState()` | int | 타이어 압력 모니터링 시스템(TPMS) 상태 조회 |
| `int getTyreTemperatureState()` | int | 타이어 온도 상태 조회 |
| `int getTyreBatteryState()` | int | 타이어 압력 센서 배터리 상태 조회 |
| `int getTyreAirLeakState(int area)` | int | 지정 타이어 공기 누출 상태 조회 |
| `int getTyreSignalState(int area)` | int | 지정 타이어 신호 상태 조회 |
| `int getTyrePressureState(int area)` | int | 지정 타이어 압력 상태 조회 |
| `int getTyrePressureValue(int area)` | int | 지정 타이어 압력 값 조회 |

**타이어 영역 상수**

| 상수명 | 값 | 설명 |
|---|---|---|
| `TYRE_COMMAND_AREA_LEFT_FRONT` | 1 | 좌측 앞 타이어 |
| `TYRE_COMMAND_AREA_RIGHT_FRONT` | 2 | 우측 앞 타이어 |
| `TYRE_COMMAND_AREA_LEFT_REAR` | 3 | 좌측 뒤 타이어 |
| `TYRE_COMMAND_AREA_RIGHT_REAR` | 4 | 우측 뒤 타이어 |

**상태 상수**

| 상수명 | 값 | 설명 |
|---|---|---|
| `TYRE_SYSTEM_STATE_NORMAL` | 0 | 정상 |
| `TYRE_SYSTEM_STATE_SELF_CHECKING` | 1 | 자가진단 중 |
| `TYRE_SYSTEM_STATE_SIGNAL_ANOMAL` | 2 | 신호 이상 |
| `TYRE_SYSTEM_STATE_BREAKDOWN` | 3 | 고장 |
| `TYRE_SYSTEM_STATE_MASKED` | 4 | 마스킹(차단)됨 |
| `TYRE_PRESSURE_STATE_NORMAL` | 0 | 압력 정상 |
| `TYRE_PRESSURE_STATE_OVERPRESSURE` | 1 | 압력 과다 |
| `TYRE_PRESSURE_STATE_UNDERPRESSURE` | 2 | 압력 부족 |
| `TYRE_TEMPERATURE_STATE_NORMAL` | 0 | 온도 정상 |
| `TYRE_TEMPERATURE_STATE_SUPER_HIGH` | 1 | 온도 매우 높음 |
| `TYRE_TEMPERATURE_STATE_HIGH` | 2 | 온도 다소 높음 |
| `TYRE_TEMPERATURE_STATE_SLEEP` | 3 | 슬립(대기) 상태 |
| `TYRE_AIR_LEAK_STATE_NORMAL` | 0 | 누출 없음 |
| `TYRE_AIR_LEAK_STATE_QUICK` | 1 | 급속 누출 |
| `TYRE_AIR_LEAK_STATE_SLOW` | 2 | 완속 누출 |

---

## 6. 전역 상수 참조표

다음은 `BYDAutoConstants`에 정의된 전체 디바이스 유형 ID를 정리한 것으로, 모듈 간 호출 시 참고용으로 제공됩니다.

| 상수명 | 값 | 대응 모듈 |
|---|---|---|
| `BYDAUTO_DEVICE_AC` | 1000 | 공조 (AC) |
| `BYDAUTO_DEVICE_BODYWORK` | 1001 | 차체 (Bodywork) |
| `BYDAUTO_DEVICE_AUDIO` | 1002 | 오디오 (Audio) |
| `BYDAUTO_DEVICE_LIGHT` | 1004 | 조명 (Light) |
| `BYDAUTO_DEVICE_ENERGY` | 1006 | 에너지 관리 (Energy) |
| `BYDAUTO_DEVICE_INSTRUMENT` | 1007 | 계기판 (Instrument) |
| `BYDAUTO_DEVICE_PM2P5` | 1008 | PM2.5 |
| `BYDAUTO_DEVICE_CHARGING` | 1009 | 충전 (Charging) |
| `BYDAUTO_DEVICE_GEARBOX` | 1011 | 변속기 (Gearbox) |
| `BYDAUTO_DEVICE_ENGINE` | 1012 | 엔진 (Engine) |
| `BYDAUTO_DEVICE_SPEED` | 1013 | 속도 (Speed) |
| `BYDAUTO_DEVICE_STATISTIC` | 1014 | 주행 통계 (Statistic) |
| `BYDAUTO_DEVICE_TYRE` | 1016 | 타이어 (Tyre) |
| `BYDAUTO_DEVICE_LOCATION` | 1017 | 위치(Location) - 본 JAR에는 미포함 |
| `BYDAUTO_DEVICE_SETTING` | 1023 | 시스템 설정 (Setting) |
| `BYDAUTO_DEVICE_TIME` | 1024 | 시간 (Time) |
| `BYDAUTO_DEVICE_RADAR` | 1025 | 레이더 (Radar) |
| `BYDAUTO_DEVICE_PANORAMA` | 1031 | 어라운드뷰 (Panorama) |
| `BYDAUTO_DEVICE_DOOR_LOCK` | 1041 | 도어락 (DoorLock) |
| `BYDAUTO_DEVICE_SAFETY_BELT` | 1042 | 안전벨트 (SafetyBelt) |
| `BYDAUTO_DEVICE_SENSOR` | 1043 | 센서 (Sensor) |
| `BYDAUTO_DEVICE_WIPER` | 1046 | 와이퍼 (Wiper) - 본 JAR에는 미포함 |
| `BYDAUTO_DEVICE_REAR_VIEW_MIRROR` | 1047 | 사이드미러 - 본 JAR에는 미포함 |

---

## 7. 모범 사례 및 주의사항

### 7.1 예외 처리
모든 디바이스 API는 int 상태 코드(또는 double/배열)를 반환합니다. 호출 후에는 반드시 반환값이 `*_COMMAND_SUCCESS (0)`인지 확인해야 합니다. 비동기 이벤트의 경우, 시스템 리소스 소모를 줄이기 위해 폴링 대신 리스너 콜백에서 상태 변경을 처리해야 합니다.

```java
int result = acDevice.setAcWindLevel(AC_CTRL_SOURCE_UI_KEY, AC_WINDLEVEL_3);
if (result != BYDAutoAcDevice.AC_COMMAND_SUCCESS) {
    Log.w("TAG", "풍량 설정 실패, 오류 코드: " + result);
}
```

### 7.2 리스너 생명주기 관리
Activity 또는 Service의 `onResume`/`onStart`에서 리스너를 등록하고, `onPause`/`onStop`에서 해제하여 메모리 누수 및 콜백 중복 호출을 방지해야 합니다.

```java
@Override protected void onResume() {
    super.onResume();
    acDevice.registerListener(mAcListener);
}

@Override protected void onPause() {
    super.onPause();
    acDevice.unregisterListener(mAcListener);
}
```

### 7.3 다중 디바이스 연동
여러 디바이스의 상태를 동시에 조회해야 하는 경우, 다수의 디바이스 인스턴스를 빈번하게 생성하여 리소스를 낭비하는 것을 피하기 위해 `BYDAutoDeviceManager`의 통합 읽기/쓰기 인터페이스를 사용하는 것을 권장합니다.

### 7.4 차종 적응(호환성)
차종별로 지원되는 기능에 차이가 있습니다. 특정 기능을 제어하거나 조회하기 전에, 애플리케이션의 호환성을 높이기 위해 먼저 `BYDAutoSettingDevice.hasFeature(String)`를 통해 해당 차종이 이 기능을 지원하는지 조회할 것을 권장합니다.

```java
int hasSeatHeat = settingDevice.hasFeature(BYDAutoSettingDevice.FEATURE_DRIVER_SEAT_HEATING);
if (hasSeatHeat == BYDAutoSettingDevice.DEVICE_HAS_THE_FEATURE) {
    // 시트 열선 관련 로직 실행
}
```

### 7.5 온도 단위 처리
공조 모듈은 섭씨(°C)와 화씨(°F)를 모두 지원합니다. `setAcTemperature` 호출 시 반드시 단위 파라미터를 명시적으로 전달해야 하며, 단위별 유효 범위가 다르다는 점에 주의해야 합니다: 섭씨 17-33°C, 화씨 64-91°F.

### 7.6 안전 제한
일부 조작(예: 공조 제어, 윈도우 제어)은 주행 중에는 시스템에 의해 제한될 수 있습니다. 제어 관련 API를 호출할 때는 제어 소스(setSource) 파라미터를 전달하는 것을 권장합니다. 예를 들어 `AC_CTRL_SOURCE_UI_KEY (0)`은 UI 버튼 조작을, `AC_CTRL_SOURCE_VOICE (1)`은 음성 명령을 의미하며, 이는 시스템의 기록 및 권한 검증에 활용됩니다.

### 7.7 버전 호환성
본 매뉴얼은 2020-03-13 버전의 `bydauto-openapi.jar`를 기준으로 작성되었습니다. 이후 차종이나 시스템 업그레이드로 디바이스 유형, 메서드, 상수가 추가될 수 있습니다. 개발 시에는 하위 호환성을 고려한 설계를 하고, 존재하지 않는 기능에 대해서는 대체(fallback) 처리를 제공해야 합니다.

---

*본 문서는 BYDAuto OpenAPI JAR 패키지의 디컴파일 분석을 기반으로 자동 생성되었으며, 개발 참고용으로만 제공됩니다. 비야디(BYD)는 공식적으로 모든 권리를 보유합니다. 실제 API 동작은 차량 시스템 구현을 기준으로 합니다.*
