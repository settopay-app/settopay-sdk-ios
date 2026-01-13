import Foundation
import SafariServices
import UIKit

// MARK: - Types

public enum SettoEnvironment: String {
    case dev = "dev"
    case prod = "prod"

    /// API 서버 (백엔드 gRPC-Gateway)
    var apiURL: String {
        switch self {
        case .dev: return "https://dev-wallet.settopay.com"
        case .prod: return "https://wallet.settopay.com"
        }
    }

    /// 웹앱 (프론트엔드 결제 페이지)
    var webAppURL: String {
        switch self {
        case .dev: return "https://dev-app.settopay.com"
        case .prod: return "https://app.settopay.com"
        }
    }
}

public struct SettoConfig {
    public let environment: SettoEnvironment
    public let debug: Bool

    public init(
        environment: SettoEnvironment,
        debug: Bool = false
    ) {
        self.environment = environment
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
    /// 결제자 지갑 주소 (서버에서 반환)
    public let fromAddress: String?
    /// 결산 수신자 주소 (pool이 아닌 최종 수신자, 서버에서 반환)
    public let toAddress: String?
    /// 결제 금액 (USD, 예: "10.00", 서버에서 반환)
    public let amount: String?
    /// 체인 ID (예: 8453, 56, 900001, 서버에서 반환)
    public let chainId: Int?
    /// 토큰 심볼 (예: "USDC", "USDT", 서버에서 반환)
    public let tokenSymbol: String?
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
    ///   - config.debug: 디버그 로그 (선택)
    public func initialize(config: SettoConfig) {
        self.config = config
        debugLog("Initialized with environment: \(config.environment)")
    }

    /// 결제 요청
    ///
    /// 항상 PaymentToken을 발급받아서 결제 페이지로 전달합니다.
    /// - IdP Token 없음: Setto 로그인 필요
    /// - IdP Token 있음: 자동로그인
    ///
    /// - Parameters:
    ///   - merchantId: 머천트 ID
    ///   - amount: 결제 금액
    ///   - idpToken: IdP 토큰 (선택, 있으면 자동로그인)
    ///   - viewController: Safari를 표시할 뷰 컨트롤러
    ///   - completion: 결제 결과 콜백
    public func openPayment(
        merchantId: String,
        amount: String,
        idpToken: String? = nil,
        from viewController: UIViewController,
        completion: @escaping (PaymentResult) -> Void
    ) {
        guard let config = config else {
            completion(PaymentResult(status: .failed, paymentId: nil, txHash: nil, fromAddress: nil, toAddress: nil, amount: nil, chainId: nil, tokenSymbol: nil, error: "SDK not initialized"))
            return
        }

        debugLog("Requesting PaymentToken...")
        requestPaymentToken(
            merchantId: merchantId,
            amount: amount,
            idpToken: idpToken,
            config: config
        ) { [weak self] result in
            switch result {
            case .success(let paymentToken):
                let encodedToken = paymentToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? paymentToken
                let urlString = "\(config.environment.webAppURL)/pay/wallet#pt=\(encodedToken)"
                guard let url = URL(string: urlString) else {
                    completion(PaymentResult(status: .failed, paymentId: nil, txHash: nil, fromAddress: nil, toAddress: nil, amount: nil, chainId: nil, tokenSymbol: nil, error: "Invalid URL"))
                    return
                }
                self?.debugLog("Opening payment page")
                self?.openSafariViewController(url: url, from: viewController, completion: completion)

            case .failure(let error):
                completion(PaymentResult(status: .failed, paymentId: nil, txHash: nil, fromAddress: nil, toAddress: nil, amount: nil, chainId: nil, tokenSymbol: nil, error: error.localizedDescription))
            }
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

        let urlString = "\(config.environment.apiURL)/api/external/payment/\(paymentId)"
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
        let fromAddress = queryItems.first(where: { $0.name == "from_address" })?.value
        let toAddress = queryItems.first(where: { $0.name == "to_address" })?.value
        let amount = queryItems.first(where: { $0.name == "amount" })?.value
        let chainIdStr = queryItems.first(where: { $0.name == "chain_id" })?.value
        let chainId = chainIdStr != nil ? Int(chainIdStr!) : nil
        let tokenSymbol = queryItems.first(where: { $0.name == "token_symbol" })?.value
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
            fromAddress: fromAddress,
            toAddress: toAddress,
            amount: amount,
            chainId: chainId,
            tokenSymbol: tokenSymbol,
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
        idpToken: String?,
        config: SettoConfig,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let urlString = "\(config.environment.apiURL)/api/external/payment/token"
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "SettoSDK", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "merchant_id": merchantId,
            "amount": amount
        ]
        if let idpToken = idpToken {
            body["idp_token"] = idpToken
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
        let result = PaymentResult(status: .cancelled, paymentId: nil, txHash: nil, fromAddress: nil, toAddress: nil, amount: nil, chainId: nil, tokenSymbol: nil, error: nil)
        completion?(result)
        completion = nil
        safariVC = nil
        debugLog("Safari closed by user")
    }
}
