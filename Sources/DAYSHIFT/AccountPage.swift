import SwiftUI

@MainActor
struct AccountPage: View {
    @Environment(AppearanceSettings.self) private var appearance
    @Environment(CloudAccount.self) private var account
    @Environment(CloudSync.self) private var sync
    @Environment(TaskStore.self) private var store
    @State private var isCreatingAccount = false
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                Text("account")
                    .font(.custom(appearance.fontName, size: appearance.scaled(24)))
                    .padding(.bottom, 10)

                if let email = account.email {
                    Text(email.lowercased())
                        .font(.custom(appearance.fontName, size: appearance.scaled(17)))
                    Text(sync.status)
                        .font(.custom(appearance.fontName, size: appearance.scaled(14)))
                        .foregroundStyle(.secondary)
                    if sync.pendingCount > 0 {
                        Text("your changes are saved on this mac and will upload when connected")
                            .font(.custom(appearance.fontName, size: appearance.scaled(13)))
                            .foregroundStyle(.secondary)
                    }
                    Button("sync now") { sync.syncNow(account: account, store: store) }
                        .padding(.top, 6)
                    Button("sign out") { Task { await account.signOut() } }
                        .padding(.top, 4)
                } else if account.isConfigured {
                    HStack(spacing: 16) {
                        Button("sign in") { isCreatingAccount = false; account.message = nil }
                            .opacity(isCreatingAccount ? 0.48 : 1)
                        Button("create account") { isCreatingAccount = true; account.message = nil }
                            .opacity(isCreatingAccount ? 1 : 0.48)
                    }
                    .padding(.bottom, 8)

                    TextField("email", text: $email)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .textFieldStyle(.plain)
                        .frame(maxWidth: 320)

                    SecureField("password", text: $password)
                        .textContentType(isCreatingAccount ? .newPassword : .password)
                        .textFieldStyle(.plain)
                        .frame(maxWidth: 320)
                        .onSubmit(submit)

                    Button(isCreatingAccount ? "create account" : "sign in", action: submit)
                        .disabled(account.isWorking)
                        .padding(.top, 7)

                    Text("your current tasks stay on this mac until you sign in. signing in copies them into your account without removing the local originals.")
                        .font(.custom(appearance.fontName, size: appearance.scaled(13)))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 420, alignment: .leading)
                        .padding(.top, 8)
                } else {
                    Text("cloud sync is not configured in this build")
                        .font(.custom(appearance.fontName, size: appearance.scaled(15)))
                        .foregroundStyle(.secondary)
                }

                if let message = account.message {
                    Text(message)
                        .font(.custom(appearance.fontName, size: appearance.scaled(13)))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 420, alignment: .leading)
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(.horizontal, 38)
            .padding(.top, 30)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(appearance.backgroundColor)
        .foregroundStyle(appearance.textColor)
        .tint(appearance.textColor)
        .font(.custom(appearance.fontName, size: appearance.scaled(15)))
        .buttonStyle(.plain)
    }

    private func submit() {
        Task {
            if isCreatingAccount {
                await account.signUp(email: email, password: password)
            } else {
                await account.signIn(email: email, password: password)
            }
            if account.userID != nil { password = "" }
        }
    }
}
