import Foundation
import Combine

// MARK: - Core Billing Models

struct Customer: Codable, Identifiable {
    let id: String
    let tenantId: String
    var email: String
    var name: String
    var phone: String?
    var address: BillingAddress?
    var paymentMethods: [PaymentMethod]
    let createdAt: Date
    var updatedAt: Date
    var lastPaymentAt: Date?
    let metadata: [String: String]
    
    #if DEBUG
    static let mock = Customer(
        id: "cus_sample_123",
        tenantId: "tenant_001",
        email: "john.doe@example.com",
        name: "John Doe",
        phone: "+1-555-0123",
        address: BillingAddress.mock,
        paymentMethods: [PaymentMethod.mock],
        createdAt: Date().addingTimeInterval(-86400 * 30),
        updatedAt: Date(),
        lastPaymentAt: Date().addingTimeInterval(-86400 * 5),
        metadata: ["segment": "premium", "source": "web"]
    )
    #endif
}

struct BillingAddress: Codable {
    let line1: String
    let line2: String?
    let city: String
    let state: String
    let postalCode: String
    let country: String
    
    #if DEBUG
    static let mock = BillingAddress(
        line1: "123 Golf Course Dr",
        line2: "Suite 100",
        city: "Pebble Beach",
        state: "CA",
        postalCode: "93953",
        country: "US"
    )
    #endif
}

struct PaymentMethod: Codable, Identifiable {
    let id: String
    let customerId: String
    let type: PaymentMethodType
    let isDefault: Bool
    let card: CardDetails?
    let bankAccount: BankAccountDetails?
    let walletDetails: WalletDetails?
    let createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
    let fingerprint: String
    let metadata: [String: String]
    
    #if DEBUG
    static let mock = PaymentMethod(
        id: "pm_sample_123",
        customerId: "cus_sample_123",
        type: .card,
        isDefault: true,
        card: CardDetails.mock,
        bankAccount: nil,
        walletDetails: nil,
        createdAt: Date().addingTimeInterval(-86400 * 7),
        updatedAt: Date(),
        lastUsedAt: Date().addingTimeInterval(-86400 * 2),
        fingerprint: "card_fingerprint_abc123",
        metadata: ["nickname": "Primary Card"]
    )
    #endif
}

struct CardDetails: Codable {
    let brand: CardBrand
    let last4: String
    let expiryMonth: Int
    let expiryYear: Int
    let country: String
    let funding: CardFunding
    let fingerprint: String
    let threeDSecure: ThreeDSecureStatus
    
    #if DEBUG
    static let mock = CardDetails(
        brand: .visa,
        last4: "4242",
        expiryMonth: 12,
        expiryYear: 2028,
        country: "US",
        funding: .credit,
        fingerprint: "card_fingerprint_abc123",
        threeDSecure: .supported
    )
    #endif
}

struct BankAccountDetails: Codable {
    let routingNumber: String
    let last4: String
    let accountType: BankAccountType
    let bankName: String
    let country: String
    let currency: String
    let status: BankAccountStatus
}

struct WalletDetails: Codable {
    let type: WalletType
    let email: String?
    let name: String?
}

// MARK: - Payment Models

struct PaymentIntent: Codable, Identifiable {
    let id: String
    let tenantId: String
    let customerId: String
    let amount: Decimal
    let currency: String
    let status: PaymentIntentStatus
    let paymentMethodId: String?
    let description: String?
    let receiptEmail: String?
    let statementDescriptor: String?
    let setupFutureUsage: SetupFutureUsage?
    let captureMethod: CaptureMethod
    let confirmationMethod: ConfirmationMethod
    var charges: [Charge]
    let createdAt: Date
    var confirmedAt: Date?
    var canceledAt: Date?
    let clientSecret: String
    let metadata: [String: String]
    
    #if DEBUG
    static let mock = PaymentIntent(
        id: "pi_sample_123",
        tenantId: "tenant_001",
        customerId: "cus_sample_123",
        amount: 99.00,
        currency: "USD",
        status: .succeeded,
        paymentMethodId: "pm_sample_123",
        description: "Professional Plan Subscription",
        receiptEmail: "john.doe@example.com",
        statementDescriptor: "GOLFFINDER PRO",
        setupFutureUsage: .offSession,
        captureMethod: .automatic,
        confirmationMethod: .automatic,
        charges: [Charge.mock],
        createdAt: Date().addingTimeInterval(-3600),
        confirmedAt: Date().addingTimeInterval(-3500),
        canceledAt: nil,
        clientSecret: "pi_sample_123_secret_abc",
        metadata: ["subscription_id": "sub_123"]
    )
    #endif
}

struct Charge: Codable, Identifiable {
    let id: String
    let paymentIntentId: String
    let amount: Decimal
    let amountCaptured: Decimal
    let amountRefunded: Decimal
    let currency: String
    let status: ChargeStatus
    let paymentMethodId: String
    let description: String?
    let receiptUrl: String?
    let failureCode: String?
    let failureMessage: String?
    let riskLevel: RiskLevel
    let fraudScore: Double
    let disputed: Bool
    let refunded: Bool
    let captured: Bool
    let createdAt: Date
    var paidAt: Date?
    let metadata: [String: String]
    
    #if DEBUG
    static let mock = Charge(
        id: "ch_sample_123",
        paymentIntentId: "pi_sample_123",
        amount: 99.00,
        amountCaptured: 99.00,
        amountRefunded: 0.00,
        currency: "USD",
        status: .succeeded,
        paymentMethodId: "pm_sample_123",
        description: "Professional Plan Subscription",
        receiptUrl: "https://example.com/receipts/ch_sample_123",
        failureCode: nil,
        failureMessage: nil,
        riskLevel: .normal,
        fraudScore: 0.15,
        disputed: false,
        refunded: false,
        captured: true,
        createdAt: Date().addingTimeInterval(-3600),
        paidAt: Date().addingTimeInterval(-3500),
        metadata: ["plan": "professional"]
    )
    #endif
}

struct Refund: Codable, Identifiable {
    let id: String
    let chargeId: String
    let amount: Decimal
    let currency: String
    let status: RefundStatus
    let reason: RefundReason
    let description: String?
    let receiptNumber: String
    let createdAt: Date
    let metadata: [String: String]
    
    #if DEBUG
    static let mock = Refund(
        id: "re_sample_123",
        chargeId: "ch_sample_123",
        amount: 25.00,
        currency: "USD",
        status: .succeeded,
        reason: .requestedByCustomer,
        description: "Partial refund for unused service",
        receiptNumber: "1234-5678-9012",
        createdAt: Date(),
        metadata: ["partial": "true"]
    )
    #endif
}

// MARK: - Invoice Models

struct Invoice: Codable, Identifiable {
    let id: String
    let tenantId: String
    let customerId: String
    let subscriptionId: String?
    let number: String
    let status: InvoiceStatus
    let description: String?
    let amountDue: Decimal
    let amountPaid: Decimal
    let amountRemaining: Decimal
    let subtotal: Decimal
    let tax: Decimal?
    let total: Decimal
    let currency: String
    var dueDate: Date
    let periodStart: Date
    let periodEnd: Date
    var paidAt: Date?
    var voidedAt: Date?
    let attemptCount: Int
    let nextPaymentAttempt: Date?
    let hostedInvoiceUrl: String
    let invoicePdf: String
    let lines: [InvoiceLineItem]
    let discounts: [InvoiceDiscount]
    let createdAt: Date
    let metadata: [String: String]
    
    #if DEBUG
    static let mock = Invoice(
        id: "in_sample_123",
        tenantId: "tenant_001",
        customerId: "cus_sample_123",
        subscriptionId: "sub_sample_123",
        number: "GF-2024-001",
        status: .paid,
        description: "Monthly subscription billing",
        amountDue: 99.00,
        amountPaid: 99.00,
        amountRemaining: 0.00,
        subtotal: 99.00,
        tax: 8.91,
        total: 107.91,
        currency: "USD",
        dueDate: Date().addingTimeInterval(86400 * 30),
        periodStart: Date().addingTimeInterval(-86400 * 30),
        periodEnd: Date(),
        paidAt: Date().addingTimeInterval(-86400 * 25),
        voidedAt: nil,
        attemptCount: 1,
        nextPaymentAttempt: nil,
        hostedInvoiceUrl: "https://invoice.golffinder.app/in_sample_123",
        invoicePdf: "https://files.golffinder.app/invoices/in_sample_123.pdf",
        lines: [InvoiceLineItem.mock],
        discounts: [],
        createdAt: Date().addingTimeInterval(-86400 * 30),
        metadata: ["auto_collection": "charge_automatically"]
    )
    #endif
}

struct InvoiceLineItem: Codable, Identifiable {
    let id: String
    let type: LineItemType
    let description: String
    let amount: Decimal
    let currency: String
    let quantity: Int?
    let unitAmount: Decimal?
    let discountAmount: Decimal?
    let taxAmount: Decimal?
    let period: BillingPeriod?
    let metadata: [String: String]
    
    #if DEBUG
    static let mock = InvoiceLineItem(
        id: "li_sample_123",
        type: .subscription,
        description: "Professional Plan - Monthly",
        amount: 99.00,
        currency: "USD",
        quantity: 1,
        unitAmount: 99.00,
        discountAmount: 0.00,
        taxAmount: 8.91,
        period: BillingPeriod(
            start: Date().addingTimeInterval(-86400 * 30),
            end: Date()
        ),
        metadata: ["plan": "professional"]
    )
    #endif
}

struct InvoiceDiscount: Codable, Identifiable {
    let id: String
    let couponId: String
    let amount: Decimal
    let percentage: Double?
    let description: String
}

struct BillingPeriod: Codable {
    let start: Date
    let end: Date
}

// MARK: - Subscription Billing Models

struct SubscriptionBilling: Codable {
    let subscriptionId: String
    let customerId: String
    let status: SubscriptionBillingStatus
    let currentPeriodStart: Date
    let currentPeriodEnd: Date
    let billingCycleAnchor: Date
    let daysUntilDue: Int?
    let collectionMethod: CollectionMethod
    let defaultPaymentMethod: String?
    let latestInvoice: String?
    let nextInvoiceDate: Date?
    let pausedAt: Date?
    let resumeAt: Date?
    
    #if DEBUG
    static let mock = SubscriptionBilling(
        subscriptionId: "sub_sample_123",
        customerId: "cus_sample_123",
        status: .active,
        currentPeriodStart: Date().addingTimeInterval(-86400 * 15),
        currentPeriodEnd: Date().addingTimeInterval(86400 * 15),
        billingCycleAnchor: Date().addingTimeInterval(-86400 * 15),
        daysUntilDue: nil,
        collectionMethod: .chargeAutomatically,
        defaultPaymentMethod: "pm_sample_123",
        latestInvoice: "in_sample_123",
        nextInvoiceDate: Date().addingTimeInterval(86400 * 15),
        pausedAt: nil,
        resumeAt: nil
    )
    #endif
}

// MARK: - Webhook Models

struct WebhookEvent: Codable, Identifiable {
    let id: String
    let tenantId: String
    let type: WebhookEventType
    let data: WebhookEventData
    let createdAt: Date
    let livemode: Bool
    let pendingWebhooks: Int
    let request: WebhookRequest?
    let apiVersion: String
}

struct WebhookEventData: Codable {
    let object: String
    let previousAttributes: [String: String]?
}

struct WebhookRequest: Codable {
    let id: String
    let idempotencyKey: String?
}

struct WebhookEndpoint: Codable, Identifiable {
    let id: String
    let tenantId: String
    let url: String
    let enabledEvents: [WebhookEventType]
    let status: WebhookEndpointStatus
    let description: String?
    let secret: String
    let createdAt: Date
    var updatedAt: Date
    let metadata: [String: String]
}

struct WebhookDelivery: Codable, Identifiable {
    let id: String
    let eventId: String
    let endpointId: String
    let url: String
    let httpStatusCode: Int?
    let responseHeaders: [String: String]?
    let responseBody: String?
    let attemptCount: Int
    let deliveredAt: Date?
    let nextRetry: Date?
    let createdAt: Date
}

// MARK: - Payment Analytics Models

struct PaymentAnalytics: Codable {
    let tenantId: String
    let period: RevenuePeriod
    let totalVolume: Decimal
    let totalTransactions: Int
    let successRate: Double
    let averageTransactionAmount: Decimal
    let topPaymentMethods: [(PaymentMethodType, Int)]
    let chargebackRate: Double
    let refundRate: Double
    let declineRate: Double
    let fraudRate: Double
    let processingFees: Decimal
    let netRevenue: Decimal
    let generatedAt: Date
    
    #if DEBUG
    static let mock = PaymentAnalytics(
        tenantId: "tenant_001",
        period: .monthly,
        totalVolume: 125000.00,
        totalTransactions: 1250,
        successRate: 0.956,
        averageTransactionAmount: 100.00,
        topPaymentMethods: [(.card, 1000), (.applePay, 200), (.googlePay, 50)],
        chargebackRate: 0.004,
        refundRate: 0.025,
        declineRate: 0.044,
        fraudRate: 0.001,
        processingFees: 3625.00,
        netRevenue: 121375.00,
        generatedAt: Date()
    )
    #endif
}

struct FraudAnalysis: Codable {
    let paymentId: String
    let riskScore: Double
    let riskLevel: RiskLevel
    let riskFactors: [RiskFactor]
    let recommendation: FraudRecommendation
    let decisionReason: String
    let mlModelVersion: String
    let analyzedAt: Date
}

struct RiskFactor: Codable {
    let type: RiskFactorType
    let score: Double
    let description: String
    let weight: Double
}

// MARK: - Billing Result Models

struct BillingResult: Codable {
    let success: Bool
    let paymentIntent: PaymentIntent?
    let error: BillingError?
    let requiresAction: Bool
    let clientSecret: String?
    let nextActionType: NextActionType?
    let message: String?
    let transactionId: String?
    let receiptUrl: String?
    
    #if DEBUG
    static let success = BillingResult(
        success: true,
        paymentIntent: PaymentIntent.mock,
        error: nil,
        requiresAction: false,
        clientSecret: nil,
        nextActionType: nil,
        message: "Payment successful",
        transactionId: "pi_sample_123",
        receiptUrl: "https://example.com/receipts/pi_sample_123"
    )
    
    static let requiresAction = BillingResult(
        success: false,
        paymentIntent: nil,
        error: nil,
        requiresAction: true,
        clientSecret: "pi_sample_123_secret_abc",
        nextActionType: .useStripeSdk,
        message: "Authentication required",
        transactionId: "pi_sample_123",
        receiptUrl: nil
    )
    #endif
}

struct PaymentMethodResult: Codable {
    let success: Bool
    let paymentMethod: PaymentMethod?
    let error: BillingError?
    let message: String?
    
    #if DEBUG
    static let success = PaymentMethodResult(
        success: true,
        paymentMethod: PaymentMethod.mock,
        error: nil,
        message: "Payment method saved successfully"
    )
    #endif
}

// MARK: - Tax Models

struct TaxCalculation: Codable {
    let amount: Decimal
    let currency: String
    let taxAmount: Decimal
    let taxRate: Double
    let jurisdiction: String
    let breakdown: [TaxBreakdown]
}

struct TaxBreakdown: Codable {
    let type: TaxType
    let rate: Double
    let amount: Decimal
    let jurisdiction: String
}

// MARK: - Audit Models

struct BillingAuditLog: Codable, Identifiable {
    let id: String
    let tenantId: String
    let userId: String?
    let action: AuditAction
    let resourceType: AuditResourceType
    let resourceId: String
    let changes: [String: AuditChange]
    let ipAddress: String
    let userAgent: String?
    let timestamp: Date
    let severity: AuditSeverity
    let compliance: [ComplianceStandard]
    let metadata: [String: String]
    
    #if DEBUG
    static let mock = BillingAuditLog(
        id: "audit_123",
        tenantId: "tenant_001",
        userId: "user_123",
        action: .paymentProcessed,
        resourceType: .paymentIntent,
        resourceId: "pi_sample_123",
        changes: [
            "status": AuditChange(from: "requires_confirmation", to: "succeeded")
        ],
        ipAddress: "192.168.1.100",
        userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)",
        timestamp: Date(),
        severity: .info,
        compliance: [.pciDss, .gdpr],
        metadata: ["amount": "99.00", "currency": "USD"]
    )
    #endif
}

struct AuditChange: Codable {
    let from: String?
    let to: String
}

// MARK: - Compliance Models

struct PCIComplianceCheck: Codable {
    let checkId: String
    let tenantId: String
    let checkType: PCICheckType
    let status: ComplianceStatus
    let findings: [ComplianceFinding]
    let score: Double
    let passedRequirements: [String]
    let failedRequirements: [String]
    let recommendations: [String]
    let nextCheckDate: Date
    let performedAt: Date
    let certificationLevel: PCICertificationLevel
}

struct ComplianceFinding: Codable, Identifiable {
    let id: String
    let requirement: String
    let status: ComplianceStatus
    let severity: ComplianceSeverity
    let description: String
    let remediation: String?
    let evidence: [String]
}

// MARK: - Enumerations

enum PaymentMethodType: String, CaseIterable, Codable {
    case card = "card"
    case bankAccount = "bank_account"
    case applePay = "apple_pay"
    case googlePay = "google_pay"
    case paypal = "paypal"
    case venmo = "venmo"
    
    var displayName: String {
        switch self {
        case .card: return "Credit Card"
        case .bankAccount: return "Bank Account"
        case .applePay: return "Apple Pay"
        case .googlePay: return "Google Pay"
        case .paypal: return "PayPal"
        case .venmo: return "Venmo"
        }
    }
}

enum CardBrand: String, CaseIterable, Codable {
    case visa = "visa"
    case mastercard = "mastercard"
    case amex = "amex"
    case discover = "discover"
    case jcb = "jcb"
    case dinersclub = "diners_club"
    case unionpay = "unionpay"
    case unknown = "unknown"
    
    var displayName: String {
        switch self {
        case .visa: return "Visa"
        case .mastercard: return "Mastercard"
        case .amex: return "American Express"
        case .discover: return "Discover"
        case .jcb: return "JCB"
        case .dinersclub: return "Diners Club"
        case .unionpay: return "Union Pay"
        case .unknown: return "Unknown"
        }
    }
}

enum CardFunding: String, CaseIterable, Codable {
    case credit = "credit"
    case debit = "debit"
    case prepaid = "prepaid"
    case unknown = "unknown"
}

enum ThreeDSecureStatus: String, CaseIterable, Codable {
    case required = "required"
    case optional = "optional"
    case notSupported = "not_supported"
    case unknown = "unknown"
    case supported = "supported"
}

enum BankAccountType: String, CaseIterable, Codable {
    case checking = "checking"
    case savings = "savings"
    case business = "business"
}

enum BankAccountStatus: String, CaseIterable, Codable {
    case new = "new"
    case validated = "validated"
    case verified = "verified"
    case verificationFailed = "verification_failed"
    case errored = "errored"
}

enum WalletType: String, CaseIterable, Codable {
    case applePay = "apple_pay"
    case googlePay = "google_pay"
    case samsungPay = "samsung_pay"
    case paypal = "paypal"
    case venmo = "venmo"
}

enum PaymentIntentStatus: String, CaseIterable, Codable {
    case requiresPaymentMethod = "requires_payment_method"
    case requiresConfirmation = "requires_confirmation"
    case requiresAction = "requires_action"
    case processing = "processing"
    case requiresCapture = "requires_capture"
    case canceled = "canceled"
    case succeeded = "succeeded"
    
    var displayName: String {
        switch self {
        case .requiresPaymentMethod: return "Requires Payment Method"
        case .requiresConfirmation: return "Requires Confirmation"
        case .requiresAction: return "Requires Action"
        case .processing: return "Processing"
        case .requiresCapture: return "Requires Capture"
        case .canceled: return "Canceled"
        case .succeeded: return "Succeeded"
        }
    }
}

enum SetupFutureUsage: String, CaseIterable, Codable {
    case none = "none"
    case offSession = "off_session"
    case onSession = "on_session"
}

enum CaptureMethod: String, CaseIterable, Codable {
    case automatic = "automatic"
    case manual = "manual"
}

enum ConfirmationMethod: String, CaseIterable, Codable {
    case automatic = "automatic"
    case manual = "manual"
}

enum ChargeStatus: String, CaseIterable, Codable {
    case pending = "pending"
    case succeeded = "succeeded"
    case failed = "failed"
}

enum RiskLevel: String, CaseIterable, Codable {
    case normal = "normal"
    case elevated = "elevated"
    case highest = "highest"
    
    var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .elevated: return "Elevated"
        case .highest: return "Highest"
        }
    }
}

enum RefundStatus: String, CaseIterable, Codable {
    case pending = "pending"
    case succeeded = "succeeded"
    case failed = "failed"
    case canceled = "canceled"
}

enum RefundReason: String, CaseIterable, Codable {
    case duplicate = "duplicate"
    case fraudulent = "fraudulent"
    case requestedByCustomer = "requested_by_customer"
    case expired = "expired"
    case other = "other"
}

enum InvoiceStatus: String, CaseIterable, Codable {
    case draft = "draft"
    case open = "open"
    case paid = "paid"
    case uncollectible = "uncollectible"
    case void = "void"
    
    var displayName: String {
        switch self {
        case .draft: return "Draft"
        case .open: return "Open"
        case .paid: return "Paid"
        case .uncollectible: return "Uncollectible"
        case .void: return "Void"
        }
    }
}

enum LineItemType: String, CaseIterable, Codable {
    case subscription = "subscription"
    case invoice = "invoice"
    case invoiceitem = "invoiceitem"
}

enum SubscriptionBillingStatus: String, CaseIterable, Codable {
    case active = "active"
    case pastDue = "past_due"
    case unpaid = "unpaid"
    case canceled = "canceled"
    case incomplete = "incomplete"
    case incompleteExpired = "incomplete_expired"
    case trialing = "trialing"
    case paused = "paused"
}

enum CollectionMethod: String, CaseIterable, Codable {
    case chargeAutomatically = "charge_automatically"
    case sendInvoice = "send_invoice"
}

enum WebhookEventType: String, CaseIterable, Codable {
    case paymentIntentSucceeded = "payment_intent.succeeded"
    case paymentIntentFailed = "payment_intent.payment_failed"
    case invoicePaid = "invoice.paid"
    case invoicePaymentFailed = "invoice.payment_failed"
    case customerCreated = "customer.created"
    case customerUpdated = "customer.updated"
    case paymentMethodAttached = "payment_method.attached"
    case chargeDisputed = "charge.dispute.created"
    
    var displayName: String {
        switch self {
        case .paymentIntentSucceeded: return "Payment Intent Succeeded"
        case .paymentIntentFailed: return "Payment Intent Failed"
        case .invoicePaid: return "Invoice Paid"
        case .invoicePaymentFailed: return "Invoice Payment Failed"
        case .customerCreated: return "Customer Created"
        case .customerUpdated: return "Customer Updated"
        case .paymentMethodAttached: return "Payment Method Attached"
        case .chargeDisputed: return "Charge Disputed"
        }
    }
}

enum WebhookEndpointStatus: String, CaseIterable, Codable {
    case enabled = "enabled"
    case disabled = "disabled"
}

enum NextActionType: String, CaseIterable, Codable {
    case useStripeSdk = "use_stripe_sdk"
    case redirectToUrl = "redirect_to_url"
    case displayOtpAction = "display_otp_action"
}

enum TaxType: String, CaseIterable, Codable {
    case vat = "vat"
    case gst = "gst"
    case salesTax = "sales_tax"
    case other = "other"
}

enum AuditAction: String, CaseIterable, Codable {
    case paymentProcessed = "payment_processed"
    case refundIssued = "refund_issued"
    case customerCreated = "customer_created"
    case paymentMethodAdded = "payment_method_added"
    case invoiceGenerated = "invoice_generated"
    case subscriptionCreated = "subscription_created"
    case fraudDetected = "fraud_detected"
    
    var displayName: String {
        switch self {
        case .paymentProcessed: return "Payment Processed"
        case .refundIssued: return "Refund Issued"
        case .customerCreated: return "Customer Created"
        case .paymentMethodAdded: return "Payment Method Added"
        case .invoiceGenerated: return "Invoice Generated"
        case .subscriptionCreated: return "Subscription Created"
        case .fraudDetected: return "Fraud Detected"
        }
    }
}

enum AuditResourceType: String, CaseIterable, Codable {
    case paymentIntent = "payment_intent"
    case customer = "customer"
    case paymentMethod = "payment_method"
    case invoice = "invoice"
    case subscription = "subscription"
    case refund = "refund"
}

enum AuditSeverity: String, CaseIterable, Codable {
    case info = "info"
    case warning = "warning"
    case error = "error"
    case critical = "critical"
}

enum ComplianceStandard: String, CaseIterable, Codable {
    case pciDss = "pci_dss"
    case gdpr = "gdpr"
    case ccpa = "ccpa"
    case hipaa = "hipaa"
    case sox = "sox"
}

enum FraudRecommendation: String, CaseIterable, Codable {
    case allow = "allow"
    case review = "review"
    case block = "block"
    
    var displayName: String {
        switch self {
        case .allow: return "Allow"
        case .review: return "Review"
        case .block: return "Block"
        }
    }
}

enum RiskFactorType: String, CaseIterable, Codable {
    case velocity = "velocity"
    case geolocation = "geolocation"
    case deviceFingerprint = "device_fingerprint"
    case behaviorAnalysis = "behavior_analysis"
    case blacklist = "blacklist"
    case cvvCheck = "cvv_check"
    case avsCheck = "avs_check"
}

enum PCICheckType: String, CaseIterable, Codable {
    case dataEncryption = "data_encryption"
    case accessControl = "access_control"
    case networkSecurity = "network_security"
    case vulnerabilityManagement = "vulnerability_management"
    case securityTesting = "security_testing"
    case monitoringLogging = "monitoring_logging"
}

enum ComplianceStatus: String, CaseIterable, Codable {
    case compliant = "compliant"
    case nonCompliant = "non_compliant"
    case inProgress = "in_progress"
    case notApplicable = "not_applicable"
}

enum ComplianceSeverity: String, CaseIterable, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
}

enum PCICertificationLevel: String, CaseIterable, Codable {
    case level1 = "level_1"
    case level2 = "level_2"
    case level3 = "level_3"
    case level4 = "level_4"
    case serviceProvider = "service_provider"
}

// MARK: - Error Types

enum BillingError: Error, LocalizedError, Codable {
    case customerNotFound(String)
    case paymentMethodNotFound(String)
    case paymentFailed(String)
    case insufficientFunds
    case cardDeclined(String?)
    case invalidPaymentMethod
    case amountTooSmall(Decimal)
    case amountTooLarge(Decimal)
    case currencyNotSupported(String)
    case duplicateTransaction(String)
    case fraudDetected(String)
    case complianceViolation(String)
    case pciViolation(String)
    case rateLimitExceeded
    case webhookDeliveryFailed(String)
    case invoiceNotFound(String)
    case subscriptionNotFound(String)
    case refundFailed(String)
    case authenticationRequired
    case networkError(Error)
    case authorizationError
    
    var errorDescription: String? {
        switch self {
        case .customerNotFound(let id):
            return "Customer with ID \(id) not found"
        case .paymentMethodNotFound(let id):
            return "Payment method with ID \(id) not found"
        case .paymentFailed(let reason):
            return "Payment failed: \(reason)"
        case .insufficientFunds:
            return "Insufficient funds in account"
        case .cardDeclined(let reason):
            return "Card declined\(reason.map { ": \($0)" } ?? "")"
        case .invalidPaymentMethod:
            return "Invalid payment method"
        case .amountTooSmall(let amount):
            return "Amount \(amount) is below minimum"
        case .amountTooLarge(let amount):
            return "Amount \(amount) exceeds maximum"
        case .currencyNotSupported(let currency):
            return "Currency \(currency) is not supported"
        case .duplicateTransaction(let id):
            return "Duplicate transaction detected: \(id)"
        case .fraudDetected(let reason):
            return "Fraud detected: \(reason)"
        case .complianceViolation(let details):
            return "Compliance violation: \(details)"
        case .pciViolation(let details):
            return "PCI compliance violation: \(details)"
        case .rateLimitExceeded:
            return "Rate limit exceeded for billing operations"
        case .webhookDeliveryFailed(let url):
            return "Webhook delivery failed to \(url)"
        case .invoiceNotFound(let id):
            return "Invoice with ID \(id) not found"
        case .subscriptionNotFound(let id):
            return "Subscription with ID \(id) not found"
        case .refundFailed(let reason):
            return "Refund failed: \(reason)"
        case .authenticationRequired:
            return "Additional authentication required"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .authorizationError:
            return "Authorization error: insufficient permissions"
        }
    }
    
    var failureReason: String? {
        return errorDescription
    }
}

// MARK: - Extensions

extension Decimal {
    var currencyFormatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: self as NSDecimalNumber) ?? "$0.00"
    }
}

extension PaymentIntent {
    var isSuccessful: Bool {
        return status == .succeeded
    }
    
    var requiresUserAction: Bool {
        return status == .requiresAction || status == .requiresConfirmation
    }
}

extension Invoice {
    var isPaid: Bool {
        return status == .paid
    }
    
    var isOverdue: Bool {
        return status == .open && dueDate < Date()
    }
    
    var daysOverdue: Int {
        guard isOverdue else { return 0 }
        return Calendar.current.dateComponents([.day], from: dueDate, to: Date()).day ?? 0
    }
}

extension Customer {
    var hasDefaultPaymentMethod: Bool {
        return paymentMethods.contains { $0.isDefault }
    }
    
    var defaultPaymentMethod: PaymentMethod? {
        return paymentMethods.first { $0.isDefault }
    }
}