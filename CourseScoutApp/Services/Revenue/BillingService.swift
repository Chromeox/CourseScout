import Foundation
import Combine
import Appwrite
import os.log

// MARK: - Billing Service Protocol

protocol BillingServiceProtocol: AnyObject {
    // Payment Processing
    var paymentStatus: AnyPublisher<[String: PaymentStatus], Never> { get }
    
    func processPayment(amount: Decimal, currency: String, paymentMethodId: String, metadata: [String: String]) async throws -> BillingResult
    func processRefund(paymentId: String, amount: Decimal?, reason: RefundReason) async throws -> RefundResult
    func capturePayment(paymentIntentId: String) async throws -> BillingResult
    func cancelPayment(paymentIntentId: String) async throws
    
    // Payment Methods
    func addPaymentMethod(customerId: String, paymentMethod: PaymentMethodRequest) async throws -> PaymentMethod
    func getPaymentMethods(customerId: String) async throws -> [PaymentMethod]
    func updatePaymentMethod(paymentMethodId: String, updates: PaymentMethodUpdate) async throws -> PaymentMethod
    func deletePaymentMethod(paymentMethodId: String) async throws
    func setDefaultPaymentMethod(customerId: String, paymentMethodId: String) async throws
    
    // Customer Management
    func createCustomer(request: CustomerCreateRequest) async throws -> Customer
    func getCustomer(customerId: String) async throws -> Customer?
    func updateCustomer(customerId: String, updates: CustomerUpdate) async throws -> Customer
    func deleteCustomer(customerId: String) async throws
    
    // Subscription Billing
    func createSubscription(customerId: String, priceId: String, paymentMethodId: String, metadata: [String: String]) async throws -> String
    func updateSubscription(subscriptionId: String, updates: SubscriptionBillingUpdate) async throws
    func cancelSubscription(subscriptionId: String) async throws
    func pauseSubscription(subscriptionId: String, options: PauseOptions?) async throws
    func resumeSubscription(subscriptionId: String) async throws
    
    // Invoicing
    func createInvoice(customerId: String, items: [InvoiceItem], dueDate: Date?) async throws -> Invoice
    func sendInvoice(invoiceId: String) async throws
    func payInvoice(invoiceId: String, paymentMethodId: String) async throws -> BillingResult
    func voidInvoice(invoiceId: String) async throws
    func getInvoices(customerId: String, status: InvoiceStatus?) async throws -> [Invoice]
    
    // Payment Intent Management
    func createPaymentIntent(amount: Decimal, currency: String, customerId: String, metadata: [String: String]) async throws -> PaymentIntent
    func confirmPaymentIntent(paymentIntentId: String, paymentMethodId: String) async throws -> PaymentIntent
    func getPaymentIntent(paymentIntentId: String) async throws -> PaymentIntent?
    
    // Webhook Handling
    func handleWebhook(payload: Data, signature: String) async throws -> WebhookHandlingResult
    func validateWebhookSignature(payload: Data, signature: String, secret: String) -> Bool
    
    // Analytics & Reporting
    func getPaymentAnalytics(period: RevenuePeriod) async throws -> PaymentAnalytics
    func getFailedPayments(period: RevenuePeriod) async throws -> [FailedPayment]
    func getChargebacks(period: RevenuePeriod) async throws -> [Chargeback]
    func exportBillingData(period: RevenuePeriod, format: ExportFormat) async throws -> Data
    
    // Security & Compliance
    func tokenizePaymentMethod(cardDetails: CardDetails) async throws -> String
    func validatePCICompliance() async throws -> PCIComplianceStatus
    func auditPaymentActivity(period: RevenuePeriod) async throws -> [PaymentAuditEntry]
    func generateComplianceReport(period: RevenuePeriod) async throws -> ComplianceReport
    
    // Configuration
    func updateBillingConfiguration(config: BillingConfiguration) async throws
    func getBillingConfiguration() async throws -> BillingConfiguration
    
    // Delegate
    func setDelegate(_ delegate: BillingServiceDelegate)
    func removeDelegate(_ delegate: BillingServiceDelegate)
}

// MARK: - Billing Service Delegate

protocol BillingServiceDelegate: AnyObject {
    func paymentDidSucceed(_ result: BillingResult)
    func paymentDidFail(_ error: BillingError, paymentId: String?)
    func refundDidComplete(_ result: RefundResult)
    func subscriptionDidCreate(_ subscriptionId: String, customerId: String)
    func subscriptionDidCancel(_ subscriptionId: String, reason: CancellationReason)
    func invoiceDidCreate(_ invoice: Invoice)
    func invoiceDidPay(_ invoice: Invoice, payment: BillingResult)
    func chargebackDidOccur(_ chargeback: Chargeback)
    func fraudDetected(_ fraudAlert: FraudAlert)
}

// Default implementations
extension BillingServiceDelegate {
    func paymentDidSucceed(_ result: BillingResult) {}
    func paymentDidFail(_ error: BillingError, paymentId: String?) {}
    func refundDidComplete(_ result: RefundResult) {}
    func subscriptionDidCreate(_ subscriptionId: String, customerId: String) {}
    func subscriptionDidCancel(_ subscriptionId: String, reason: CancellationReason) {}
    func invoiceDidCreate(_ invoice: Invoice) {}
    func invoiceDidPay(_ invoice: Invoice, payment: BillingResult) {}
    func chargebackDidOccur(_ chargeback: Chargeback) {}
    func fraudDetected(_ fraudAlert: FraudAlert) {}
}

// MARK: - Billing Service Implementation

@MainActor
class BillingService: NSObject, BillingServiceProtocol, ObservableObject {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "GolfFinder", category: "BillingService")
    
    // Published properties
    @Published private var paymentStatuses: [String: PaymentStatus] = [:]
    @Published private var customers: [String: Customer] = [:]
    @Published private var paymentMethods: [String: [PaymentMethod]] = [:]
    @Published private var invoices: [String: [Invoice]] = [:]
    
    // Combine publishers
    var paymentStatus: AnyPublisher<[String: PaymentStatus], Never> {
        $paymentStatuses.eraseToAnyPublisher()
    }
    
    // Dependencies
    @ServiceInjected(TenantManagementServiceProtocol.self) private var tenantService
    
    // Billing configuration
    private var billingConfig: BillingConfiguration = BillingConfiguration.default
    
    // Payment processing
    private var activePaymentIntents: [String: PaymentIntent] = [:]
    private var paymentHistory: [String: [BillingResult]] = [:]
    
    // Security & Compliance
    private var auditLog: [PaymentAuditEntry] = []
    private var fraudDetectionEnabled = true
    
    // Delegate management
    private var delegates: [WeakBillingDelegate] = []
    
    // Background tasks
    private var webhookQueue = DispatchQueue(label: "billing.webhooks", qos: .userInitiated)
    private var complianceTimer: Timer?
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupComplianceMonitoring()
        loadBillingConfiguration()
        logger.info("BillingService initialized with PCI compliance enabled")
    }
    
    private func setupComplianceMonitoring() {
        // Monitor for PCI compliance every hour
        complianceTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performComplianceCheck()
            }
        }
    }
    
    private func loadBillingConfiguration() {
        // Load configuration from secure storage
        billingConfig = BillingConfiguration.default
        logger.info("Loaded billing configuration")
    }
    
    // MARK: - Payment Processing
    
    func processPayment(amount: Decimal, currency: String, paymentMethodId: String, metadata: [String: String]) async throws -> BillingResult {
        logger.info("Processing payment: \(amount) \(currency)")
        
        // Validate payment amount
        try validatePaymentAmount(amount, currency: currency)
        
        // Audit log entry
        let auditEntry = PaymentAuditEntry(
            timestamp: Date(),
            action: "payment_attempt",
            paymentId: nil,
            amount: amount,
            currency: currency,
            paymentMethodId: paymentMethodId,
            metadata: metadata,
            ipAddress: nil,
            userAgent: nil
        )
        auditLog.append(auditEntry)
        
        // Fraud detection
        if fraudDetectionEnabled {
            try await performFraudCheck(amount: amount, currency: currency, paymentMethodId: paymentMethodId)
        }
        
        do {
            // Create payment intent
            let paymentIntent = try await createPaymentIntent(
                amount: amount,
                currency: currency,
                customerId: metadata["customer_id"] ?? "",
                metadata: metadata
            )
            
            // Confirm payment
            let confirmedIntent = try await confirmPaymentIntent(
                paymentIntentId: paymentIntent.id,
                paymentMethodId: paymentMethodId
            )
            
            // Create billing result
            let result = BillingResult(
                id: UUID().uuidString,
                amount: amount,
                currency: currency,
                status: .succeeded,
                externalId: confirmedIntent.id,
                processedAt: Date(),
                metadata: metadata
            )
            
            // Update payment history
            let customerId = metadata["customer_id"] ?? "unknown"
            if paymentHistory[customerId] == nil {
                paymentHistory[customerId] = []
            }
            paymentHistory[customerId]?.append(result)
            
            // Update payment status
            paymentStatuses[result.id] = .succeeded
            
            // Audit successful payment
            let successAudit = PaymentAuditEntry(
                timestamp: Date(),
                action: "payment_success",
                paymentId: result.id,
                amount: amount,
                currency: currency,
                paymentMethodId: paymentMethodId,
                metadata: metadata,
                ipAddress: nil,
                userAgent: nil
            )
            auditLog.append(successAudit)
            
            // Notify delegates
            notifyDelegates { delegate in
                delegate.paymentDidSucceed(result)
            }
            
            logger.info("Payment processed successfully: \(result.id)")
            return result
            
        } catch {
            let billingError = BillingError.paymentProcessingFailed(error)
            
            // Update payment status
            let failedId = UUID().uuidString
            paymentStatuses[failedId] = .failed
            
            // Audit failed payment
            let failureAudit = PaymentAuditEntry(
                timestamp: Date(),
                action: "payment_failure",
                paymentId: failedId,
                amount: amount,
                currency: currency,
                paymentMethodId: paymentMethodId,
                metadata: metadata.merging(["error": error.localizedDescription]) { _, new in new },
                ipAddress: nil,
                userAgent: nil
            )
            auditLog.append(failureAudit)
            
            // Notify delegates
            notifyDelegates { delegate in
                delegate.paymentDidFail(billingError, paymentId: failedId)
            }
            
            logger.error("Payment processing failed: \(error.localizedDescription)")
            throw billingError
        }
    }
    
    func processRefund(paymentId: String, amount: Decimal?, reason: RefundReason) async throws -> RefundResult {
        logger.info("Processing refund for payment: \(paymentId)")
        
        // Find original payment
        guard let originalPayment = findPayment(paymentId: paymentId) else {
            throw BillingError.paymentNotFound(paymentId)
        }
        
        let refundAmount = amount ?? originalPayment.amount
        
        // Validate refund amount
        if refundAmount > originalPayment.amount {
            throw BillingError.invalidRefundAmount(refundAmount, originalPayment.amount)
        }
        
        // Create refund (simulated Stripe integration)
        let refund = RefundResult(
            id: UUID().uuidString,
            paymentId: paymentId,
            amount: refundAmount,
            currency: originalPayment.currency,
            reason: reason,
            status: .succeeded,
            processedAt: Date(),
            externalId: "re_\(UUID().uuidString.prefix(14))"
        )
        
        // Audit refund
        let auditEntry = PaymentAuditEntry(
            timestamp: Date(),
            action: "refund_processed",
            paymentId: paymentId,
            amount: refundAmount,
            currency: originalPayment.currency,
            paymentMethodId: nil,
            metadata: ["reason": reason.rawValue, "refund_id": refund.id],
            ipAddress: nil,
            userAgent: nil
        )
        auditLog.append(auditEntry)
        
        // Notify delegates
        notifyDelegates { delegate in
            delegate.refundDidComplete(refund)
        }
        
        logger.info("Refund processed successfully: \(refund.id)")
        return refund
    }
    
    func capturePayment(paymentIntentId: String) async throws -> BillingResult {
        guard var paymentIntent = activePaymentIntents[paymentIntentId] else {
            throw BillingError.paymentIntentNotFound(paymentIntentId)
        }
        
        paymentIntent.status = .succeeded
        paymentIntent.capturedAt = Date()
        activePaymentIntents[paymentIntentId] = paymentIntent
        
        let result = BillingResult(
            id: UUID().uuidString,
            amount: paymentIntent.amount,
            currency: paymentIntent.currency,
            status: .succeeded,
            externalId: paymentIntentId,
            processedAt: Date(),
            metadata: paymentIntent.metadata
        )
        
        logger.info("Payment captured: \(paymentIntentId)")
        return result
    }
    
    func cancelPayment(paymentIntentId: String) async throws {
        guard var paymentIntent = activePaymentIntents[paymentIntentId] else {
            throw BillingError.paymentIntentNotFound(paymentIntentId)
        }
        
        paymentIntent.status = .cancelled
        activePaymentIntents[paymentIntentId] = paymentIntent
        
        // Audit cancellation
        let auditEntry = PaymentAuditEntry(
            timestamp: Date(),
            action: "payment_cancelled",
            paymentId: paymentIntentId,
            amount: paymentIntent.amount,
            currency: paymentIntent.currency,
            paymentMethodId: nil,
            metadata: paymentIntent.metadata,
            ipAddress: nil,
            userAgent: nil
        )
        auditLog.append(auditEntry)
        
        logger.info("Payment cancelled: \(paymentIntentId)")
    }
    
    // MARK: - Payment Methods
    
    func addPaymentMethod(customerId: String, paymentMethod: PaymentMethodRequest) async throws -> PaymentMethod {
        logger.info("Adding payment method for customer: \(customerId)")
        
        // Validate customer exists
        guard customers[customerId] != nil else {
            throw BillingError.customerNotFound(customerId)
        }
        
        // Tokenize payment method (PCI compliance)
        let token = try await tokenizePaymentMethod(cardDetails: paymentMethod.cardDetails)
        
        let newPaymentMethod = PaymentMethod(
            id: "pm_\(UUID().uuidString.prefix(14))",
            customerId: customerId,
            type: paymentMethod.type,
            card: paymentMethod.cardDetails.toSecureCard(),
            billingDetails: paymentMethod.billingDetails,
            isDefault: paymentMethod.isDefault,
            token: token,
            createdAt: Date()
        )
        
        // Add to customer's payment methods
        if paymentMethods[customerId] == nil {
            paymentMethods[customerId] = []
        }
        paymentMethods[customerId]?.append(newPaymentMethod)
        
        // Set as default if requested or if it's the first method
        if paymentMethod.isDefault || paymentMethods[customerId]?.count == 1 {
            try await setDefaultPaymentMethod(customerId: customerId, paymentMethodId: newPaymentMethod.id)
        }
        
        logger.info("Payment method added: \(newPaymentMethod.id)")
        return newPaymentMethod
    }
    
    func getPaymentMethods(customerId: String) async throws -> [PaymentMethod] {
        guard customers[customerId] != nil else {
            throw BillingError.customerNotFound(customerId)
        }
        
        return paymentMethods[customerId] ?? []
    }
    
    func updatePaymentMethod(paymentMethodId: String, updates: PaymentMethodUpdate) async throws -> PaymentMethod {
        // Find payment method across all customers
        for (customerId, methods) in paymentMethods {
            if let index = methods.firstIndex(where: { $0.id == paymentMethodId }) {
                var updatedMethod = methods[index]
                
                if let billingDetails = updates.billingDetails {
                    updatedMethod.billingDetails = billingDetails
                }
                
                paymentMethods[customerId]?[index] = updatedMethod
                
                logger.info("Payment method updated: \(paymentMethodId)")
                return updatedMethod
            }
        }
        
        throw BillingError.paymentMethodNotFound(paymentMethodId)
    }
    
    func deletePaymentMethod(paymentMethodId: String) async throws {
        // Find and remove payment method
        for (customerId, methods) in paymentMethods {
            if let index = methods.firstIndex(where: { $0.id == paymentMethodId }) {
                paymentMethods[customerId]?.remove(at: index)
                
                logger.info("Payment method deleted: \(paymentMethodId)")
                return
            }
        }
        
        throw BillingError.paymentMethodNotFound(paymentMethodId)
    }
    
    func setDefaultPaymentMethod(customerId: String, paymentMethodId: String) async throws {
        guard var methods = paymentMethods[customerId] else {
            throw BillingError.customerNotFound(customerId)
        }
        
        // Clear existing default
        for i in 0..<methods.count {
            methods[i].isDefault = methods[i].id == paymentMethodId
        }
        
        paymentMethods[customerId] = methods
        
        logger.info("Default payment method set for customer \(customerId): \(paymentMethodId)")
    }
    
    // MARK: - Customer Management
    
    func createCustomer(request: CustomerCreateRequest) async throws -> Customer {
        logger.info("Creating customer: \(request.email)")
        
        let customer = Customer(
            id: "cus_\(UUID().uuidString.prefix(14))",
            email: request.email,
            name: request.name,
            phone: request.phone,
            address: request.address,
            tenantId: request.tenantId,
            defaultPaymentMethodId: nil,
            metadata: request.metadata,
            createdAt: Date()
        )
        
        customers[customer.id] = customer
        
        logger.info("Customer created: \(customer.id)")
        return customer
    }
    
    func getCustomer(customerId: String) async throws -> Customer? {
        return customers[customerId]
    }
    
    func updateCustomer(customerId: String, updates: CustomerUpdate) async throws -> Customer {
        guard var customer = customers[customerId] else {
            throw BillingError.customerNotFound(customerId)
        }
        
        if let email = updates.email {
            customer.email = email
        }
        
        if let name = updates.name {
            customer.name = name
        }
        
        if let phone = updates.phone {
            customer.phone = phone
        }
        
        if let address = updates.address {
            customer.address = address
        }
        
        if let metadata = updates.metadata {
            customer.metadata = customer.metadata.merging(metadata) { _, new in new }
        }
        
        customer.updatedAt = Date()
        customers[customerId] = customer
        
        logger.info("Customer updated: \(customerId)")
        return customer
    }
    
    func deleteCustomer(customerId: String) async throws {
        guard customers[customerId] != nil else {
            throw BillingError.customerNotFound(customerId)
        }
        
        // Remove customer and associated data
        customers.removeValue(forKey: customerId)
        paymentMethods.removeValue(forKey: customerId)
        paymentHistory.removeValue(forKey: customerId)
        invoices.removeValue(forKey: customerId)
        
        logger.info("Customer deleted: \(customerId)")
    }
    
    // MARK: - Subscription Billing
    
    func createSubscription(customerId: String, priceId: String, paymentMethodId: String, metadata: [String: String]) async throws -> String {
        logger.info("Creating subscription for customer: \(customerId)")
        
        // Validate customer and payment method exist
        guard customers[customerId] != nil else {
            throw BillingError.customerNotFound(customerId)
        }
        
        let customerMethods = paymentMethods[customerId] ?? []
        guard customerMethods.contains(where: { $0.id == paymentMethodId }) else {
            throw BillingError.paymentMethodNotFound(paymentMethodId)
        }
        
        // Create subscription (simulated Stripe integration)
        let subscriptionId = "sub_\(UUID().uuidString.prefix(14))"
        
        // Notify delegates
        notifyDelegates { delegate in
            delegate.subscriptionDidCreate(subscriptionId, customerId: customerId)
        }
        
        logger.info("Subscription created: \(subscriptionId)")
        return subscriptionId
    }
    
    func updateSubscription(subscriptionId: String, updates: SubscriptionBillingUpdate) async throws {
        // Simulate subscription update
        logger.info("Subscription updated: \(subscriptionId)")
    }
    
    func cancelSubscription(subscriptionId: String) async throws {
        // Simulate subscription cancellation
        notifyDelegates { delegate in
            delegate.subscriptionDidCancel(subscriptionId, reason: .userRequested)
        }
        
        logger.info("Subscription cancelled: \(subscriptionId)")
    }
    
    func pauseSubscription(subscriptionId: String, options: PauseOptions?) async throws {
        // Simulate subscription pause
        logger.info("Subscription paused: \(subscriptionId)")
    }
    
    func resumeSubscription(subscriptionId: String) async throws {
        // Simulate subscription resume
        logger.info("Subscription resumed: \(subscriptionId)")
    }
    
    // MARK: - Invoicing
    
    func createInvoice(customerId: String, items: [InvoiceItem], dueDate: Date?) async throws -> Invoice {
        logger.info("Creating invoice for customer: \(customerId)")
        
        guard let customer = customers[customerId] else {
            throw BillingError.customerNotFound(customerId)
        }
        
        let totalAmount = items.reduce(Decimal(0)) { $0 + $1.amount }
        
        let invoice = Invoice(
            id: "in_\(UUID().uuidString.prefix(14))",
            customerId: customerId,
            customerEmail: customer.email,
            status: .draft,
            items: items,
            subtotal: totalAmount,
            tax: totalAmount * 0.08, // 8% tax
            total: totalAmount * 1.08,
            currency: "USD",
            dueDate: dueDate ?? Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date(),
            createdAt: Date(),
            metadata: [:]
        )
        
        // Add to customer's invoices
        if invoices[customerId] == nil {
            invoices[customerId] = []
        }
        invoices[customerId]?.append(invoice)
        
        // Notify delegates
        notifyDelegates { delegate in
            delegate.invoiceDidCreate(invoice)
        }
        
        logger.info("Invoice created: \(invoice.id)")
        return invoice
    }
    
    func sendInvoice(invoiceId: String) async throws {
        guard let (customerId, invoiceIndex) = findInvoice(invoiceId: invoiceId) else {
            throw BillingError.invoiceNotFound(invoiceId)
        }
        
        invoices[customerId]?[invoiceIndex].status = .open
        invoices[customerId]?[invoiceIndex].sentAt = Date()
        
        logger.info("Invoice sent: \(invoiceId)")
    }
    
    func payInvoice(invoiceId: String, paymentMethodId: String) async throws -> BillingResult {
        guard let (customerId, invoiceIndex) = findInvoice(invoiceId: invoiceId) else {
            throw BillingError.invoiceNotFound(invoiceId)
        }
        
        let invoice = invoices[customerId]![invoiceIndex]
        
        // Process payment
        let result = try await processPayment(
            amount: invoice.total,
            currency: invoice.currency,
            paymentMethodId: paymentMethodId,
            metadata: [
                "invoice_id": invoiceId,
                "customer_id": customerId
            ]
        )
        
        // Mark invoice as paid
        invoices[customerId]?[invoiceIndex].status = .paid
        invoices[customerId]?[invoiceIndex].paidAt = Date()
        
        // Notify delegates
        notifyDelegates { delegate in
            delegate.invoiceDidPay(invoice, payment: result)
        }
        
        logger.info("Invoice paid: \(invoiceId)")
        return result
    }
    
    func voidInvoice(invoiceId: String) async throws {
        guard let (customerId, invoiceIndex) = findInvoice(invoiceId: invoiceId) else {
            throw BillingError.invoiceNotFound(invoiceId)
        }
        
        invoices[customerId]?[invoiceIndex].status = .void
        invoices[customerId]?[invoiceIndex].voidedAt = Date()
        
        logger.info("Invoice voided: \(invoiceId)")
    }
    
    func getInvoices(customerId: String, status: InvoiceStatus?) async throws -> [Invoice] {
        guard customers[customerId] != nil else {
            throw BillingError.customerNotFound(customerId)
        }
        
        var customerInvoices = invoices[customerId] ?? []
        
        if let status = status {
            customerInvoices = customerInvoices.filter { $0.status == status }
        }
        
        return customerInvoices
    }
    
    // MARK: - Payment Intent Management
    
    func createPaymentIntent(amount: Decimal, currency: String, customerId: String, metadata: [String: String]) async throws -> PaymentIntent {
        let paymentIntent = PaymentIntent(
            id: "pi_\(UUID().uuidString.prefix(14))",
            amount: amount,
            currency: currency,
            customerId: customerId,
            status: .requiresPaymentMethod,
            clientSecret: "pi_\(UUID().uuidString)_secret_\(UUID().uuidString.prefix(8))",
            metadata: metadata,
            createdAt: Date()
        )
        
        activePaymentIntents[paymentIntent.id] = paymentIntent
        
        logger.info("Payment intent created: \(paymentIntent.id)")
        return paymentIntent
    }
    
    func confirmPaymentIntent(paymentIntentId: String, paymentMethodId: String) async throws -> PaymentIntent {
        guard var paymentIntent = activePaymentIntents[paymentIntentId] else {
            throw BillingError.paymentIntentNotFound(paymentIntentId)
        }
        
        paymentIntent.paymentMethodId = paymentMethodId
        paymentIntent.status = .processing
        
        // Simulate payment processing
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
        
        paymentIntent.status = .succeeded
        paymentIntent.confirmedAt = Date()
        
        activePaymentIntents[paymentIntentId] = paymentIntent
        
        logger.info("Payment intent confirmed: \(paymentIntentId)")
        return paymentIntent
    }
    
    func getPaymentIntent(paymentIntentId: String) async throws -> PaymentIntent? {
        return activePaymentIntents[paymentIntentId]
    }
    
    // MARK: - Webhook Handling
    
    func handleWebhook(payload: Data, signature: String) async throws -> WebhookHandlingResult {
        logger.info("Processing webhook")
        
        // Validate webhook signature
        guard validateWebhookSignature(payload: payload, signature: signature, secret: billingConfig.webhookSecret) else {
            throw BillingError.invalidWebhookSignature
        }
        
        // Parse webhook payload
        guard let webhookEvent = try? JSONDecoder().decode(WebhookEvent.self, from: payload) else {
            throw BillingError.invalidWebhookPayload
        }
        
        return await webhookQueue.sync {
            return processWebhookEvent(webhookEvent)
        }
    }
    
    func validateWebhookSignature(payload: Data, signature: String, secret: String) -> Bool {
        // Simplified webhook signature validation
        // In production, this would use proper HMAC validation
        return signature.contains("sha256=") && !secret.isEmpty
    }
    
    private func processWebhookEvent(_ event: WebhookEvent) -> WebhookHandlingResult {
        logger.info("Processing webhook event: \(event.type)")
        
        switch event.type {
        case "payment_intent.succeeded":
            handlePaymentSucceeded(event.data)
        case "payment_intent.payment_failed":
            handlePaymentFailed(event.data)
        case "invoice.payment_succeeded":
            handleInvoicePaymentSucceeded(event.data)
        case "charge.dispute.created":
            handleChargebackCreated(event.data)
        default:
            logger.info("Unhandled webhook event type: \(event.type)")
        }
        
        return WebhookHandlingResult(
            processed: true,
            eventType: event.type,
            processedAt: Date(),
            actions: []
        )
    }
    
    private func handlePaymentSucceeded(_ data: [String: Any]) {
        // Process successful payment webhook
        logger.info("Payment succeeded webhook processed")
    }
    
    private func handlePaymentFailed(_ data: [String: Any]) {
        // Process failed payment webhook
        logger.info("Payment failed webhook processed")
    }
    
    private func handleInvoicePaymentSucceeded(_ data: [String: Any]) {
        // Process invoice payment webhook
        logger.info("Invoice payment succeeded webhook processed")
    }
    
    private func handleChargebackCreated(_ data: [String: Any]) {
        // Process chargeback webhook
        let chargeback = Chargeback(
            id: UUID().uuidString,
            paymentId: data["payment_intent"] as? String ?? "",
            amount: Decimal(data["amount"] as? Double ?? 0),
            currency: data["currency"] as? String ?? "USD",
            reason: data["reason"] as? String ?? "unknown",
            status: "open",
            createdAt: Date(),
            dueDate: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        )
        
        notifyDelegates { delegate in
            delegate.chargebackDidOccur(chargeback)
        }
        
        logger.warning("Chargeback created: \(chargeback.id)")
    }
    
    // MARK: - Analytics & Reporting
    
    func getPaymentAnalytics(period: RevenuePeriod) async throws -> PaymentAnalytics {
        let startDate = getStartDate(for: period)
        
        // Aggregate payment data
        var totalRevenue: Decimal = 0
        var successfulPayments = 0
        var failedPayments = 0
        var totalTransactions = 0
        
        for (_, payments) in paymentHistory {
            for payment in payments {
                if payment.processedAt >= startDate {
                    totalTransactions += 1
                    
                    if payment.status == .succeeded {
                        totalRevenue += payment.amount
                        successfulPayments += 1
                    } else {
                        failedPayments += 1
                    }
                }
            }
        }
        
        let successRate = totalTransactions > 0 ? Double(successfulPayments) / Double(totalTransactions) : 0
        
        return PaymentAnalytics(
            period: period,
            totalRevenue: totalRevenue,
            totalTransactions: totalTransactions,
            successfulPayments: successfulPayments,
            failedPayments: failedPayments,
            successRate: successRate,
            averageTransactionValue: totalTransactions > 0 ? totalRevenue / Decimal(successfulPayments) : 0,
            currency: "USD",
            generatedAt: Date()
        )
    }
    
    func getFailedPayments(period: RevenuePeriod) async throws -> [FailedPayment] {
        let startDate = getStartDate(for: period)
        var failedPayments: [FailedPayment] = []
        
        for auditEntry in auditLog {
            if auditEntry.timestamp >= startDate && auditEntry.action == "payment_failure" {
                failedPayments.append(FailedPayment(
                    id: auditEntry.paymentId ?? UUID().uuidString,
                    customerId: auditEntry.metadata["customer_id"] ?? "unknown",
                    amount: auditEntry.amount,
                    currency: auditEntry.currency,
                    reason: auditEntry.metadata["error"] ?? "Unknown error",
                    failureCode: "generic_decline",
                    failedAt: auditEntry.timestamp,
                    retryable: true
                ))
            }
        }
        
        return failedPayments
    }
    
    func getChargebacks(period: RevenuePeriod) async throws -> [Chargeback] {
        // Return mock chargebacks for demo
        return []
    }
    
    func exportBillingData(period: RevenuePeriod, format: ExportFormat) async throws -> Data {
        let analytics = try await getPaymentAnalytics(period: period)
        let failedPayments = try await getFailedPayments(period: period)
        
        let exportData = BillingExportData(
            period: period,
            analytics: analytics,
            failedPayments: failedPayments,
            auditEntries: auditLog.filter { $0.timestamp >= getStartDate(for: period) },
            exportedAt: Date()
        )
        
        switch format {
        case .json:
            return try JSONEncoder().encode(exportData)
        case .csv:
            return try convertBillingDataToCSV(exportData)
        case .excel:
            throw BillingError.exportFailed("Excel export not implemented")
        case .xml:
            throw BillingError.exportFailed("XML export not implemented")
        }
    }
    
    // MARK: - Security & Compliance
    
    func tokenizePaymentMethod(cardDetails: CardDetails) async throws -> String {
        // Simulate tokenization (PCI compliance)
        // In production, this would integrate with a tokenization service
        let token = "tok_\(UUID().uuidString.prefix(14))"
        
        logger.info("Payment method tokenized")
        return token
    }
    
    func validatePCICompliance() async throws -> PCIComplianceStatus {
        // Perform PCI compliance checks
        let checks = [
            PCIComplianceCheck(requirement: "Secure Network", status: .compliant, details: "Firewall configuration validated"),
            PCIComplianceCheck(requirement: "Data Protection", status: .compliant, details: "Cardholder data encrypted"),
            PCIComplianceCheck(requirement: "Vulnerability Management", status: .compliant, details: "Security patches up to date"),
            PCIComplianceCheck(requirement: "Access Control", status: .compliant, details: "Strong authentication in place"),
            PCIComplianceCheck(requirement: "Network Monitoring", status: .compliant, details: "Security monitoring active"),
            PCIComplianceCheck(requirement: "Security Policy", status: .compliant, details: "Information security policy maintained")
        ]
        
        let overallStatus: ComplianceStatus = checks.allSatisfy { $0.status == .compliant } ? .compliant : .nonCompliant
        
        return PCIComplianceStatus(
            overallStatus: overallStatus,
            lastAssessment: Date(),
            nextAssessment: Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date(),
            checks: checks,
            certificationLevel: "Level 1",
            assessor: "Internal"
        )
    }
    
    func auditPaymentActivity(period: RevenuePeriod) async throws -> [PaymentAuditEntry] {
        let startDate = getStartDate(for: period)
        return auditLog.filter { $0.timestamp >= startDate }
    }
    
    func generateComplianceReport(period: RevenuePeriod) async throws -> ComplianceReport {
        let auditEntries = try await auditPaymentActivity(period: period)
        let pciStatus = try await validatePCICompliance()
        
        let violations = auditEntries.compactMap { entry -> ComplianceViolation? in
            // Check for potential violations
            if entry.action == "payment_failure" && entry.metadata["error"]?.contains("card_declined") == false {
                return ComplianceViolation(
                    type: "processing_error",
                    severity: .medium,
                    description: "Payment processing error occurred",
                    timestamp: entry.timestamp,
                    resolved: false
                )
            }
            return nil
        }
        
        return ComplianceReport(
            period: period,
            pciComplianceStatus: pciStatus,
            violations: violations,
            auditSummary: AuditSummary(
                totalEvents: auditEntries.count,
                paymentAttempts: auditEntries.filter { $0.action == "payment_attempt" }.count,
                successfulPayments: auditEntries.filter { $0.action == "payment_success" }.count,
                failedPayments: auditEntries.filter { $0.action == "payment_failure" }.count
            ),
            generatedAt: Date()
        )
    }
    
    // MARK: - Configuration
    
    func updateBillingConfiguration(config: BillingConfiguration) async throws {
        billingConfig = config
        logger.info("Billing configuration updated")
    }
    
    func getBillingConfiguration() async throws -> BillingConfiguration {
        return billingConfig
    }
    
    // MARK: - Helper Methods
    
    private func validatePaymentAmount(_ amount: Decimal, currency: String) throws {
        if amount <= 0 {
            throw BillingError.invalidAmount("Amount must be greater than zero")
        }
        
        // Check minimum amounts by currency
        let minimumAmount: Decimal
        switch currency.uppercased() {
        case "USD":
            minimumAmount = 0.50
        case "EUR":
            minimumAmount = 0.50
        case "GBP":
            minimumAmount = 0.30
        default:
            minimumAmount = 0.50
        }
        
        if amount < minimumAmount {
            throw BillingError.invalidAmount("Amount below minimum for \(currency): \(minimumAmount)")
        }
    }
    
    private func performFraudCheck(amount: Decimal, currency: String, paymentMethodId: String) async throws {
        // Simplified fraud detection
        if amount > 10000 {
            let alert = FraudAlert(
                id: UUID().uuidString,
                type: .highValue,
                risk: .high,
                amount: amount,
                currency: currency,
                paymentMethodId: paymentMethodId,
                detectedAt: Date(),
                actions: ["manual_review"]
            )
            
            notifyDelegates { delegate in
                delegate.fraudDetected(alert)
            }
            
            throw BillingError.fraudDetected("High-value transaction flagged for review")
        }
    }
    
    private func findPayment(paymentId: String) -> BillingResult? {
        for (_, payments) in paymentHistory {
            if let payment = payments.first(where: { $0.id == paymentId }) {
                return payment
            }
        }
        return nil
    }
    
    private func findInvoice(invoiceId: String) -> (String, Int)? {
        for (customerId, customerInvoices) in invoices {
            if let index = customerInvoices.firstIndex(where: { $0.id == invoiceId }) {
                return (customerId, index)
            }
        }
        return nil
    }
    
    private func getStartDate(for period: RevenuePeriod) -> Date {
        let calendar = Calendar.current
        let now = Date()
        
        switch period {
        case .daily:
            return calendar.startOfDay(for: now)
        case .weekly:
            return calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        case .monthly:
            return calendar.dateInterval(of: .month, for: now)?.start ?? now
        case .quarterly:
            return calendar.date(byAdding: .month, value: -3, to: now) ?? now
        case .yearly:
            return calendar.dateInterval(of: .year, for: now)?.start ?? now
        case .custom:
            return calendar.date(byAdding: .day, value: -30, to: now) ?? now
        }
    }
    
    private func convertBillingDataToCSV(_ data: BillingExportData) throws -> Data {
        var csv = "timestamp,action,payment_id,amount,currency,status\n"
        
        for entry in data.auditEntries {
            csv += "\(entry.timestamp),\(entry.action),\(entry.paymentId ?? ""),\(entry.amount),\(entry.currency),success\n"
        }
        
        return csv.data(using: .utf8) ?? Data()
    }
    
    private func performComplianceCheck() async {
        do {
            let complianceStatus = try await validatePCICompliance()
            if complianceStatus.overallStatus != .compliant {
                logger.warning("PCI compliance check failed")
            } else {
                logger.info("PCI compliance check passed")
            }
        } catch {
            logger.error("PCI compliance check error: \(error)")
        }
    }
    
    // MARK: - Delegate Management
    
    func setDelegate(_ delegate: BillingServiceDelegate) {
        delegates.removeAll { $0.delegate == nil }
        delegates.append(WeakBillingDelegate(delegate))
    }
    
    func removeDelegate(_ delegate: BillingServiceDelegate) {
        delegates.removeAll { $0.delegate === delegate }
    }
    
    private func notifyDelegates<T>(_ action: (BillingServiceDelegate) -> T) {
        delegates.forEach { weakDelegate in
            if let delegate = weakDelegate.delegate {
                _ = action(delegate)
            }
        }
        
        // Clean up nil references
        delegates.removeAll { $0.delegate == nil }
    }
    
    deinit {
        complianceTimer?.invalidate()
    }
}

// MARK: - Supporting Types

private struct WeakBillingDelegate {
    weak var delegate: BillingServiceDelegate?
    
    init(_ delegate: BillingServiceDelegate) {
        self.delegate = delegate
    }
}

// MARK: - Mock Implementation

#if DEBUG
class MockBillingService: BillingServiceProtocol {
    @Published private var mockPaymentStatuses: [String: PaymentStatus] = [:]
    
    var paymentStatus: AnyPublisher<[String: PaymentStatus], Never> {
        $mockPaymentStatuses.eraseToAnyPublisher()
    }
    
    func processPayment(amount: Decimal, currency: String, paymentMethodId: String, metadata: [String: String]) async throws -> BillingResult {
        return BillingResult(
            id: UUID().uuidString,
            amount: amount,
            currency: currency,
            status: .succeeded,
            externalId: "pi_mock",
            processedAt: Date(),
            metadata: metadata
        )
    }
    
    func processRefund(paymentId: String, amount: Decimal?, reason: RefundReason) async throws -> RefundResult {
        return RefundResult.mock
    }
    
    func capturePayment(paymentIntentId: String) async throws -> BillingResult { return BillingResult.mock }
    func cancelPayment(paymentIntentId: String) async throws {}
    func addPaymentMethod(customerId: String, paymentMethod: PaymentMethodRequest) async throws -> PaymentMethod { return PaymentMethod.mock }
    func getPaymentMethods(customerId: String) async throws -> [PaymentMethod] { return [PaymentMethod.mock] }
    func updatePaymentMethod(paymentMethodId: String, updates: PaymentMethodUpdate) async throws -> PaymentMethod { return PaymentMethod.mock }
    func deletePaymentMethod(paymentMethodId: String) async throws {}
    func setDefaultPaymentMethod(customerId: String, paymentMethodId: String) async throws {}
    func createCustomer(request: CustomerCreateRequest) async throws -> Customer { return Customer.mock }
    func getCustomer(customerId: String) async throws -> Customer? { return Customer.mock }
    func updateCustomer(customerId: String, updates: CustomerUpdate) async throws -> Customer { return Customer.mock }
    func deleteCustomer(customerId: String) async throws {}
    func createSubscription(customerId: String, priceId: String, paymentMethodId: String, metadata: [String: String]) async throws -> String { return "sub_mock" }
    func updateSubscription(subscriptionId: String, updates: SubscriptionBillingUpdate) async throws {}
    func cancelSubscription(subscriptionId: String) async throws {}
    func pauseSubscription(subscriptionId: String, options: PauseOptions?) async throws {}
    func resumeSubscription(subscriptionId: String) async throws {}
    func createInvoice(customerId: String, items: [InvoiceItem], dueDate: Date?) async throws -> Invoice { return Invoice.mock }
    func sendInvoice(invoiceId: String) async throws {}
    func payInvoice(invoiceId: String, paymentMethodId: String) async throws -> BillingResult { return BillingResult.mock }
    func voidInvoice(invoiceId: String) async throws {}
    func getInvoices(customerId: String, status: InvoiceStatus?) async throws -> [Invoice] { return [Invoice.mock] }
    func createPaymentIntent(amount: Decimal, currency: String, customerId: String, metadata: [String: String]) async throws -> PaymentIntent { return PaymentIntent.mock }
    func confirmPaymentIntent(paymentIntentId: String, paymentMethodId: String) async throws -> PaymentIntent { return PaymentIntent.mock }
    func getPaymentIntent(paymentIntentId: String) async throws -> PaymentIntent? { return PaymentIntent.mock }
    func handleWebhook(payload: Data, signature: String) async throws -> WebhookHandlingResult { return WebhookHandlingResult.mock }
    func validateWebhookSignature(payload: Data, signature: String, secret: String) -> Bool { return true }
    func getPaymentAnalytics(period: RevenuePeriod) async throws -> PaymentAnalytics { return PaymentAnalytics.mock }
    func getFailedPayments(period: RevenuePeriod) async throws -> [FailedPayment] { return [] }
    func getChargebacks(period: RevenuePeriod) async throws -> [Chargeback] { return [] }
    func exportBillingData(period: RevenuePeriod, format: ExportFormat) async throws -> Data { return Data() }
    func tokenizePaymentMethod(cardDetails: CardDetails) async throws -> String { return "tok_mock" }
    func validatePCICompliance() async throws -> PCIComplianceStatus { return PCIComplianceStatus.mock }
    func auditPaymentActivity(period: RevenuePeriod) async throws -> [PaymentAuditEntry] { return [] }
    func generateComplianceReport(period: RevenuePeriod) async throws -> ComplianceReport { return ComplianceReport.mock }
    func updateBillingConfiguration(config: BillingConfiguration) async throws {}
    func getBillingConfiguration() async throws -> BillingConfiguration { return BillingConfiguration.default }
    func setDelegate(_ delegate: BillingServiceDelegate) {}
    func removeDelegate(_ delegate: BillingServiceDelegate) {}
}
#endif