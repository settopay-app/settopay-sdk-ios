import Foundation

/// Setto SDK 환경 설정
public enum SettoEnvironment: String {
    /// 개발 환경
    case development
    /// 프로덕션 환경
    case production

    /// 환경에 해당하는 Base URL
    var baseURL: String {
        switch self {
        case .development:
            return "https://dev-wallet.settopay.com"
        case .production:
            return "https://wallet.settopay.com"
        }
    }
}
