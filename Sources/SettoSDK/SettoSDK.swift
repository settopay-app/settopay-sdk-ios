import Foundation
import SafariServices
import UIKit

// MARK: - Types

public enum SettoEnvironment: String {
    case dev = "dev"
    case prod = "prod"

    var baseURL: String {
        switch self {
        case .dev: return "https://dev-wallet.settopay.com"
        case .prod: return "https://wallet.settopay.com"
        }
    }
}

public struct SettoConfig {
    public let environment: SettoEnvironment
    public let idpToken: String?  // IdP 토큰 (있으면 자동로그인)
    public let debug: Bool

    public init(
        environment: SettoEnvironment,
        idpToken: String? = nil,
        debug: Bool = false
    ) {
        self.environment = environment
        self.idpToken = idpToken
        self.debug = debug
    }
}

public enum PaymentStatus: String {
    case success
    case failed
    case cancelled
}

public struct PaymentResult {
    public let status: PaymentStatus
    public let paymentId: String?
    public let txHash: String?
    public let error: String?
}

public struct PaymentInfo: Decodable {
    public let paymentId: String
    public let status: String
    public let amount: String
    public let currency: String
    public let txHash: String?
    public let createdAt: Int64
    public let completedAt: Int64?

    enum CodingKeys: String, CodingKey {
        case paymentId = "payment_id"
        case status
        case amount
        case currency
        case txHash = "tx_hash"
        case createdAt = "created_at"
        case completedAt = "completed_at"
    }
}

// MARK: - SDK

public final class SettoSDK {

    public static let shared = SettoSDK()

    private var config: SettoConfig?
    private var safariVC: SFSafariViewController?
    private var completion: ((PaymentResult) -> Void)?

    private init() {}

    // MARK: - Public Methods

    /// SDK 초기화
    ///
    /// - Parameters:
    ///   - config.environment: 환경 (dev | prod)
    ///   - config.idpToken: IdP 토큰 (선택, 있으면 자동로그인)
    ///   - config.debug: 디버그 로그 (선택)
    public func initialize(config: SettoConfig) {
        self.config = config
        debugLog("Initialized with environment: \(config.environment)")
    }

    /// 결제 요청
    ///
    /// IdP Token 유무에 따라 자동로그인 여부가 결정됩니다.
    /// - IdP Token 없음: Setto 로그인 필요
    /// - IdP Token 있음: PaymentToken 발급 후 자동로그인
    public func openPayment(
        merchantId: String,
        amount: String,
        orderId: String? = nil,
        from viewController: UIViewController,
        completion: @escaping (PaymentResult) -> Void
    ) {
        guard let config = config else {
            completion(PaymentResult(status: .failed, paymentId: nil, txHash: nil, error: "SDK not initialized"))
            return
        }

        if let idpToken = config.idpToken {
            // IdP Token 있음 → PaymentToken 발급 → Fragment로 전달
            debugLog("Requesting PaymentToken...")
            requestPaymentToken(
                merchantId: merchantId,
                amount: amount,
                orderId: orderId,
                idpToken: idpToken,
                config: config
            ) { [weak self] result in
                switch result {
                case .success(let paymentToken):
                    let encodedToken = paymentToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? paymentToken
                    let urlString = "\(config.environment.baseURL)/pay/wallet#pt=\(encodedToken)"
                    guard let url = URL(string: urlString) else {
                        completion(PaymentResult(status: .failed, paymentId: nil, txHash: nil, error: "Invalid URL"))
                        return
                    }
                    self?.debugLog("Opening payment with auto-login")
                    self?.openSafariViewController(url: url, from: viewController, completion: completion)

                case .failure(let error):
                    completion(PaymentResult(status: .failed, paymentId: nil, txHash: nil, error: error.localizedDescription))
                }
            }
        } else {
            // IdP Token 없음 → Query param으로 직접 전달
            var urlComponents = URLComponents(string: "\(config.environment.baseURL)/pay/wallet")!
            urlComponents.queryItems = [
                URLQueryItem(name: "merchant_id", value: merchantId),
                URLQueryItem(name: "amount", value: amount)
            ]
            if let orderId = orderId {
                urlComponents.queryItems?.append(URLQueryItem(name: "order_id", value: orderId))
            }

            guard let url = urlComponents.url else {
                completion(PaymentResult(status: .failed, paymentId: nil, txHash: nil, error: "Invalid URL"))
                return
            }

            debugLog("Opening payment with Setto login")
            openSafariViewController(url: url, from: viewController, completion: completion)
        }
    }

    /// 결제 상태 조회
    public func getPaymentInfo(
        merchantId: String,
        paymentId: String,
        completion: @escaping (Result<PaymentInfo, Error>) -> Void
    ) {
        guard let config = config else {
            completion(.failure(NSError(domain: "SettoSDK", code: -1, userInfo: [NSLocalizedDescriptionKey: "SDK not initialized"])))
            return
        }

        let urlString = "\(config.environment.baseURL)/api/external/payment/\(paymentId)"
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "SettoSDK", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }

        var request = URLRequest(url: url)
        request.setValue(merchantId, forHTTPHeaderField: "X-Merchant-ID")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(NSError(domain: "SettoSDK", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }

            do {
                let info = try JSONDecoder().decode(PaymentInfo.self, from: data)
                completion(.success(info))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    /// URL Scheme 콜백 처리
    /// AppDelegate 또는 SceneDelegate에서 호출
    public func handleCallback(url: URL) -> Bool {
        // setto-{merchantId}://callback?status=success&payment_id=xxx&tx_hash=xxx
        guard url.scheme?.hasPrefix("setto-") == true,
              url.host == "callback" else {
            return false
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        let statusString = queryItems.first(where: { $0.name == "status" })?.value ?? ""
        let paymentId = queryItems.first(where: { $0.name == "payment_id" })?.value
        let txHash = queryItems.first(where: { $0.name == "tx_hash" })?.value
        let errorMsg = queryItems.first(where: { $0.name == "error" })?.value

        let status: PaymentStatus
        switch statusString {
        case "success": status = .success
        case "failed": status = .failed
        default: status = .cancelled
        }

        let result = PaymentResult(
            status: status,
            paymentId: paymentId,
            txHash: txHash,
            error: errorMsg
        )

        dismissSafariViewController()
        completion?(result)
        completion = nil

        debugLog("Callback received: \(statusString)")
        return true
    }

    /// 초기화 여부 확인
    public var isInitialized: Bool {
        return config != nil
    }

    // MARK: - Private Methods

    private func requestPaymentToken(
        merchantId: String,
        amount: String,
        orderId: String?,
        idpToken: String,
        config: SettoConfig,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let urlString = "\(config.environment.baseURL)/api/external/payment/token"
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "SettoSDK", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "merchant_id": merchantId,
            "amount": amount,
            "idp_token": idpToken
        ]
        if let orderId = orderId {
            body["order_id"] = orderId
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(NSError(domain: "SettoSDK", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                    return
                }

                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let paymentToken = json["payment_token"] as? String {
                        completion(.success(paymentToken))
                    } else {
                        completion(.failure(NSError(domain: "SettoSDK", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                    }
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    private func openSafariViewController(
        url: URL,
        from viewController: UIViewController,
        completion: @escaping (PaymentResult) -> Void
    ) {
        self.completion = completion

        let safariVC = SFSafariViewController(url: url)
        safariVC.delegate = self
        safariVC.modalPresentationStyle = .pageSheet

        self.safariVC = safariVC
        viewController.present(safariVC, animated: true)
    }

    private func dismissSafariViewController() {
        safariVC?.dismiss(animated: true)
        safariVC = nil
    }

    private func debugLog(_ message: String) {
        guard config?.debug == true else { return }
        print("[SettoSDK] \(message)")
    }
}

// MARK: - SFSafariViewControllerDelegate

extension SettoSDK: SFSafariViewControllerDelegate {
    public func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        // 사용자가 Safari를 닫음 (취소)
        let result = PaymentResult(status: .cancelled, paymentId: nil, txHash: nil, error: nil)
        completion?(result)
        completion = nil
        safariVC = nil
        debugLog("Safari closed by user")
    }
}
