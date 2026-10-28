import SwiftUI

/// 规范 1：登录 / 服务器连接页。
struct LoginView: View {
    @EnvironmentObject private var session: SessionStore
    @FocusState private var focused: Field?

    private enum Field {
        case server, username, password
    }

    var body: some View {
        ZStack {
            Theme.bgHome.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 26) {
                    header
                    formCard
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, Theme.padPage)
                .padding(.top, 70)
            }
        }
        .onTapGesture {
            focused = nil
        }
    }

    // MARK: - 标题

    private var header: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.accent.opacity(0.14))
                    .frame(width: 72, height: 72)

                Image(systemName: "play.tv.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.bottom, 8)

            // 规范 1（v1.3）：标题取应用名，不硬编码；26sp 粗体，字距 0.08em
            Text(AppInfo.displayName)
                .font(Theme.font(26, .bold))
                .foregroundStyle(Theme.textPrimary)
                .tracking(26 * 0.08)

            Text("连接你的媒体服务器")
                .font(Theme.font(13))
                .foregroundStyle(Theme.textWeak)
        }
    }

    // MARK: - 表单

    private var formCard: some View {
        VStack(spacing: 12) {
            inputField(
                icon: "server.rack",
                placeholder: "192.168.1.10:7025",
                text: $session.serverAddress,
                field: .server,
                keyboard: .URL
            )

            inputField(
                icon: "person",
                placeholder: "admin",
                text: $session.username,
                field: .username,
                keyboard: .default
            )

            secureField

            rememberRow

            Button {
                focused = nil
                Task { await session.connect() }
            } label: {
                HStack(spacing: 8) {
                    if session.isConnecting {
                        ProgressView()
                            .tint(Color(hex: 0x08150E))
                            .scaleEffect(0.85)
                    }
                    Text(session.isConnecting ? "连接中…" : "连接")
                }
            }
            .buttonStyle(PrimaryButtonStyle(enabled: canConnect))
            .disabled(!canConnect || session.isConnecting)
            .padding(.top, 6)

            // 规范 1：失败时在按钮下方显示错误原因
            if let error = session.errorMessage {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 11))
                    Text(error)
                        .font(Theme.font(12))
                        .multilineTextAlignment(.leading)
                }
                .foregroundStyle(Color(hex: 0xFF6B6B))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSheet, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
    }

    private var canConnect: Bool {
        !session.serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !session.password.isEmpty
    }

    private func inputField(
        icon: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        keyboard: UIKeyboardType
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textFaint)
                .frame(width: 18)

            TextField(placeholder, text: text)
                .font(Theme.font(14))
                .foregroundStyle(Theme.textPrimary)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused, equals: field)
                .submitLabel(.next)
                .onSubmit {
                    switch field {
                    case .server: focused = .username
                    case .username: focused = .password
                    case .password: focused = nil
                    }
                }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusInput, style: .continuous)
                .fill(Theme.cardDeep)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusInput, style: .continuous)
                .stroke(
                    focused == field ? Theme.accent.opacity(0.7) : Theme.inputBorder,
                    lineWidth: 1
                )
        )
    }

    private var secureField: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textFaint)
                .frame(width: 18)

            SecureField("密码", text: $session.password)
                .font(Theme.font(14))
                .foregroundStyle(Theme.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused, equals: .password)
                .submitLabel(.go)
                .onSubmit {
                    guard canConnect else { return }
                    focused = nil
                    Task { await session.connect() }
                }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusInput, style: .continuous)
                .fill(Theme.cardDeep)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusInput, style: .continuous)
                .stroke(
                    focused == .password ? Theme.accent.opacity(0.7) : Theme.inputBorder,
                    lineWidth: 1
                )
        )
    }

    private var rememberRow: some View {
        Button {
            session.rememberPassword.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: session.rememberPassword ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15))
                    .foregroundStyle(session.rememberPassword ? Theme.accent : Theme.textFaint)

                Text("记住密码")
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.textSecondary)

                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }
}
