import Foundation

/// Setto SDK 에러 코드
public enum SettoErrorCode: String {
    // 사용자 액션
    case userCancelled = "USER_CANCELLED"

    // 결제 실패
    case paymentFailed = "PAYMENT_FAILED"
    case insufficientBalance = "INSUFFICIENT_BALANCE"
    case transactionRejected = "TRANSACTION_REJECTED"

    // 네트워크/시스템
    case networkError = "NETWORK_ERROR"
    case sessionExpired = "SESSION_EXPIRED"

    // 파라미터
    case invalidParams = "INVALID_PARAMS"
    case invalidMerchant = "INVALID_MERCHANT"

    // SDK 내부
    case presentationFailed = "PRESENTATION_FAILED"
}

/// Setto SDK 에러
public enum SettoError: Error, LocalizedError {
    /// 사용자가 결제를 취소함
    case userCancelled

    /// 결제 실패
    case paymentFailed(String?)

    /// 네트워크 오류
    case networkError

    /// 세션 만료
    case sessionExpired

    /// 잘못된 파라미터
    case invalidParams

    /// 화면 표시 실패
    case presentationFailed

    /// 에러 코드
    public var code: SettoErrorCode {
        switch self {
        case .userCancelled:
            return .userCancelled
        case .paymentFailed:
            return .paymentFailed
        case .networkError:
            return .networkError
        case .sessionExpired:
            return .sessionExpired
        case .invalidParams:
            return .invalidParams
        case .presentationFailed:
            return .presentationFailed
        }
    }

    public var errorDescription: String? {
        switch self {
        case .userCancelled:
            return "사용자가 결제를 취소했습니다."
        case .paymentFailed(let message):
            return message ?? "결제에 실패했습니다."
        case .networkError:
            return "네트워크 오류가 발생했습니다."
        case .sessionExpired:
            return "세션이 만료되었습니다."
        case .invalidParams:
            return "잘못된 파라미터입니다."
        case .presentationFailed:
            return "결제 화면을 표시할 수 없습니다."
        }
    }

    /// Deep Link error 파라미터로부터 에러 생성
    static func from(errorCode: String?) -> SettoError {
        guard let code = errorCode else {
            return .paymentFailed(nil)
        }

        switch code {
        case SettoErrorCode.userCancelled.rawValue:
            return .userCancelled
        case SettoErrorCode.insufficientBalance.rawValue:
            return .paymentFailed("잔액이 부족합니다.")
        case SettoErrorCode.transactionRejected.rawValue:
            return .paymentFailed("트랜잭션이 거부되었습니다.")
        case SettoErrorCode.networkError.rawValue:
            return .networkError
        case SettoErrorCode.sessionExpired.rawValue:
            return .sessionExpired
        case SettoErrorCode.invalidParams.rawValue:
            return .invalidParams
        default:
            return .paymentFailed(code)
        }
    }
}
