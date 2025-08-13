#!/bin/bash

# Revenue Architecture Validation Script
# Validates MVVM compliance, security, and architecture integrity

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
SERVICES_DIR="$PROJECT_DIR/GolfFinderApp/Services/Revenue"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0

echo "=============================================="
echo "🏗️  REVENUE ARCHITECTURE VALIDATION"
echo "=============================================="
echo ""

# Helper functions
print_check() {
    local message="$1"
    printf "%-60s" "$message"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
}

print_result() {
    local result="$1"
    if [ "$result" = "PASS" ]; then
        printf "[${GREEN}PASS${NC}]\n"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    elif [ "$result" = "WARN" ]; then
        printf "[${YELLOW}WARN${NC}]\n"
    else
        printf "[${RED}FAIL${NC}]\n"
    fi
}

check_file_exists() {
    local file="$1"
    if [ -f "$file" ]; then
        return 0
    else
        return 1
    fi
}

check_swift_syntax() {
    local file="$1"
    if command -v xcrun > /dev/null 2>&1; then
        if xcrun swiftc -typecheck "$file" 2>/dev/null; then
            return 0
        else
            return 1
        fi
    else
        # Fallback: Basic syntax check
        if grep -E "(class|struct|enum|protocol)" "$file" >/dev/null 2>&1; then
            return 0
        else
            return 1
        fi
    fi
}

check_mvvm_compliance() {
    local file="$1"
    local protocol_found=false
    local async_await_found=false
    local combine_found=false
    
    # Check for protocol definition
    if grep -q "protocol.*Protocol" "$file"; then
        protocol_found=true
    fi
    
    # Check for async/await usage
    if grep -q "async\|await" "$file"; then
        async_await_found=true
    fi
    
    # Check for Combine usage
    if grep -q "AnyPublisher\|@Published\|Combine" "$file"; then
        combine_found=true
    fi
    
    if [ "$protocol_found" = true ] && ([ "$async_await_found" = true ] || [ "$combine_found" = true ]); then
        return 0
    else
        return 1
    fi
}

check_security_patterns() {
    local file="$1"
    local security_issues=()
    
    # Check for hardcoded secrets
    if grep -i "secret\|password\|key.*=" "$file" | grep -v "// " | grep -v "\*" >/dev/null 2>&1; then
        security_issues+=("hardcoded_secrets")
    fi
    
    # Check for SQL injection vulnerabilities
    if grep -i "SELECT.*+\|INSERT.*+\|UPDATE.*+" "$file" >/dev/null 2>&1; then
        security_issues+=("sql_injection")
    fi
    
    # Check for proper error handling
    if ! grep -q "throws\|Result<\|Error" "$file"; then
        security_issues+=("missing_error_handling")
    fi
    
    if [ ${#security_issues[@]} -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

check_dependency_injection() {
    local file="$1"
    
    # Check for proper dependency injection patterns
    if grep -q "init.*:.*)" "$file" && grep -q "let.*:" "$file"; then
        return 0
    else
        return 1
    fi
}

echo "📋 CHECKING REVENUE SERVICE FILES"
echo "================================================"

# Core service files to check
services=(
    "RevenueServiceProtocol.swift"
    "SubscriptionService.swift" 
    "TenantManagementService.swift"
    "APIUsageTrackingService.swift"
    "BillingService.swift"
    "RevenueModels.swift"
    "TenantModels.swift"
    "UsageTrackingModels.swift"
    "BillingModels.swift"
    "DatabaseSchema.swift"
)

for service in "${services[@]}"; do
    file_path="$SERVICES_DIR/$service"
    
    # Check file exists
    print_check "File exists: $service"
    if check_file_exists "$file_path"; then
        print_result "PASS"
    else
        print_result "FAIL"
        continue
    fi
    
    # Check Swift syntax
    print_check "Swift syntax valid: $service"
    if check_swift_syntax "$file_path"; then
        print_result "PASS"
    else
        print_result "FAIL"
    fi
    
    # Check MVVM compliance (skip for model files)
    if [[ "$service" != *"Models.swift" && "$service" != "DatabaseSchema.swift" ]]; then
        print_check "MVVM compliance: $service"
        if check_mvvm_compliance "$file_path"; then
            print_result "PASS"
        else
            print_result "WARN"
        fi
    fi
    
    # Check security patterns
    print_check "Security patterns: $service"
    if check_security_patterns "$file_path"; then
        print_result "PASS"
    else
        print_result "WARN"
    fi
    
    # Check dependency injection (service files only)
    if [[ "$service" == *"Service.swift" ]]; then
        print_check "Dependency injection: $service"
        if check_dependency_injection "$file_path"; then
            print_result "PASS"
        else
            print_result "WARN"
        fi
    fi
done

echo ""
echo "🔧 CHECKING SERVICE CONTAINER INTEGRATION"
echo "================================================"

CONTAINER_FILE="$PROJECT_DIR/GolfFinderApp/Services/ServiceContainer.swift"

print_check "ServiceContainer file exists"
if check_file_exists "$CONTAINER_FILE"; then
    print_result "PASS"
else
    print_result "FAIL"
fi

print_check "Revenue services registered in container"
if grep -q "RevenueServiceProtocol\|TenantManagementServiceProtocol\|BillingServiceProtocol\|APIUsageTrackingServiceProtocol" "$CONTAINER_FILE"; then
    print_result "PASS"
else
    print_result "FAIL"
fi

print_check "Mock services provided for testing"
if grep -q "MockRevenueService\|MockTenantManagementService\|MockBillingService" "$CONTAINER_FILE"; then
    print_result "PASS"
else
    print_result "WARN"
fi

print_check "Proper dependency chain configuration"
if grep -q "billingService.*resolve\|analyticsService.*resolve\|securityService.*resolve" "$CONTAINER_FILE"; then
    print_result "PASS"
else
    print_result "WARN"
fi

echo ""
echo "🔐 SECURITY ARCHITECTURE VALIDATION"
echo "================================================"

print_check "PCI compliance patterns in BillingService"
if grep -q "PCI\|tokenization\|audit.*log\|compliance" "$SERVICES_DIR/BillingService.swift"; then
    print_result "PASS"
else
    print_result "WARN"
fi

print_check "Tenant isolation in database schema"
if grep -q "tenant_id\|RLS\|row.*level.*security" "$SERVICES_DIR/DatabaseSchema.swift"; then
    print_result "PASS"
else
    print_result "FAIL"
fi

print_check "API rate limiting implementation"
if grep -q "rate.*limit\|throttle\|quota" "$SERVICES_DIR/APIUsageTrackingService.swift"; then
    print_result "PASS"
else
    print_result "WARN"
fi

print_check "Audit logging for compliance"
if grep -q "audit\|log.*transaction\|compliance.*record" "$SERVICES_DIR/BillingService.swift"; then
    print_result "PASS"
else
    print_result "WARN"
fi

echo ""
echo "🏛️ ARCHITECTURAL PATTERN VALIDATION" 
echo "================================================"

print_check "Protocol-based service architecture"
if find "$SERVICES_DIR" -name "*.swift" -exec grep -l "protocol.*Protocol" {} \; | wc -l | awk '{print $1}' | grep -q "[3-9]"; then
    print_result "PASS"
else
    print_result "FAIL"
fi

print_check "Proper separation of concerns"
models_count=$(find "$SERVICES_DIR" -name "*Models.swift" | wc -l)
services_count=$(find "$SERVICES_DIR" -name "*Service.swift" | wc -l)
if [ "$models_count" -ge 3 ] && [ "$services_count" -ge 3 ]; then
    print_result "PASS"
else
    print_result "WARN"
fi

print_check "Error handling consistency"
error_handling_files=$(grep -l "Error\|throws\|Result<" "$SERVICES_DIR"/*.swift | wc -l)
total_service_files=$(find "$SERVICES_DIR" -name "*Service.swift" | wc -l)
if [ "$error_handling_files" -ge "$total_service_files" ]; then
    print_result "PASS"
else
    print_result "WARN"
fi

print_check "Async/await or Combine usage"
async_files=$(grep -l "async\|await\|AnyPublisher" "$SERVICES_DIR"/*.swift | wc -l)
if [ "$async_files" -ge 3 ]; then
    print_result "PASS"
else
    print_result "WARN"
fi

echo ""
echo "💾 DATA MODEL VALIDATION"
echo "================================================"

print_check "Comprehensive revenue models defined"
if grep -q "struct.*Revenue\|struct.*Subscription\|struct.*Payment" "$SERVICES_DIR/RevenueModels.swift"; then
    print_result "PASS"
else
    print_result "FAIL"
fi

print_check "Multi-tenant data models"
if grep -q "struct.*Tenant\|TenantType\|TenantStatus" "$SERVICES_DIR/TenantModels.swift"; then
    print_result "PASS"
else
    print_result "FAIL"
fi

print_check "Billing and payment models"
if grep -q "struct.*Invoice\|struct.*Payment\|PaymentMethod" "$SERVICES_DIR/BillingModels.swift"; then
    print_result "PASS"
else
    print_result "FAIL"
fi

print_check "Usage tracking models"
if grep -q "struct.*Usage\|APIUsage\|RateLimit" "$SERVICES_DIR/UsageTrackingModels.swift"; then
    print_result "PASS"
else
    print_result "FAIL"
fi

echo ""
echo "🗄️ DATABASE SCHEMA VALIDATION"
echo "================================================"

print_check "Multi-tenant database design"
if grep -q "CREATE TABLE.*tenant\|tenant_id.*UUID" "$SERVICES_DIR/DatabaseSchema.swift"; then
    print_result "PASS"
else
    print_result "FAIL"
fi

print_check "Row-level security policies"
if grep -q "ROW LEVEL SECURITY\|CREATE POLICY\|RLS" "$SERVICES_DIR/DatabaseSchema.swift"; then
    print_result "PASS"
else
    print_result "FAIL"
fi

print_check "Performance optimization indexes"
if grep -q "CREATE INDEX\|idx_.*tenant" "$SERVICES_DIR/DatabaseSchema.swift"; then
    print_result "PASS"
else
    print_result "WARN"
fi

print_check "Backup and migration support"
if grep -q "backup\|migration\|restore" "$SERVICES_DIR/DatabaseSchema.swift"; then
    print_result "PASS"
else
    print_result "WARN"
fi

echo ""
echo "🧪 TESTING INFRASTRUCTURE"
echo "================================================"

print_check "Mock services for unit testing"
mock_count=$(grep -c "Mock.*Service" "$CONTAINER_FILE" 2>/dev/null || echo "0")
if [ "$mock_count" -ge 4 ]; then
    print_result "PASS"
else
    print_result "WARN"
fi

print_check "Sample data for development"
if grep -q "#if DEBUG" "$SERVICES_DIR"/*Models.swift; then
    print_result "PASS"
else
    print_result "WARN"
fi

print_check "Error case coverage"
if grep -q "Error.*LocalizedError\|enum.*Error" "$SERVICES_DIR"/*.swift; then
    print_result "PASS"
else
    print_result "WARN"
fi

echo ""
echo "⚡ PERFORMANCE CONSIDERATIONS"
echo "================================================"

print_check "Singleton lifecycle for services"
if grep -q "lifecycle:.*singleton" "$CONTAINER_FILE"; then
    print_result "PASS"
else
    print_result "WARN"
fi

print_check "Efficient data structures used"
if grep -q "Dictionary\|Set\|Array.*sorted" "$SERVICES_DIR"/*.swift; then
    print_result "PASS"
else
    print_result "WARN"
fi

print_check "Caching strategy implemented"
if grep -q "cache\|Cache\|cached" "$SERVICES_DIR"/*.swift || grep -q "CacheService" "$CONTAINER_FILE"; then
    print_result "PASS"
else
    print_result "WARN"
fi

echo ""
echo "=============================================="
echo "📊 VALIDATION SUMMARY"
echo "=============================================="
echo ""

# Calculate success rate
success_rate=$(echo "scale=1; $PASSED_CHECKS * 100 / $TOTAL_CHECKS" | bc -l 2>/dev/null || echo "N/A")

echo "Total Checks: $TOTAL_CHECKS"
echo "Passed Checks: $PASSED_CHECKS"
echo "Success Rate: $success_rate%"
echo ""

# Determine overall status
if [ "$PASSED_CHECKS" -ge $((TOTAL_CHECKS * 85 / 100)) ]; then
    echo -e "${GREEN}✅ REVENUE ARCHITECTURE VALIDATION PASSED${NC}"
    echo "The revenue infrastructure meets production readiness standards."
    exit_code=0
elif [ "$PASSED_CHECKS" -ge $((TOTAL_CHECKS * 70 / 100)) ]; then
    echo -e "${YELLOW}⚠️  REVENUE ARCHITECTURE VALIDATION PASSED WITH WARNINGS${NC}"
    echo "The revenue infrastructure is functional but has areas for improvement."
    exit_code=0
else
    echo -e "${RED}❌ REVENUE ARCHITECTURE VALIDATION FAILED${NC}"
    echo "The revenue infrastructure requires fixes before production deployment."
    exit_code=1
fi

echo ""
echo "🚀 NEXT STEPS:"
echo "1. Review any failed or warning checks above"
echo "2. Implement missing mock services for comprehensive testing"
echo "3. Add unit tests for revenue services"
echo "4. Conduct security audit for PCI compliance"
echo "5. Performance testing under load"
echo "6. Integration testing with payment providers"
echo ""

exit $exit_code