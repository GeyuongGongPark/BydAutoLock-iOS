import SwiftUI

struct HelpView: View {

    var body: some View {
        List {
            // MARK: - 기본 설정
            Section {
                HelpItem(
                    icon: "person.badge.key.fill", color: .blue,
                    title: "BYD 계정 설정",
                    content: """
BYD 공식 앱에 로그인할 때 쓰는 이메일과 비밀번호를 입력합니다.

PIN (작동 비밀번호) — BYD 앱에서 원격 제어 시 요구하는 6자리 숫자입니다. PIN이 없으면 자동 잠금/해제가 동작하지 않습니다. BYD 앱 → 차량 제어 → 비밀번호 설정에서 먼저 설정하세요.

지역 서버 — 차량을 구입한 국가를 선택합니다. 한국 구입 차량은 반드시 KR을 선택해야 합니다.
"""
                )
                HelpItem(
                    icon: "bluetooth", color: .cyan,
                    title: "블루투스 기기 설정",
                    content: """
차량에서 발신하는 BLE 신호를 감지해 내 차량을 선택합니다.

차량 시동이 꺼져 있어도 BLE 신호는 발신됩니다. 차량 근처 10m 이내에서 스캔하세요.

목록에서 신호 세기(dBm) 숫자가 0에 가까울수록 가까운 기기입니다. (예: -55 dBm이 -80 dBm보다 가까움)
"""
                )
                HelpItem(
                    icon: "car.fill", color: .indigo,
                    title: "차량 정보",
                    content: """
차종을 선택하면 해당 차량의 BLE 특성에 맞게 감도 파라미터가 자동으로 조정됩니다.

지원 차종: ATTO 3, SEAL, DOLPHIN, SEALION 7
"""
                )
            } header: {
                Text("기본 설정")
            }

            // MARK: - 자동 잠금 설정
            Section {
                HelpItem(
                    icon: "slider.horizontal.3", color: .orange,
                    title: "RSSI 임계값이란?",
                    content: """
RSSI(Received Signal Strength Indicator)는 블루투스 신호 세기를 나타내는 단위입니다. dBm으로 표시되며, 0에 가까울수록 신호가 강하고 (가까운 거리), 음수 절댓값이 클수록 신호가 약합니다 (먼 거리).

잠금 해제 임계값 — 이 값 이상의 신호 세기가 감지되면 문이 열립니다. (기본: -70 dBm)
• 더 가까이서 열리게: 값을 낮추세요 (예: -70 → -65)
• 더 멀리서 열리게: 값을 높이세요 (예: -70 → -75)

잠금 임계값 — 이 값 이하로 신호가 떨어지면 문이 잠깁니다. (기본: -85 dBm)
• 더 가까이서 잠기게: 값을 높이세요 (예: -85 → -80)
• 더 멀리서 잠기게: 값을 낮추세요 (예: -85 → -90)

잠금 해제 임계값이 잠금 임계값보다 반드시 높아야(0에 가까워야) 합니다.
"""
                )
                HelpItem(
                    icon: "waveform.path.ecg", color: .purple,
                    title: "EMA 평활화 계수 (α) 란?",
                    content: """
BLE 신호는 순간적으로 튀거나 흔들릴 수 있습니다. EMA(지수 이동 평균)는 이런 노이즈를 줄여 안정적인 값을 만들어냅니다.

α 값이 낮을수록 (0.05 쪽) — 신호 변화에 느리게 반응합니다. 노이즈에 강하지만 실제로 가까워져도 반응이 느릴 수 있습니다.

α 값이 높을수록 (0.8 쪽) — 신호 변화에 빠르게 반응합니다. 실시간성이 좋지만 일시적인 신호 튐에 민감합니다.

기본값 0.25가 대부분의 환경에서 적합합니다.
"""
                )
                HelpItem(
                    icon: "location.fill", color: .blue,
                    title: "지오펜싱이란?",
                    content: """
지오펜싱은 차량 주차 위치를 기준으로 가상의 경계선(반경)을 만드는 기능입니다.

이 경계 밖에 있을 때는 BLE 스캔을 자동으로 중단해 배터리를 절약합니다.
경계 안에 들어오면 BLE 스캔이 자동으로 재개됩니다.

반경 — 50m ~ 500m 사이에서 조정할 수 있습니다. (기본: 150m)
반경이 너무 좁으면 차량 근처에서도 스캔이 시작되지 않을 수 있습니다.
"""
                )
            } header: {
                Text("자동 잠금 설정")
            }

            // MARK: - 에어컨
            Section {
                HelpItem(
                    icon: "snowflake", color: .teal,
                    title: "에어컨 자동 제어",
                    content: """
잠금 해제 시 자동 켜기 — 차에 가까이 갈 때 에어컨이 미리 켜집니다. 여름/겨울에 탑승 전 실내 온도를 조절할 때 유용합니다.

잠금 시 자동 끄기 — 차에서 멀어지면 에어컨이 자동으로 꺼집니다.

에어컨은 최대 20분간 동작한 뒤 차량이 자동으로 종료합니다.

바람 세기 '자동'으로 설정하면 차량이 스스로 풍량을 결정합니다.
"""
                )
            } header: {
                Text("에어컨 설정")
            }

            // MARK: - 알림
            Section {
                HelpItem(
                    icon: "bell.badge.fill", color: .red,
                    title: "알림 설정",
                    content: """
잠금 / 해제 — 자동 또는 수동으로 잠기거나 열릴 때 알림을 받습니다.

신호 끊김 / 복구 — BLE 신호가 30초 이상 끊겼을 때 알림을 받습니다. BLE 재연결 사이클(약 20초)은 정상 동작이므로 알림이 발송되지 않습니다.

차량 배터리 부족 — 차량 배터리가 설정한 % 이하로 떨어지면 알림을 받습니다. (기본: 20%)

알림을 받으려면 iOS 설정에서 BYDAutoLock의 알림 권한이 허용되어 있어야 합니다.
"""
                )
            } header: {
                Text("알림 설정")
            }

            // MARK: - FAQ
            Section {
                HelpItem(
                    icon: "questionmark.circle.fill", color: .gray,
                    title: "자동으로 잠기거나 열리지 않아요",
                    content: """
1. 메인 화면에서 서비스 상태가 '연결됨'인지 확인하세요
2. 메뉴 → 블루투스 기기 설정에서 차량이 선택되어 있는지 확인하세요
3. 메뉴 → BYD 계정 설정에서 PIN이 입력되어 있는지 확인하세요
4. BYD 앱에서 작동 비밀번호(PIN)가 설정되어 있는지 확인하세요
"""
                )
                HelpItem(
                    icon: "questionmark.circle.fill", color: .gray,
                    title: "앱이 백그라운드에서 동작하지 않아요",
                    content: """
1. iOS 설정 → BYDAutoLock → 위치 → '항상'으로 설정하세요
2. iOS 설정 → BYDAutoLock → 백그라운드 앱 새로 고침이 켜져 있는지 확인하세요
3. iOS 설정 → BYDAutoLock → 블루투스 접근이 허용되어 있는지 확인하세요
"""
                )
                HelpItem(
                    icon: "questionmark.circle.fill", color: .gray,
                    title: "주행 중에 문이 잠겨요",
                    content: """
주행 중 BLE 신호가 약해지면 이탈로 감지될 수 있습니다.
앱이 CoreMotion으로 주행을 감지해 잠금을 차단하지만, 감지에 약간의 지연이 있습니다.

메뉴 → RSSI 임계값 설정에서 잠금 임계값을 낮추면(예: -85 → -90) 완화됩니다.
"""
                )
                HelpItem(
                    icon: "questionmark.circle.fill", color: .gray,
                    title: "배터리가 많이 소모돼요",
                    content: """
• 메뉴 → RSSI 임계값 설정 → BLE 스캔 모드를 '저전력 (Low Power)'으로 변경하세요
• 지오펜싱이 활성화되어 있으면 차량 근처에서만 스캔이 동작해 배터리를 절약합니다
"""
                )
            } header: {
                Text("자주 묻는 질문")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("사용 가이드")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Help Item

private struct HelpItem: View {

    let icon: String
    let color: Color
    let title: String
    let content: String

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(color)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    Text(title)
                        .foregroundStyle(.primary)
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if isExpanded {
                Text(content)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
                    .padding(.leading, 40)
            }
        }
    }
}
