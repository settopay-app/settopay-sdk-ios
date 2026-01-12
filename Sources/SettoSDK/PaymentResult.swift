import Foundation

/// 결제 상태
public enum PaymentStatus: String {
    case success
    case failed
    case cancelled
}

/// 결제 결과
public struct PaymentResult {
    /// 결제 상태
    public let status: PaymentStatus

    /// 블록체인 트랜잭션 해시 (성공 시)
    public let txId: String?

    /// Setto 결제 ID
    public let paymentId: String?

    /// 에러 메시지 (실패 시)
    public let error: String?

    public init(
        status: PaymentStatus,
        txId: String? = nil,
        paymentId: String? = nil,
        error: String? = nil
    ) {
        self.status = status
        self.txId = txId
        self.paymentId = paymentId
        self.error = error
    }
}

/// 결제 요청 파라미터
public struct PaymentParams {
    /// 주문 ID
    public let orderId: String

    /// 결제 금액
    public let amount: Decimal

    /// 통화 (기본: USD)
    public let currency: String?

    public init(orderId: String, amount: Decimal, currency: String? = nil) {
        self.orderId = orderId
        self.amount = amount
        self.currency = currency
    }
}
