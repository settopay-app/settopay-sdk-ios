import Foundation
import SafariServices
import UIKit

/// Setto iOS SDK
///
/// SFSafariViewController를 사용하여 wallet.settopay.com과 연동합니다.
///
/// ## 사용 예시
/// ```swift
/// // 초기화
/// SettoSDK.shared.initialize(
///     merchantId: "merchant-123",
///     environment: .production,
///     returnScheme: "mygame"
/// )
///
/// // 결제 요청
/// SettoSDK.shared.openPayment(
///     params: PaymentParams(orderId: "order-456", amount: 100.00)
/// ) { result in
///     switch result {
///     case .success(let paymentResult):
///         print("결제 성공: \(paymentResult.txId ?? "")")
///     case .failure(let error):
///         print("결제 실패: \(error)")
///     }
/// }
/// ```
public final class SettoSDK: NSObject {
    /// 싱글톤 인스턴스
    public static let shared = SettoSDK()

    // MARK: - Private Properties

    private var merchantId: String = ""
    private var returnScheme: String = ""
    private var environment: SettoEnvironment = .production

    private var safariVC: SFSafariViewController?
    private var completionHandler: ((Result<PaymentResult, SettoError>) -> Void)?

    private override init() {
        super.init()
    }

    // MARK: - Public Methods

    /// SDK 초기화
    /// - Parameters:
    ///   - merchantId: 고객사 ID
    ///   - environment: 환경 설정 (.development 또는 .production)
    ///   - returnScheme: 결제 완료 후 돌아올 Custom URL Scheme (예: "mygame")
    public func initialize(
        merchantId: String,
        environment: SettoEnvironment,
        returnScheme: String
    ) {
        self.merchantId = merchantId
        self.environment = environment
        self.returnScheme = returnScheme
    }

    /// 결제 창을 열고 결제를 진행합니다.
    /// - Parameters:
    ///   - params: 결제 파라미터
    ///   - completion: 결제 완료 콜백
    public func openPayment(
        params: PaymentParams,
        completion: @escaping (Result<PaymentResult, SettoError>) -> Void
    ) {
        self.completionHandler = completion

        // URL 생성
        guard let url = buildPaymentURL(params: params) else {
            completion(.failure(.invalidParams))
            return
        }

        // SFSafariViewController 생성
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false

        safariVC = SFSafariViewController(url: url, configuration: config)
        safariVC?.delegate = self

        // 화면 표시
        guard let topVC = Self.topViewController else {
            completion(.failure(.presentationFailed))
            return
        }

        topVC.present(safariVC!, animated: true)
    }

    /// Deep Link 처리
    /// - Parameter url: Deep Link URL
    /// - Returns: 처리 여부
    @discardableResult
    public func handleDeepLink(url: URL) -> Bool {
        // Scheme 확인
        guard url.scheme == returnScheme else {
            return false
        }

        // Safari 닫기
        safariVC?.dismiss(animated: true)

        // URL 파싱
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        let status = queryItems.first { $0.name == "status" }?.value
        let txId = queryItems.first { $0.name == "txId" }?.value
        let paymentId = queryItems.first { $0.name == "paymentId" }?.value
        let error = queryItems.first { $0.name == "error" }?.value

        // 결과 처리
        switch status {
        case "success":
            let result = PaymentResult(status: .success, txId: txId, paymentId: paymentId)
            completionHandler?(.success(result))

        case "cancelled":
            completionHandler?(.failure(.userCancelled))

        default:
            completionHandler?(.failure(SettoError.from(errorCode: error)))
        }

        completionHandler = nil
        return true
    }

    // MARK: - Private Methods

    private func buildPaymentURL(params: PaymentParams) -> URL? {
        guard let encodedMerchantId = merchantId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedOrderId = params.orderId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedScheme = returnScheme.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else {
            return nil
        }

        var urlString = "\(environment.baseURL)/pay"
        urlString += "?merchantId=\(encodedMerchantId)"
        urlString += "&orderId=\(encodedOrderId)"
        urlString += "&amount=\(params.amount)"
        urlString += "&returnScheme=\(encodedScheme)"

        if let currency = params.currency,
           let encodedCurrency = currency.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            urlString += "&currency=\(encodedCurrency)"
        }

        return URL(string: urlString)
    }

    /// 최상위 ViewController 가져오기
    private static var topViewController: UIViewController? {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }

        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

// MARK: - SFSafariViewControllerDelegate

extension SettoSDK: SFSafariViewControllerDelegate {
    public func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        // 사용자가 Safari를 닫음 (취소)
        completionHandler?(.failure(.userCancelled))
        completionHandler = nil
    }
}
