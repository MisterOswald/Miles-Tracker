import SwiftUI

struct SyncSettingsView: View {
    @EnvironmentObject private var sync: SyncEngine

    @State private var serverURL = AppSettings.serverURL
    @State private var email = AppSettings.accountEmail
    @State private var password = ""
    @State private var working = false
    @State private var message: String?
    @State private var signedIn = APIClient.shared.isConfigured

    var body: some View {
        Form {
            Section {
                TextField("https://your-app.vercel.app", text: $serverURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Server")
            } footer: {
                Text("The URL of your Miles web deployment on Vercel.")
            }

            if signedIn {
                Section("Account") {
                    LabeledContent("Signed in as", value: AppSettings.accountEmail)
                    Button("Sign out", role: .destructive) {
                        APIClient.shared.logout()
                        signedIn = false
                        message = nil
                    }
                }
            } else {
                Section("Sign in") {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                    Button {
                        Task { await signIn() }
                    } label: {
                        if working {
                            ProgressView()
                        } else {
                            Text("Sign in")
                        }
                    }
                    .disabled(working || serverURL.isEmpty || email.isEmpty || password.isEmpty)
                }
            }

            if let message {
                Section {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(signedIn ? .green : .red)
                }
            }
        }
        .navigationTitle("Server & Account")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            AppSettings.serverURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func signIn() async {
        working = true
        message = nil
        AppSettings.serverURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await APIClient.shared.login(email: email, password: password)
            signedIn = true
            password = ""
            message = "Signed in. Drives will sync automatically."
            sync.requestSync()
        } catch {
            signedIn = false
            message = (error as? APIError)?.errorDescription
                ?? "Sign-in failed: \(error.localizedDescription)"
        }
        working = false
    }
}
