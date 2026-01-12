# SettoSDK for iOS

Setto iOS SDK - SFSafariViewController 기반 결제 연동 SDK

## 요구사항

- iOS 13.0+
- Swift 5.7+

## 설치

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/settopay-app/setto-ios-sdk.git", from: "0.1.0")
]
```

### Xcode

1. File → Add Packages...
2. URL 입력: `https://github.com/settopay-app/setto-ios-sdk.git`

## 설정

### Info.plist - Custom URL Scheme 등록

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>mygame</string>  <!-- 고객사 Scheme -->
        </array>
        <key>CFBundleURLName</key>
        <string>com.customer.mygame</string>
    </dict>
</array>
```

### SceneDelegate - Deep Link 수신

```swift
// SceneDelegate.swift
import SettoSDK

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        // 앱 시작 시 Deep Link 처리
        if let urlContext = connectionOptions.urlContexts.first {
            SettoSDK.shared.handleDeepLink(url: urlContext.url)
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        // 앱 실행 중 Deep Link 처리
        guard let url = URLContexts.first?.url else { return }
        SettoSDK.shared.handleDeepLink(url: url)
    }
}
```

## 사용법

### SDK 초기화

```swift
import SettoSDK

// AppDelegate 또는 앱 시작 시점에서 초기화
SettoSDK.shared.initialize(
    merchantId: "your-merchant-id",
    environment: .production,  // .development 또는 .production
    returnScheme: "mygame"     // Info.plist에 등록한 Scheme
)
```

### 결제 요청

```swift
import SettoSDK

func handlePayment() {
    let params = PaymentParams(
        orderId: "order-123",
        amount: Decimal(100.00),
        currency: "USD"  // 선택
    )

    SettoSDK.shared.openPayment(params: params) { result in
        switch result {
        case .success(let paymentResult):
            print("결제 성공!")
            print("TX ID: \(paymentResult.txId ?? "N/A")")
            // 서버에서 결제 검증 필수!

        case .failure(let error):
            switch error {
            case .userCancelled:
                print("사용자가 결제를 취소했습니다.")
            case .paymentFailed(let message):
                print("결제 실패: \(message ?? "알 수 없는 오류")")
            default:
                print("오류: \(error.localizedDescription)")
            }
        }
    }
}
```

## API

### SettoSDK

#### `initialize(merchantId:environment:returnScheme:)`

SDK를 초기화합니다. 앱 시작 시 한 번만 호출합니다.

| 파라미터 | 타입 | 설명 |
|---------|------|------|
| `merchantId` | `String` | 고객사 ID |
| `environment` | `SettoEnvironment` | `.development` 또는 `.production` |
| `returnScheme` | `String` | Custom URL Scheme |

#### `openPayment(params:completion:)`

결제 창을 열고 결제를 진행합니다.

| 파라미터 | 타입 | 설명 |
|---------|------|------|
| `params` | `PaymentParams` | 결제 파라미터 |
| `completion` | `(Result<PaymentResult, SettoError>) -> Void` | 결제 완료 콜백 |

#### `handleDeepLink(url:) -> Bool`

Deep Link를 처리합니다. SceneDelegate에서 호출합니다.

### PaymentParams

| 속성 | 타입 | 필수 | 설명 |
|------|------|------|------|
| `orderId` | `String` | ✅ | 주문 ID |
| `amount` | `Decimal` | ✅ | 결제 금액 |
| `currency` | `String?` | | 통화 (기본: USD) |

### PaymentResult

| 속성 | 타입 | 설명 |
|------|------|------|
| `status` | `PaymentStatus` | `.success`, `.failed`, `.cancelled` |
| `txId` | `String?` | 블록체인 트랜잭션 해시 |
| `paymentId` | `String?` | Setto 결제 ID |
| `error` | `String?` | 에러 메시지 |

### SettoError

| 케이스 | 설명 |
|--------|------|
| `.userCancelled` | 사용자 취소 |
| `.paymentFailed(String?)` | 결제 실패 |
| `.networkError` | 네트워크 오류 |
| `.sessionExpired` | 세션 만료 |
| `.invalidParams` | 잘못된 파라미터 |
| `.presentationFailed` | 화면 표시 실패 |

## 인증 방식

iOS SDK는 SFSafariViewController(시스템 브라우저)를 사용합니다:

- **이미 Setto에 로그인된 경우**: Safari 세션이 공유되어 바로 결제 화면이 표시됩니다.
- **로그인되지 않은 경우**: Setto 자체 OAuth 로그인 화면이 표시된 후 결제가 진행됩니다.

> **참고**: Web/WebGL SDK와 달리 idpToken 파라미터가 필요 없습니다. 시스템 브라우저가 세션을 관리합니다.

## 보안 참고사항

1. **결제 결과는 서버에서 검증 필수**: SDK에서 반환하는 결과는 UX 피드백용입니다. 실제 결제 완료 여부는 고객사 서버에서 Setto API를 통해 검증해야 합니다.

2. **Custom URL Scheme 보안**: 다른 앱이 동일한 Scheme을 등록할 수 있으므로, 결제 결과는 반드시 서버에서 검증하세요.

## License

MIT
