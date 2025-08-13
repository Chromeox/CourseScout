# 🛠️ CourseScout API Gateway Technical Implementation Guide
## Production Deployment & Developer Onboarding Manual

---

# 🚀 Quick Start Guide

## Prerequisites Checklist

### **Infrastructure Requirements**:
- [x] Production Appwrite instance configured
- [x] Stripe account with live API keys
- [x] Domain names registered (api.coursescout.io, developers.coursescout.io)
- [x] SSL certificates configured
- [x] CDN setup (Cloudflare/AWS CloudFront)

### **Development Environment**:
```bash
# Verify implementation is complete
cd /Users/chromefang.exe/GolfFinderSwiftUI
ls -la GolfFinderApp/API/

# Expected structure:
# ├── Endpoints/        (4 files - CourseData, Analytics, Predictive, RealTime)
# ├── Gateway/          (4 files - Service, Auth, RateLimit, Usage)
# └── Portal/           (8 files - Developer portal backend)
```

---

# 🔧 Production Deployment

## Step 1: Environment Configuration

### **Create Production Configuration**:
```swift
// GolfFinderApp/Utils/Configuration.swift
extension Configuration {
    static var production: Configuration {
        return Configuration(
            appwriteEndpoint: "https://cloud.appwrite.io/v1",
            appwriteProjectId: "coursescout-prod-2024",
            apiGatewayBaseURL: "https://api.coursescout.io",
            stripePublishableKey: "pk_live_...",
            environment: .production
        )
    }
}
```

### **Environment Variables Setup**:
```bash
# Production secrets (add to deployment environment)
export COURSESCOUT_ENV=production
export APPWRITE_ENDPOINT=https://cloud.appwrite.io/v1
export APPWRITE_PROJECT_ID=coursescout-prod-2024
export APPWRITE_API_KEY=your_production_api_key
export STRIPE_SECRET_KEY=sk_live_your_stripe_secret
export STRIPE_WEBHOOK_SECRET=whsec_your_webhook_secret
export JWT_SECRET=your_jwt_secret_key
export API_GATEWAY_DOMAIN=api.coursescout.io
```

## Step 2: Database Setup

### **Appwrite Collections Configuration**:
```javascript
// Run in Appwrite Console
const collections = [
    {
        name: "golf_courses",
        permissions: ["read", "write"],
        attributes: [
            { key: "name", type: "string", required: true },
            { key: "latitude", type: "double", required: true },
            { key: "longitude", type: "double", required: true },
            { key: "rating", type: "double", default: 0 },
            { key: "green_fee_weekday", type: "double", default: 0 },
            // ... additional attributes
        ]
    },
    {
        name: "api_keys",
        permissions: ["read", "write"],
        attributes: [
            { key: "key_hash", type: "string", required: true },
            { key: "developer_id", type: "string", required: true },
            { key: "tier", type: "string", required: true },
            { key: "rate_limit", type: "integer", required: true },
            { key: "created_at", type: "datetime", required: true }
        ]
    },
    // ... additional collections
];
```

## Step 3: Deployment Scripts

### **Create Deployment Script**:
```bash
#!/bin/bash
# deploy-production.sh

echo "🚀 Deploying CourseScout API Gateway to Production..."

# Build the application
echo "📦 Building application..."
swift build -c release

# Run tests
echo "🧪 Running tests..."
swift test

if [ $? -ne 0 ]; then
    echo "❌ Tests failed. Deployment aborted."
    exit 1
fi

# Deploy to production server
echo "🚀 Deploying to production..."
rsync -avz --delete .build/release/ production-server:/opt/coursescout-api/

# Restart services
echo "♻️ Restarting services..."
ssh production-server "sudo systemctl restart coursescout-api"
ssh production-server "sudo systemctl restart nginx"

# Health check
echo "🏥 Running health checks..."
curl -f https://api.coursescout.io/health || {
    echo "❌ Health check failed"
    exit 1
}

echo "✅ Deployment completed successfully!"
```

---

# 🔐 Security Configuration

## API Key Management

### **Generate Master API Keys**:
```swift
// One-time setup script
import Foundation
import CryptoKit

func generateMasterKeys() {
    let masterAPIKey = generateSecureAPIKey(length: 64)
    let webhookSecret = generateSecureSecret(length: 32)
    let jwtSecret = generateSecureSecret(length: 32)
    
    print("Master API Key: \(masterAPIKey)")
    print("Webhook Secret: \(webhookSecret)")
    print("JWT Secret: \(jwtSecret)")
    
    // Store these in your secure environment configuration
}

func generateSecureAPIKey(length: Int) -> String {
    let characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    return String((0..<length).map{ _ in characters.randomElement()! })
}
```

### **Rate Limiting Configuration**:
```swift
// Configure rate limits for each tier
let rateLimits: [APITier: RateLimit] = [
    .free: RateLimit(requestsPerDay: 1000, burstLimit: 10),
    .premium: RateLimit(requestsPerDay: 10000, burstLimit: 50),
    .business: RateLimit(requestsPerDay: 100000, burstLimit: 200),
    .enterprise: RateLimit(requestsPerDay: -1, burstLimit: 1000) // Unlimited
]
```

---

# 🌐 DNS & Domain Setup

## Domain Configuration

### **DNS Records**:
```dns
# A Records
api.coursescout.io.        IN A    YOUR_SERVER_IP
developers.coursescout.io. IN A    YOUR_SERVER_IP
docs.coursescout.io.       IN A    YOUR_SERVER_IP

# CNAME Records
www.developers.coursescout.io. IN CNAME developers.coursescout.io.

# MX Records (for developer support emails)
developers.coursescout.io. IN MX 10 mail.coursescout.io.
```

### **SSL Certificate Setup**:
```bash
# Using Certbot for Let's Encrypt
sudo certbot --nginx -d api.coursescout.io
sudo certbot --nginx -d developers.coursescout.io
sudo certbot --nginx -d docs.coursescout.io

# Verify SSL configuration
curl -I https://api.coursescout.io
```

---

# 📚 Developer Portal Setup

## Self-Service Registration

### **Registration Flow**:
```swift
// Developer registration endpoint
func registerDeveloper(request: DeveloperRegistration) async throws -> DeveloperAccount {
    // 1. Validate email and create account
    let account = try await createDeveloperAccount(request)
    
    // 2. Generate initial API key (Free tier)
    let apiKey = try await generateAPIKey(
        developerId: account.id,
        tier: .free,
        name: "Default Key"
    )
    
    // 3. Send welcome email with documentation
    try await sendWelcomeEmail(account: account, apiKey: apiKey)
    
    // 4. Create Stripe customer for future billing
    try await createStripeCustomer(account: account)
    
    return account
}
```

### **API Key Generation**:
```swift
// Secure API key generation
func generateAPIKey(developerId: String, tier: APITier, name: String) async throws -> APIKey {
    let keyString = "cs_" + generateSecureAPIKey(length: 32)
    let keyHash = SHA256.hash(data: keyString.data(using: .utf8)!)
    
    let apiKey = APIKey(
        id: UUID(),
        keyHash: keyHash.hexString,
        developerId: developerId,
        name: name,
        tier: tier,
        rateLimit: tier.defaultRateLimit,
        isActive: true,
        createdAt: Date()
    )
    
    try await saveAPIKey(apiKey)
    return apiKey
}
```

---

# 📖 Documentation Generation

## OpenAPI Specification

### **Auto-Generate API Docs**:
```swift
// Generate OpenAPI spec from endpoints
func generateOpenAPISpec() -> OpenAPIDocument {
    let document = OpenAPIDocument(
        info: OpenAPIInfo(
            title: "CourseScout API",
            version: "1.0.0",
            description: "Comprehensive golf course and booking API"
        ),
        servers: [
            OpenAPIServer(url: "https://api.coursescout.io/v1")
        ]
    )
    
    // Add endpoints
    document.addPath("/courses", operations: [
        .get: courseSearchOperation,
        .post: courseCreateOperation
    ])
    
    // Add authentication schemes
    document.addSecurityScheme("ApiKeyAuth", scheme: .apiKey(
        name: "x-api-key",
        location: .header
    ))
    
    return document
}
```

### **Interactive Documentation Setup**:
```html
<!-- docs.coursescout.io/index.html -->
<!DOCTYPE html>
<html>
<head>
    <title>CourseScout API Documentation</title>
    <link rel="stylesheet" type="text/css" href="https://unpkg.com/swagger-ui-dist@3.25.0/swagger-ui.css" />
</head>
<body>
    <div id="swagger-ui"></div>
    <script src="https://unpkg.com/swagger-ui-dist@3.25.0/swagger-ui-bundle.js"></script>
    <script>
        SwaggerUIBundle({
            url: 'https://api.coursescout.io/openapi.json',
            dom_id: '#swagger-ui',
            presets: [SwaggerUIBundle.presets.apis, SwaggerUIBundle.presets.standalone]
        });
    </script>
</body>
</html>
```

---

# 💳 Billing Integration

## Stripe Configuration

### **Product & Price Setup**:
```javascript
// Run in Stripe Dashboard or API
const products = [
    {
        name: "CourseScout API - Premium",
        description: "10,000 requests/day with analytics",
        price: 9900, // $99.00 in cents
        interval: "month"
    },
    {
        name: "CourseScout API - Business", 
        description: "100,000 requests/day with real-time booking",
        price: 99900, // $999.00 in cents
        interval: "month"
    }
];
```

### **Webhook Handling**:
```swift
// Handle Stripe webhooks for billing events
func handleStripeWebhook(_ event: StripeEvent) async throws {
    switch event.type {
    case "customer.subscription.created":
        try await handleSubscriptionCreated(event)
    case "customer.subscription.updated":
        try await handleSubscriptionUpdated(event)
    case "customer.subscription.deleted":
        try await handleSubscriptionCancelled(event)
    case "invoice.payment_succeeded":
        try await handlePaymentSucceeded(event)
    case "invoice.payment_failed":
        try await handlePaymentFailed(event)
    default:
        print("Unhandled webhook event: \(event.type)")
    }
}
```

---

# 📊 Analytics & Monitoring

## Performance Monitoring

### **Metrics Collection**:
```swift
// Real-time API metrics
struct APIMetrics {
    var totalRequests: Int = 0
    var successfulRequests: Int = 0
    var failedRequests: Int = 0
    var averageResponseTime: TimeInterval = 0
    var peakRPS: Int = 0 // Requests per second
    var errorRate: Double { failedRequests / totalRequests }
}

// Usage tracking per API key
struct UsageMetrics {
    let apiKey: String
    let tier: APITier
    var requestsToday: Int
    var requestsThisMonth: Int
    var lastRequestTime: Date
    var overageCharges: Decimal
}
```

### **Health Check Endpoint**:
```swift
// /health endpoint for monitoring
func healthCheck() async -> HealthStatus {
    let appwriteStatus = await checkAppwriteConnection()
    let stripeStatus = await checkStripeConnection()
    let redisStatus = await checkRedisConnection()
    
    let overallHealth = appwriteStatus && stripeStatus && redisStatus
    
    return HealthStatus(
        status: overallHealth ? .healthy : .degraded,
        services: [
            "appwrite": appwriteStatus ? .up : .down,
            "stripe": stripeStatus ? .up : .down,
            "redis": redisStatus ? .up : .down
        ],
        timestamp: Date()
    )
}
```

---

# 📱 SDK Generation & Distribution

## Multi-Language SDK Creation

### **Swift SDK**:
```swift
// CourseScoutAPI.swift - Generated SDK
public class CourseScoutAPI {
    private let apiKey: String
    private let baseURL = "https://api.coursescout.io/v1"
    
    public init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    public func searchCourses(
        location: CLLocation? = nil,
        radius: Double? = nil,
        priceRange: PriceRange? = nil
    ) async throws -> [GolfCourse] {
        let endpoint = "/courses/search"
        let parameters = buildSearchParameters(
            location: location,
            radius: radius,
            priceRange: priceRange
        )
        
        return try await performRequest(endpoint: endpoint, parameters: parameters)
    }
}
```

### **JavaScript SDK**:
```javascript
// coursescout-api.js - NPM Package
class CourseScoutAPI {
    constructor(apiKey) {
        this.apiKey = apiKey;
        this.baseURL = 'https://api.coursescout.io/v1';
    }
    
    async searchCourses({ location, radius, priceRange } = {}) {
        const endpoint = '/courses/search';
        const params = new URLSearchParams();
        
        if (location) {
            params.append('lat', location.latitude);
            params.append('lng', location.longitude);
        }
        if (radius) params.append('radius', radius);
        if (priceRange) {
            params.append('min_price', priceRange.min);
            params.append('max_price', priceRange.max);
        }
        
        return await this.makeRequest(endpoint, { params });
    }
}

module.exports = CourseScoutAPI;
```

### **Python SDK**:
```python
# coursescout_api.py - PyPI Package
import requests
from typing import Optional, List, Dict

class CourseScoutAPI:
    def __init__(self, api_key: str):
        self.api_key = api_key
        self.base_url = "https://api.coursescout.io/v1"
        self.session = requests.Session()
        self.session.headers.update({
            'x-api-key': api_key,
            'Content-Type': 'application/json'
        })
    
    def search_courses(
        self, 
        location: Optional[Dict] = None,
        radius: Optional[float] = None,
        price_range: Optional[Dict] = None
    ) -> List[Dict]:
        endpoint = "/courses/search"
        params = {}
        
        if location:
            params.update({
                'lat': location['latitude'],
                'lng': location['longitude']
            })
        if radius:
            params['radius'] = radius
        if price_range:
            params.update({
                'min_price': price_range['min'],
                'max_price': price_range['max']
            })
        
        response = self.session.get(f"{self.base_url}{endpoint}", params=params)
        response.raise_for_status()
        return response.json()['courses']
```

---

# 🚦 Testing & Quality Assurance

## Automated Testing Suite

### **API Integration Tests**:
```swift
// APIGatewayIntegrationTests.swift
class APIGatewayIntegrationTests: XCTestCase {
    var apiGateway: APIGatewayService!
    
    override func setUp() async throws {
        apiGateway = APIGatewayService(
            appwriteClient: TestAppwriteClient(),
            environment: .test
        )
    }
    
    func testCourseSearchWithValidAPIKey() async throws {
        let request = APIGatewayRequest(
            method: .GET,
            path: "/courses/search",
            headers: ["x-api-key": "test_api_key_valid"],
            body: nil
        )
        
        let response = try await apiGateway.processRequest(request)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertNotNil(response.data)
    }
    
    func testRateLimitingEnforcement() async throws {
        let apiKey = "test_api_key_limited"
        
        // Make requests up to the limit
        for _ in 0..<10 {
            let response = try await makeAPIRequest(apiKey: apiKey)
            XCTAssertEqual(response.statusCode, 200)
        }
        
        // Next request should be rate limited
        let limitedResponse = try await makeAPIRequest(apiKey: apiKey)
        XCTAssertEqual(limitedResponse.statusCode, 429)
    }
}
```

### **Load Testing**:
```bash
#!/bin/bash
# load-test.sh - Using Apache Bench

echo "🚀 Starting CourseScout API Load Test..."

# Test course search endpoint
ab -n 1000 -c 10 -H "x-api-key: test_load_key" \
   https://api.coursescout.io/v1/courses/search

# Test course details endpoint  
ab -n 500 -c 5 -H "x-api-key: test_load_key" \
   https://api.coursescout.io/v1/courses/course_123

# Test analytics endpoint (Premium tier)
ab -n 200 -c 2 -H "x-api-key: test_premium_key" \
   https://api.coursescout.io/v1/analytics/courses/course_123

echo "✅ Load testing completed!"
```

---

# 📈 Launch Checklist

## Pre-Launch Validation

### **Technical Checklist**:
- [ ] Production infrastructure deployed and tested
- [ ] All API endpoints responding correctly
- [ ] Rate limiting working for all tiers
- [ ] SSL certificates configured and valid
- [ ] Database migrations completed
- [ ] Monitoring and alerting configured
- [ ] Backup systems operational
- [ ] Load testing completed successfully

### **Business Checklist**:
- [ ] Stripe billing integration tested
- [ ] Developer portal registration flow working
- [ ] API documentation published and accessible
- [ ] SDK packages published to package managers
- [ ] Customer support channels established
- [ ] Legal terms of service and privacy policy published
- [ ] Pricing tiers configured correctly
- [ ] Marketing website launched

### **Security Checklist**:
- [ ] API key authentication working
- [ ] Rate limiting preventing abuse
- [ ] Input validation on all endpoints
- [ ] SQL injection protection verified
- [ ] HTTPS enforced on all endpoints
- [ ] Security headers configured
- [ ] Vulnerability scanning completed
- [ ] Data encryption at rest and in transit

---

# 🎯 Success Metrics & Monitoring

## Key Performance Indicators

### **Technical KPIs**:
```swift
// Monitoring dashboard metrics
struct TechnicalKPIs {
    let averageResponseTime: TimeInterval    // Target: <200ms
    let uptime: Double                       // Target: 99.9%
    let errorRate: Double                    // Target: <0.1%
    let requestsPerSecond: Int              // Target: 100+ RPS
    let cacheHitRatio: Double               // Target: >80%
}
```

### **Business KPIs**:
```swift
// Business metrics tracking
struct BusinessKPIs {
    let monthlyRecurringRevenue: Decimal     // Primary metric
    let customerAcquisitionCost: Decimal     // Target: <$50
    let customerLifetimeValue: Decimal       // Target: >$1000
    let churnRate: Double                    // Target: <5% monthly
    let apiCallGrowthRate: Double           // Target: 20% MoM
}
```

### **Developer KPIs**:
```swift
// Developer ecosystem health
struct DeveloperKPIs {
    let activeAPIKeys: Int                   // Total active developers
    let newRegistrations: Int                // Monthly new signups
    let documentationPageViews: Int          // Developer engagement
    let sdkDownloads: Int                    // SDK adoption
    let supportTicketResolutionTime: TimeInterval // Target: <24 hours
}
```

---

# 🔧 Troubleshooting Guide

## Common Issues & Solutions

### **API Performance Issues**:
```swift
// Debug slow API responses
func debugSlowResponses() async {
    let slowEndpoints = await getEndpointsWithHighLatency()
    
    for endpoint in slowEndpoints {
        // Check database query performance
        let dbMetrics = await getDatabaseMetrics(for: endpoint)
        print("DB Query Time: \(dbMetrics.averageQueryTime)ms")
        
        // Check external API calls
        let externalMetrics = await getExternalAPIMetrics(for: endpoint)
        print("External API Time: \(externalMetrics.averageResponseTime)ms")
        
        // Check caching efficiency
        let cacheMetrics = await getCacheMetrics(for: endpoint)
        print("Cache Hit Rate: \(cacheMetrics.hitRate)%")
    }
}
```

### **Rate Limiting Issues**:
```swift
// Debug rate limiting problems
func debugRateLimiting(apiKey: String) async {
    let rateLimitState = await getRateLimitState(apiKey: apiKey)
    print("Current Usage: \(rateLimitState.requestsUsed)/\(rateLimitState.limit)")
    print("Reset Time: \(rateLimitState.resetTime)")
    
    if rateLimitState.isLimited {
        print("Rate limited until: \(rateLimitState.resetTime)")
        // Suggest upgrade to higher tier
        let suggestedTier = suggestTierUpgrade(currentUsage: rateLimitState.requestsUsed)
        print("Suggested upgrade to: \(suggestedTier)")
    }
}
```

### **Billing Issues**:
```swift
// Debug billing and subscription problems
func debugBillingIssues(customerId: String) async {
    let subscription = await getActiveSubscription(customerId: customerId)
    let usage = await getCurrentUsage(customerId: customerId)
    let invoices = await getRecentInvoices(customerId: customerId)
    
    print("Subscription Status: \(subscription?.status ?? "None")")
    print("Current Usage: \(usage.requestsThisMonth)")
    print("Overage Charges: $\(usage.overageCharges)")
    
    for invoice in invoices {
        print("Invoice \(invoice.id): \(invoice.status) - $\(invoice.amount)")
    }
}
```

---

# 📞 Support & Maintenance

## Ongoing Maintenance Tasks

### **Daily Operations**:
- Monitor API performance and error rates
- Check system health and uptime
- Review customer support tickets
- Monitor billing and payment issues

### **Weekly Operations**:
- Review usage analytics and growth metrics
- Update API documentation for new features
- Security patch updates
- Database maintenance and optimization

### **Monthly Operations**:
- Performance optimization review
- Security audit and penetration testing
- Business metrics analysis and reporting
- Customer feedback analysis and feature planning

---

This technical implementation guide provides comprehensive instructions for deploying and maintaining the CourseScout API Gateway in production. Follow these steps carefully to ensure a successful launch and ongoing operation of your API platform.

**Document Version**: 1.0  
**Last Updated**: December 2024  
**Maintained by**: CourseScout Technical Team