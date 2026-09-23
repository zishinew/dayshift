import SwiftUI

@MainActor
struct AccountPage: View {
    @Binding var isCreatingAccount: Bool
    @Environment(AppearanceSettings.self) private var appearance
    @Environment(CloudAccount.self) private var account
    @Environment(CloudSync.self) private var sync
    @Environment(TaskStore.self) private var store
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                Text(account.email == nil ? (isCreatingAccount ? "sign up" : "log in") : "account")
                    .font(.custom(appearance.fontName, size: appearance.scaled(24)))
                    .padding(.bottom, 8)

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
                    TextField("email", text: $email)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .textFieldStyle(.plain)
                        .frame(maxWidth: 320)
                        .padding(.bottom, 7)
                        .overlay(alignment: .bottom) {
                            appearance.textColor.opacity(0.2).frame(height: 1)
                        }

                    SecureField("password", text: $password)
                        .textContentType(isCreatingAccount ? .newPassword : .password)
                        .textFieldStyle(.plain)
                        .frame(maxWidth: 320)
                        .padding(.bottom, 7)
                        .overlay(alignment: .bottom) {
                            appearance.textColor.opacity(0.2).frame(height: 1)
                        }
                        .onSubmit(submit)

                    Button(action: submit) {
                        Text(isCreatingAccount ? "create account" : "log in")
                            .foregroundStyle(appearance.backgroundColor)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 7).fill(appearance.textColor))
                    }
                        .disabled(account.isWorking)
                        .padding(.top, 7)

                    HStack(spacing: 5) {
                        Text(isCreatingAccount ? "already have an account?" : "new to dayshift?")
                            .foregroundStyle(.secondary)
                        Button(isCreatingAccount ? "log in" : "sign up") {
                            isCreatingAccount.toggle()
                            account.message = nil
                        }
                    }
                    .font(.custom(appearance.fontName, size: appearance.scaled(13)))

                    Text("your current tasks will be copied into your account. the originals stay on this mac.")
                        .font(.custom(appearance.fontName, size: appearance.scaled(13)))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 420, alignment: .leading)
                        .padding(.top, 4)
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
