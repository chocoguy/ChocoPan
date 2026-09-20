import SwiftUI

struct SetupCredentialsStep: View {
    @Bindable var coordinator: LibrarySetupCoordinator
    let onBack: () -> Void

    var body: some View {
        SetupStepScaffold(
            title: "Connect to your server",
            subtitle: "Enter the address and credentials for the SMB share."
        ) {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 20) {
                    TextField("Address or IP", text: $coordinator.host)
                    TextField("Username", text: $coordinator.username)
                    SecureField("Password", text: $coordinator.password)
                }
                .frame(maxWidth: 700)

//                Text("Ex: 192.168.1.153. ChocoPan connects over SMB on port 445.")
//                    .font(.footnote)
//                    .foregroundStyle(.secondary)

                if let error = coordinator.error {
                    SetupErrorBanner(error: error)
                }
            }
        } actions: {
            Button("Back", action: onBack)

            Button {
                Task { await coordinator.testConnection() }
            } label: {
                if coordinator.isTestingConnection {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Connecting…")
                    }
                } else {
                    Text("Test Connection")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!coordinator.canSubmitCredentials)
        }
    }
}

#Preview {
    SetupCredentialsStep(coordinator: LibrarySetupCoordinator(), onBack: {})
}
