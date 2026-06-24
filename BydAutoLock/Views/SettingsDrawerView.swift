import SwiftUI

struct SettingsDrawerView: View {
    @Binding var isOpen: Bool

    var body: some View {
        NavigationStack {
            List {
                Section("설정") {
                    drawerLink("BYD 계정 설정",    icon: "person.badge.key.fill", color: .blue)    { AuthSettingsView() }
                    drawerLink("블루투스 기기 설정", icon: "bluetooth",             color: .cyan)    { BluetoothSettingsView() }
                    drawerLink("RSSI 임계값 설정",  icon: "slider.horizontal.3",   color: .orange)  { ThresholdSettingsView() }
                    drawerLink("에어컨 설정",       icon: "snowflake",             color: .teal)    { AcSettingsView() }
                }

                Section("기타") {
                    drawerLink("알림 설정",   icon: "bell.badge.fill",          color: .red)    { NotificationSettingsView() }
                    drawerLink("디버그 로그", icon: "doc.text.magnifyingglass", color: .purple) { LogView() }
                    urlLink("피드백",        icon: "message.fill",             color: .yellow, url: "https://open.kakao.com/o/gGtmWXAi")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("메뉴")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { withAnimation(.spring(duration: 0.3)) { isOpen = false } } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.bold())
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func urlLink(_ title: String, icon: String, color: Color, url: String) -> some View {
        Button {
            if let u = URL(string: url) { UIApplication.shared.open(u) }
        } label: {
            Label {
                Text(title)
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(color)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
        }
    }

    private func drawerLink<Dest: View>(_ title: String, icon: String, color: Color, @ViewBuilder dest: () -> Dest) -> some View {
        NavigationLink(destination: dest().onAppear { }) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(color)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
        }
    }
}
