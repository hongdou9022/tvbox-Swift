import Foundation
import Combine

/// 登录状态与服务器会话（规范第 1 章）。
@MainActor
final class SessionStore: ObservableObject {
    static let shared = SessionStore()

    @Published private(set) var isLoggedIn = false
    @Published private(set) var user: AppUser?
    @Published private(set) var isConnecting = false
    @Published var errorMessage: String?

    // 表单字段（登录页双向绑定）
    @Published var serverAddress: String = ""
    @Published var username: String = ""
    @Published var password: String = ""
    @Published var rememberPassword: Bool = true

    private let defaults = UserDefaults.standard
    private let api = APIClient.shared

    private enum Keys {
        static let server = "cloudvideo.session.server"
        static let username = "cloudvideo.session.username"
        static let remember = "cloudvideo.session.remember"
        static let token = "cloudvideo.session.token"
        static let password = "cloudvideo.session.password"
    }

    private init() {}

    // MARK: - 启动恢复

    /// 规范 1：连接成功后 token 持久化，此后启动直接进首页。
    func bootstrap() {
        let server = defaults.string(forKey: Keys.server) ?? ""
        let account = defaults.string(forKey: Keys.username) ?? ""
        let remember = defaults.object(forKey: Keys.remember) as? Bool ?? true

        serverAddress = server
        username = account
        rememberPassword = remember

        if remember, let saved = Keychain.get(Keys.password) {
            password = saved
        }

        guard !server.isEmpty,
              let url = APIClient.normalizeServer(server),
              let token = Keychain.get(Keys.token),
              !token.isEmpty else {
            return
        }

        api.configure(server: url, token: token)
        isLoggedIn = true
    }

    // MARK: - 连接

    func connect() async {
        let address = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = username.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !address.isEmpty else {
            errorMessage = "请填写服务器地址"
            return
        }
        guard !password.isEmpty else {
            errorMessage = "请填写密码"
            return
        }

        isConnecting = true
        errorMessage = nil

        do {
            let response = try await api.login(
                server: address,
                username: account.isEmpty ? "admin" : account,
                password: password
            )

            user = response.user
            persist(address: address, account: account, token: response.token)
            isLoggedIn = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isConnecting = false
    }

    private func persist(address: String, account: String, token: String) {
        defaults.set(address, forKey: Keys.server)
        defaults.set(account, forKey: Keys.username)
        defaults.set(rememberPassword, forKey: Keys.remember)

        Keychain.set(token, for: Keys.token)

        if rememberPassword {
            Keychain.set(password, for: Keys.password)
        } else {
            Keychain.remove(Keys.password)
        }
    }

    // MARK: - 退出

    func logout() {
        Keychain.remove(Keys.token)
        api.updateToken(nil)
        user = nil
        isLoggedIn = false
        password = ""
        errorMessage = nil
    }

    /// 收到 401 时由各页面调用，统一退回登录页。
    func handleUnauthorized() {
        guard isLoggedIn else { return }
        errorMessage = "登录已过期，请重新连接"
        logout()
    }
}
