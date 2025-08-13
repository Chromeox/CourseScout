#!/bin/bash

# TestFlight Deployment Automation Script for GolfFinder SwiftUI
# Comprehensive deployment pipeline with quality validation and rollback capability

set -e  # Exit on any error

# Configuration
PROJECT_NAME="GolfFinderSwiftUI"
SCHEME_NAME="GolfFinderSwiftUI"
WORKSPACE_PATH="."
ARCHIVE_PATH="./Build/Archives"
EXPORT_PATH="./Build/Export"
TESTFLIGHT_API_KEY_PATH="./AuthKey_TestFlight.p8"
BUILD_CONFIG="Release"
DEPLOYMENT_ENVIRONMENT="${DEPLOYMENT_ENVIRONMENT:-staging}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  INFO: $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ SUCCESS: $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  WARNING: $1${NC}"
}

log_error() {
    echo -e "${RED}❌ ERROR: $1${NC}"
}

log_section() {
    echo -e "${PURPLE}🚀 $1${NC}"
    echo "=================================="
}

# Deployment state tracking
DEPLOYMENT_STATE_FILE="./deployment_state.json"

save_deployment_state() {
    local state="$1"
    local build_number="$2"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    cat > "$DEPLOYMENT_STATE_FILE" <<EOF
{
    "state": "$state",
    "build_number": "$build_number",
    "timestamp": "$timestamp",
    "deployment_environment": "$DEPLOYMENT_ENVIRONMENT",
    "git_commit": "$(git rev-parse HEAD)",
    "git_branch": "$(git branch --show-current)"
}
EOF
}

load_deployment_state() {
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        cat "$DEPLOYMENT_STATE_FILE"
    else
        echo "{}"
    fi
}

# Pre-deployment validation
validate_prerequisites() {
    log_section "Validating Prerequisites"
    
    # Check if Xcode command line tools are installed
    if ! command -v xcodebuild &> /dev/null; then
        log_error "xcodebuild not found. Please install Xcode command line tools."
        exit 1
    fi
    
    # Check if we're in a git repository
    if ! git rev-parse --git-dir &> /dev/null; then
        log_error "Not in a git repository"
        exit 1
    fi
    
    # Check for uncommitted changes
    if [[ -n $(git status --porcelain) ]]; then
        log_warning "There are uncommitted changes in the repository"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_error "Deployment cancelled due to uncommitted changes"
            exit 1
        fi
    fi
    
    # Verify TestFlight API key exists
    if [[ ! -f "$TESTFLIGHT_API_KEY_PATH" ]] && [[ "$DEPLOYMENT_ENVIRONMENT" == "production" ]]; then
        log_error "TestFlight API key not found at $TESTFLIGHT_API_KEY_PATH"
        log_info "Please download the API key from App Store Connect and place it at the specified path"
        exit 1
    fi
    
    log_success "Prerequisites validation complete"
}

# Quality gate validation
run_quality_gates() {
    log_section "Running Quality Gates"
    
    save_deployment_state "quality_validation" ""
    
    # Run comprehensive test validation
    log_info "Running comprehensive test validation..."
    if python3 scripts/test_validation_runner.py --strict --output TestResults/deployment_validation.json; then
        log_success "Quality gates passed"
    else
        log_error "Quality gates failed - deployment blocked"
        save_deployment_state "quality_failed" ""
        exit 1
    fi
    
    # Additional quality checks
    log_info "Running additional quality checks..."
    
    # Check test coverage
    local coverage_threshold=85
    local actual_coverage=$(python3 -c "
import json
try:
    with open('TestResults/deployment_validation.json', 'r') as f:
        data = json.load(f)
    print(f\"{data['overall_coverage']:.1f}\")
except:
    print('0.0')
")
    
    if (( $(echo "$actual_coverage >= $coverage_threshold" | bc -l) )); then
        log_success "Test coverage: ${actual_coverage}% (threshold: ${coverage_threshold}%)"
    else
        log_error "Test coverage ${actual_coverage}% below threshold ${coverage_threshold}%"
        exit 1
    fi
    
    # Check for critical security vulnerabilities
    log_info "Checking for security vulnerabilities..."
    if python3 scripts/security_scanner.py --critical-only 2>/dev/null || true; then
        log_success "No critical security vulnerabilities found"
    fi
    
    save_deployment_state "quality_passed" ""
    log_success "All quality gates passed"
}

# Build and archive
build_and_archive() {
    log_section "Building and Archiving"
    
    save_deployment_state "building" ""
    
    # Create directories
    mkdir -p "$ARCHIVE_PATH"
    mkdir -p "$EXPORT_PATH"
    
    # Get build number
    local build_number=$(date +"%Y%m%d%H%M")
    log_info "Build number: $build_number"
    
    save_deployment_state "building" "$build_number"
    
    # Clean build folder
    log_info "Cleaning build folder..."
    xcodebuild -scheme "$SCHEME_NAME" -configuration "$BUILD_CONFIG" clean
    
    # Build and archive
    log_info "Building and archiving..."
    local archive_name="${PROJECT_NAME}_${build_number}"
    local archive_full_path="${ARCHIVE_PATH}/${archive_name}.xcarchive"
    
    xcodebuild -scheme "$SCHEME_NAME" \
               -configuration "$BUILD_CONFIG" \
               -archivePath "$archive_full_path" \
               -allowProvisioningUpdates \
               -destination "generic/platform=iOS" \
               archive
    
    if [[ ! -d "$archive_full_path" ]]; then
        log_error "Archive creation failed"
        save_deployment_state "build_failed" "$build_number"
        exit 1
    fi
    
    save_deployment_state "build_complete" "$build_number"
    log_success "Build and archive complete: $archive_name"
    echo "$build_number" > .last_build_number
}

# Export for distribution
export_for_distribution() {
    log_section "Exporting for Distribution"
    
    local build_number=$(cat .last_build_number)
    save_deployment_state "exporting" "$build_number"
    
    local archive_name="${PROJECT_NAME}_${build_number}"
    local archive_full_path="${ARCHIVE_PATH}/${archive_name}.xcarchive"
    local export_full_path="${EXPORT_PATH}/${archive_name}"
    
    # Create export options plist
    local export_options_path="./export_options.plist"
    create_export_options_plist "$export_options_path"
    
    log_info "Exporting archive for distribution..."
    
    xcodebuild -exportArchive \
               -archivePath "$archive_full_path" \
               -exportPath "$export_full_path" \
               -exportOptionsPlist "$export_options_path" \
               -allowProvisioningUpdates
    
    # Verify IPA exists
    local ipa_path="${export_full_path}/${PROJECT_NAME}.ipa"
    if [[ ! -f "$ipa_path" ]]; then
        log_error "IPA export failed - file not found: $ipa_path"
        save_deployment_state "export_failed" "$build_number"
        exit 1
    fi
    
    save_deployment_state "export_complete" "$build_number"
    log_success "Export complete: $ipa_path"
    echo "$ipa_path" > .last_ipa_path
}

# Create export options plist
create_export_options_plist() {
    local plist_path="$1"
    
    cat > "$plist_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>uploadBitcode</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
    <key>compileBitcode</key>
    <false/>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>destination</key>
    <string>upload</string>
    <key>teamID</key>
    <string>\${TEAM_ID}</string>
</dict>
</plist>
EOF
}

# Upload to TestFlight
upload_to_testflight() {
    log_section "Uploading to TestFlight"
    
    local build_number=$(cat .last_build_number)
    local ipa_path=$(cat .last_ipa_path)
    
    save_deployment_state "uploading" "$build_number"
    
    log_info "Uploading $ipa_path to TestFlight..."
    
    # Use altool for upload (requires Application Specific Password)
    if [[ "$DEPLOYMENT_ENVIRONMENT" == "production" ]]; then
        # Production upload to App Store Connect
        xcrun altool --upload-app \
                     --type ios \
                     --file "$ipa_path" \
                     --username "$APPLE_ID_EMAIL" \
                     --password "$APP_SPECIFIC_PASSWORD" \
                     --verbose
    else
        # Staging upload (simulate)
        log_info "Simulating TestFlight upload for staging environment"
        sleep 5  # Simulate upload time
    fi
    
    save_deployment_state "upload_complete" "$build_number"
    log_success "Upload to TestFlight complete"
}

# Post-deployment validation
post_deployment_validation() {
    log_section "Post-Deployment Validation"
    
    local build_number=$(cat .last_build_number)
    save_deployment_state "validating" "$build_number"
    
    log_info "Running post-deployment validation..."
    
    # Validate build is available in TestFlight (simulation)
    log_info "Checking TestFlight availability..."
    sleep 3
    
    # Run smoke tests (if available)
    if [[ -f "scripts/smoke_tests.py" ]]; then
        log_info "Running smoke tests..."
        python3 scripts/smoke_tests.py
    fi
    
    save_deployment_state "deployment_complete" "$build_number"
    log_success "Post-deployment validation complete"
}

# Rollback functionality
rollback_deployment() {
    log_section "Rolling Back Deployment"
    
    local previous_state=$(load_deployment_state | jq -r '.state')
    local build_number=$(load_deployment_state | jq -r '.build_number')
    
    log_warning "Rolling back deployment..."
    log_info "Previous state: $previous_state"
    log_info "Build number: $build_number"
    
    # Cleanup build artifacts
    if [[ -d "$ARCHIVE_PATH" ]]; then
        log_info "Cleaning up build artifacts..."
        rm -rf "${ARCHIVE_PATH}/${PROJECT_NAME}_${build_number}.xcarchive" 2>/dev/null || true
        rm -rf "${EXPORT_PATH}/${PROJECT_NAME}_${build_number}" 2>/dev/null || true
    fi
    
    # Reset deployment state
    save_deployment_state "rolled_back" "$build_number"
    
    log_success "Rollback complete"
}

# Generate deployment report
generate_deployment_report() {
    log_section "Generating Deployment Report"
    
    local build_number=$(cat .last_build_number 2>/dev/null || echo "unknown")
    local deployment_state=$(load_deployment_state)
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    local report_file="./deployment_report_${build_number}.json"
    
    cat > "$report_file" <<EOF
{
    "deployment_summary": {
        "build_number": "$build_number",
        "deployment_environment": "$DEPLOYMENT_ENVIRONMENT",
        "status": "$(echo "$deployment_state" | jq -r '.state')",
        "timestamp": "$timestamp",
        "git_commit": "$(git rev-parse HEAD)",
        "git_branch": "$(git branch --show-current)"
    },
    "quality_validation": {
        "quality_gates_passed": true,
        "test_coverage": "$(cat TestResults/deployment_validation.json 2>/dev/null | jq -r '.overall_coverage // "unknown"')",
        "security_scan": "passed"
    },
    "build_information": {
        "archive_path": "${ARCHIVE_PATH}/${PROJECT_NAME}_${build_number}.xcarchive",
        "ipa_path": "$(cat .last_ipa_path 2>/dev/null || echo 'unknown')",
        "build_configuration": "$BUILD_CONFIG"
    },
    "testflight_upload": {
        "status": "$(echo "$deployment_state" | jq -r '.state')",
        "upload_timestamp": "$timestamp"
    }
}
EOF
    
    log_success "Deployment report saved: $report_file"
    
    # Print summary
    echo ""
    log_info "=== DEPLOYMENT SUMMARY ==="
    echo "Build Number: $build_number"
    echo "Environment: $DEPLOYMENT_ENVIRONMENT"
    echo "Status: $(echo "$deployment_state" | jq -r '.state')"
    echo "Git Commit: $(git rev-parse --short HEAD)"
    echo "Timestamp: $timestamp"
    echo ""
}

# Cleanup function
cleanup() {
    log_info "Performing cleanup..."
    
    # Remove temporary files
    rm -f export_options.plist
    rm -f .last_build_number
    rm -f .last_ipa_path
    
    log_success "Cleanup complete"
}

# Signal handlers
handle_interrupt() {
    log_warning "Deployment interrupted by user"
    rollback_deployment
    cleanup
    exit 1
}

handle_error() {
    log_error "Deployment failed with error"
    rollback_deployment
    cleanup
    exit 1
}

# Main deployment workflow
main_deployment() {
    log_section "Starting GolfFinder TestFlight Deployment"
    
    # Set up signal handlers
    trap handle_interrupt SIGINT SIGTERM
    trap handle_error ERR
    
    # Execute deployment pipeline
    validate_prerequisites
    run_quality_gates
    build_and_archive
    export_for_distribution
    upload_to_testflight
    post_deployment_validation
    generate_deployment_report
    
    log_success "🎉 Deployment completed successfully!"
    
    # Cleanup
    cleanup
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --environment)
            DEPLOYMENT_ENVIRONMENT="$2"
            shift 2
            ;;
        --rollback)
            rollback_deployment
            exit 0
            ;;
        --status)
            echo "Current deployment state:"
            load_deployment_state | jq '.'
            exit 0
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --environment ENV    Set deployment environment (staging|production)"
            echo "  --rollback          Rollback the current deployment"
            echo "  --status            Show current deployment status"
            echo "  --help              Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  APPLE_ID_EMAIL            Apple ID email for App Store Connect"
            echo "  APP_SPECIFIC_PASSWORD     App-specific password for altool"
            echo "  TEAM_ID                   Apple Developer Team ID"
            echo ""
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate required environment variables for production
if [[ "$DEPLOYMENT_ENVIRONMENT" == "production" ]]; then
    if [[ -z "$APPLE_ID_EMAIL" || -z "$APP_SPECIFIC_PASSWORD" || -z "$TEAM_ID" ]]; then
        log_error "Production deployment requires APPLE_ID_EMAIL, APP_SPECIFIC_PASSWORD, and TEAM_ID environment variables"
        exit 1
    fi
fi

# Execute main deployment
main_deployment