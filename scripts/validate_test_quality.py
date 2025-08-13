#!/usr/bin/env python3
"""
Test Quality Validation Script for GolfFinder CI/CD Pipeline
Validates test coverage, performance, and security compliance
"""

import json
import sys
import os
import argparse
import subprocess
from typing import Dict, List, Any, Tuple
from datetime import datetime
import xml.etree.ElementTree as ET

class TestQualityValidator:
    def __init__(self):
        self.quality_gates = {
            'unit_test_coverage': 90.0,
            'integration_test_coverage': 85.0,
            'security_test_coverage': 95.0,
            'performance_test_success_rate': 100.0,
            'max_test_duration_minutes': 45.0,
            'max_flaky_test_percentage': 2.0,
            'min_assertion_count_per_test': 1,
            'max_test_method_length_lines': 50,
            'required_test_categories': ['unit', 'integration', 'performance', 'security', 'ui']
        }
        
        self.validation_results = {
            'passed': [],
            'failed': [],
            'warnings': []
        }
    
    def validate_test_coverage(self, coverage_file: str) -> bool:
        """Validate test coverage meets quality gates"""
        print("📊 Validating Test Coverage")
        print("-" * 50)
        
        try:
            with open(coverage_file, 'r') as f:
                coverage_data = json.load(f)
            
            overall_coverage = coverage_data.get('coverage_percentage', 0)
            file_coverage = coverage_data.get('file_coverage', {})
            
            print(f"Overall Coverage: {overall_coverage:.2f}%")
            
            # Check overall coverage threshold
            if overall_coverage >= self.quality_gates['unit_test_coverage']:
                self.validation_results['passed'].append(f"Unit test coverage: {overall_coverage:.2f}%")
                print(f"✅ Overall coverage meets threshold ({self.quality_gates['unit_test_coverage']}%)")
            else:
                self.validation_results['failed'].append(f"Unit test coverage {overall_coverage:.2f}% below threshold {self.quality_gates['unit_test_coverage']}%")
                print(f"❌ Overall coverage below threshold")
            
            # Check critical file coverage
            critical_files = [
                'APIGatewayService.swift',
                'GolfCourseService.swift', 
                'RevenueService.swift',
                'SecurityService.swift',
                'ServiceContainer.swift'
            ]
            
            low_coverage_files = []
            for file_name, coverage in file_coverage.items():
                if any(critical in file_name for critical in critical_files):
                    if coverage < 95.0:
                        low_coverage_files.append((file_name, coverage))
                        print(f"⚠️  Critical file {file_name}: {coverage:.1f}% coverage")
                    else:
                        print(f"✅ Critical file {file_name}: {coverage:.1f}% coverage")
            
            if low_coverage_files:
                self.validation_results['warnings'].extend([
                    f"Low coverage in critical file {name}: {cov:.1f}%" 
                    for name, cov in low_coverage_files
                ])
            
            return overall_coverage >= self.quality_gates['unit_test_coverage']
            
        except FileNotFoundError:
            self.validation_results['failed'].append(f"Coverage file not found: {coverage_file}")
            print(f"❌ Coverage file not found: {coverage_file}")
            return False
        except Exception as e:
            self.validation_results['failed'].append(f"Error reading coverage data: {str(e)}")
            print(f"❌ Error reading coverage data: {str(e)}")
            return False
    
    def validate_test_performance(self, performance_file: str) -> bool:
        """Validate test execution performance"""
        print("\n⚡ Validating Test Performance")
        print("-" * 50)
        
        try:
            with open(performance_file, 'r') as f:
                perf_data = json.load(f)
            
            total_duration = perf_data.get('total_test_duration_minutes', 0)
            test_results = perf_data.get('test_results', [])
            
            print(f"Total Test Duration: {total_duration:.2f} minutes")
            
            # Check total duration
            if total_duration <= self.quality_gates['max_test_duration_minutes']:
                self.validation_results['passed'].append(f"Test duration: {total_duration:.2f} minutes")
                print(f"✅ Test duration within limit ({self.quality_gates['max_test_duration_minutes']} minutes)")
            else:
                self.validation_results['failed'].append(f"Test duration {total_duration:.2f}m exceeds limit {self.quality_gates['max_test_duration_minutes']}m")
                print(f"❌ Test duration exceeds limit")
            
            # Analyze individual test performance
            slow_tests = []
            failed_tests = []
            flaky_tests = []
            
            for test in test_results:
                test_name = test.get('name', 'Unknown')
                duration = test.get('duration_seconds', 0)
                status = test.get('status', 'unknown')
                
                if duration > 30:  # Tests taking longer than 30 seconds
                    slow_tests.append((test_name, duration))
                
                if status == 'failed':
                    failed_tests.append(test_name)
                
                if test.get('is_flaky', False):
                    flaky_tests.append(test_name)
            
            # Report slow tests
            if slow_tests:
                print(f"\n⚠️  Slow Tests ({len(slow_tests)} tests > 30s):")
                for name, duration in slow_tests[:5]:  # Show top 5
                    print(f"    {name}: {duration:.1f}s")
                self.validation_results['warnings'].append(f"{len(slow_tests)} slow tests detected")
            
            # Check flaky tests
            flaky_percentage = (len(flaky_tests) / len(test_results)) * 100 if test_results else 0
            if flaky_percentage <= self.quality_gates['max_flaky_test_percentage']:
                self.validation_results['passed'].append(f"Flaky test rate: {flaky_percentage:.1f}%")
                print(f"✅ Flaky test rate acceptable: {flaky_percentage:.1f}%")
            else:
                self.validation_results['failed'].append(f"Flaky test rate {flaky_percentage:.1f}% exceeds limit {self.quality_gates['max_flaky_test_percentage']}%")
                print(f"❌ Too many flaky tests: {flaky_percentage:.1f}%")
            
            # Check performance test success rate
            perf_tests = [t for t in test_results if 'performance' in t.get('name', '').lower()]
            if perf_tests:
                perf_success_rate = (sum(1 for t in perf_tests if t.get('status') == 'passed') / len(perf_tests)) * 100
                if perf_success_rate >= self.quality_gates['performance_test_success_rate']:
                    self.validation_results['passed'].append(f"Performance test success rate: {perf_success_rate:.1f}%")
                    print(f"✅ Performance tests success rate: {perf_success_rate:.1f}%")
                else:
                    self.validation_results['failed'].append(f"Performance test success rate {perf_success_rate:.1f}% below requirement")
                    print(f"❌ Performance test success rate too low: {perf_success_rate:.1f}%")
            
            return (total_duration <= self.quality_gates['max_test_duration_minutes'] and 
                   flaky_percentage <= self.quality_gates['max_flaky_test_percentage'])
            
        except FileNotFoundError:
            self.validation_results['failed'].append(f"Performance file not found: {performance_file}")
            print(f"❌ Performance file not found: {performance_file}")
            return False
        except Exception as e:
            self.validation_results['failed'].append(f"Error reading performance data: {str(e)}")
            print(f"❌ Error reading performance data: {str(e)}")
            return False
    
    def validate_security_compliance(self, security_file: str) -> bool:
        """Validate security test compliance"""
        print("\n🔒 Validating Security Compliance")
        print("-" * 50)
        
        try:
            with open(security_file, 'r') as f:
                security_data = json.load(f)
            
            vulnerability_scan = security_data.get('vulnerability_scan', {})
            security_tests = security_data.get('security_tests', {})
            
            # Check vulnerability scan results
            critical_vulnerabilities = vulnerability_scan.get('critical', 0)
            high_vulnerabilities = vulnerability_scan.get('high', 0)
            medium_vulnerabilities = vulnerability_scan.get('medium', 0)
            
            print(f"Critical Vulnerabilities: {critical_vulnerabilities}")
            print(f"High Vulnerabilities: {high_vulnerabilities}")
            print(f"Medium Vulnerabilities: {medium_vulnerabilities}")
            
            if critical_vulnerabilities == 0:
                self.validation_results['passed'].append("No critical vulnerabilities found")
                print("✅ No critical vulnerabilities")
            else:
                self.validation_results['failed'].append(f"{critical_vulnerabilities} critical vulnerabilities found")
                print(f"❌ Critical vulnerabilities found: {critical_vulnerabilities}")
            
            if high_vulnerabilities == 0:
                self.validation_results['passed'].append("No high-severity vulnerabilities found")
                print("✅ No high-severity vulnerabilities")
            elif high_vulnerabilities <= 2:
                self.validation_results['warnings'].append(f"{high_vulnerabilities} high-severity vulnerabilities found")
                print(f"⚠️  High-severity vulnerabilities: {high_vulnerabilities}")
            else:
                self.validation_results['failed'].append(f"Too many high-severity vulnerabilities: {high_vulnerabilities}")
                print(f"❌ Too many high-severity vulnerabilities: {high_vulnerabilities}")
            
            # Check security test coverage
            security_test_coverage = security_tests.get('coverage_percentage', 0)
            if security_test_coverage >= self.quality_gates['security_test_coverage']:
                self.validation_results['passed'].append(f"Security test coverage: {security_test_coverage:.1f}%")
                print(f"✅ Security test coverage: {security_test_coverage:.1f}%")
            else:
                self.validation_results['failed'].append(f"Security test coverage {security_test_coverage:.1f}% below threshold")
                print(f"❌ Security test coverage too low: {security_test_coverage:.1f}%")
            
            # Check specific security test categories
            required_security_tests = [
                'sql_injection_protection',
                'xss_protection', 
                'authentication_bypass_prevention',
                'input_validation',
                'encryption_at_rest',
                'gdpr_compliance'
            ]
            
            missing_security_tests = []
            for test_category in required_security_tests:
                if test_category not in security_tests.get('test_categories', []):
                    missing_security_tests.append(test_category)
            
            if not missing_security_tests:
                self.validation_results['passed'].append("All required security tests present")
                print("✅ All required security test categories covered")
            else:
                self.validation_results['failed'].append(f"Missing security tests: {', '.join(missing_security_tests)}")
                print(f"❌ Missing security test categories: {', '.join(missing_security_tests)}")
            
            return (critical_vulnerabilities == 0 and 
                   high_vulnerabilities <= 2 and
                   security_test_coverage >= self.quality_gates['security_test_coverage'] and
                   not missing_security_tests)
            
        except FileNotFoundError:
            self.validation_results['failed'].append(f"Security file not found: {security_file}")
            print(f"❌ Security file not found: {security_file}")
            return False
        except Exception as e:
            self.validation_results['failed'].append(f"Error reading security data: {str(e)}")
            print(f"❌ Error reading security data: {str(e)}")
            return False
    
    def validate_test_structure(self, test_directory: str) -> bool:
        """Validate test project structure and organization"""
        print("\n🏗️ Validating Test Structure")
        print("-" * 50)
        
        required_directories = [
            'Unit/Services',
            'Integration/APIGateway', 
            'Performance/Load',
            'Security/Authentication',
            'UI/Golf'
        ]
        
        missing_directories = []
        for req_dir in required_directories:
            full_path = os.path.join(test_directory, req_dir)
            if not os.path.exists(full_path):
                missing_directories.append(req_dir)
        
        if not missing_directories:
            self.validation_results['passed'].append("All required test directories present")
            print("✅ Test directory structure is complete")
        else:
            self.validation_results['failed'].append(f"Missing test directories: {', '.join(missing_directories)}")
            print(f"❌ Missing test directories: {', '.join(missing_directories)}")
        
        # Check for test files
        test_file_count = 0
        for root, dirs, files in os.walk(test_directory):
            test_file_count += len([f for f in files if f.endswith('Tests.swift')])
        
        print(f"Total test files found: {test_file_count}")
        
        if test_file_count >= 20:  # Minimum expected test files
            self.validation_results['passed'].append(f"Adequate test file count: {test_file_count}")
            print(f"✅ Adequate number of test files: {test_file_count}")
        else:
            self.validation_results['warnings'].append(f"Low test file count: {test_file_count}")
            print(f"⚠️  Consider adding more test files: {test_file_count}")
        
        return not missing_directories
    
    def validate_test_plans(self, test_plans_directory: str) -> bool:
        """Validate Xcode test plan configuration"""
        print("\n📋 Validating Test Plans")
        print("-" * 50)
        
        required_test_plans = [
            'UnitTestPlan.xctestplan',
            'IntegrationTestPlan.xctestplan',
            'PerformanceTestPlan.xctestplan',
            'SecurityTestPlan.xctestplan'
        ]
        
        missing_plans = []
        for plan in required_test_plans:
            plan_path = os.path.join(test_plans_directory, plan)
            if not os.path.exists(plan_path):
                missing_plans.append(plan)
            else:
                # Validate test plan content
                try:
                    with open(plan_path, 'r') as f:
                        plan_content = json.load(f)
                    
                    if 'testTargets' in plan_content:
                        print(f"✅ {plan}: Valid configuration")
                    else:
                        self.validation_results['warnings'].append(f"Test plan {plan} missing testTargets")
                        print(f"⚠️  {plan}: Missing testTargets configuration")
                        
                except Exception as e:
                    self.validation_results['warnings'].append(f"Test plan {plan} validation error: {str(e)}")
                    print(f"⚠️  {plan}: Validation error - {str(e)}")
        
        if not missing_plans:
            self.validation_results['passed'].append("All required test plans present")
            print("✅ All required test plans are present")
        else:
            self.validation_results['failed'].append(f"Missing test plans: {', '.join(missing_plans)}")
            print(f"❌ Missing test plans: {', '.join(missing_plans)}")
        
        return not missing_plans
    
    def generate_quality_report(self) -> Dict[str, Any]:
        """Generate comprehensive test quality report"""
        print("\n📋 Test Quality Report")
        print("=" * 50)
        
        total_checks = (len(self.validation_results['passed']) + 
                       len(self.validation_results['failed']) + 
                       len(self.validation_results['warnings']))
        
        passed_count = len(self.validation_results['passed'])
        failed_count = len(self.validation_results['failed'])
        warning_count = len(self.validation_results['warnings'])
        
        quality_score = (passed_count / total_checks * 100) if total_checks > 0 else 0
        
        overall_status = "PASSED" if failed_count == 0 else "FAILED"
        
        print(f"Overall Status: {'✅ ' + overall_status if failed_count == 0 else '❌ ' + overall_status}")
        print(f"Quality Score: {quality_score:.1f}%")
        print(f"Total Checks: {total_checks}")
        print(f"Passed: {passed_count}")
        print(f"Failed: {failed_count}")
        print(f"Warnings: {warning_count}")
        
        if self.validation_results['passed']:
            print(f"\n✅ Passed Checks ({passed_count}):")
            for check in self.validation_results['passed']:
                print(f"    • {check}")
        
        if self.validation_results['warnings']:
            print(f"\n⚠️  Warnings ({warning_count}):")
            for warning in self.validation_results['warnings']:
                print(f"    • {warning}")
        
        if self.validation_results['failed']:
            print(f"\n❌ Failed Checks ({failed_count}):")
            for failure in self.validation_results['failed']:
                print(f"    • {failure}")
        
        if failed_count == 0:
            if warning_count == 0:
                print(f"\n🌟 Excellent! All quality gates passed with no warnings.")
            elif warning_count <= 3:
                print(f"\n👍 Good! All critical quality gates passed. Address {warning_count} warnings when possible.")
            else:
                print(f"\n⚠️  Quality gates passed but {warning_count} warnings need attention.")
        else:
            print(f"\n🚨 Quality gates failed! Address {failed_count} critical issues before deployment.")
        
        return {
            'overall_status': overall_status,
            'quality_score': quality_score,
            'total_checks': total_checks,
            'passed': passed_count,
            'failed': failed_count,
            'warnings': warning_count,
            'details': self.validation_results,
            'timestamp': datetime.now().isoformat()
        }
    
    def run_validation(self, args) -> bool:
        """Run complete test quality validation"""
        print("🚀 GolfFinder Test Quality Validation")
        print("=" * 80)
        
        success = True
        
        # Validate test coverage
        if args.coverage_file:
            coverage_valid = self.validate_test_coverage(args.coverage_file)
            success = success and coverage_valid
        
        # Validate test performance
        if args.performance_file:
            performance_valid = self.validate_test_performance(args.performance_file)
            success = success and performance_valid
        
        # Validate security compliance
        if args.security_file:
            security_valid = self.validate_security_compliance(args.security_file)
            success = success and security_valid
        
        # Validate test structure
        if args.test_directory:
            structure_valid = self.validate_test_structure(args.test_directory)
            success = success and structure_valid
        
        # Validate test plans
        if args.test_plans_directory:
            plans_valid = self.validate_test_plans(args.test_plans_directory)
            success = success and plans_valid
        
        # Generate report
        report = self.generate_quality_report()
        
        # Save report if requested
        if args.output_file:
            with open(args.output_file, 'w') as f:
                json.dump(report, f, indent=2)
            print(f"\n📄 Report saved to: {args.output_file}")
        
        return success

def main():
    parser = argparse.ArgumentParser(description='Validate GolfFinder test quality and compliance')
    parser.add_argument('--coverage-file', help='Path to test coverage JSON file')
    parser.add_argument('--performance-file', help='Path to test performance JSON file') 
    parser.add_argument('--security-file', help='Path to security scan JSON file')
    parser.add_argument('--test-directory', help='Path to test directory')
    parser.add_argument('--test-plans-directory', help='Path to test plans directory')
    parser.add_argument('--output-file', help='Path to save quality report JSON')
    parser.add_argument('--strict', action='store_true', help='Use strict quality thresholds')
    
    args = parser.parse_args()
    
    validator = TestQualityValidator()
    
    # Adjust thresholds for strict mode
    if args.strict:
        validator.quality_gates['unit_test_coverage'] = 95.0
        validator.quality_gates['integration_test_coverage'] = 90.0
        validator.quality_gates['max_test_duration_minutes'] = 30.0
        validator.quality_gates['max_flaky_test_percentage'] = 1.0
        print("🔒 Running in STRICT mode with higher quality thresholds")
        print()
    
    # Run validation
    success = validator.run_validation(args)
    
    # Exit with appropriate code
    sys.exit(0 if success else 1)

if __name__ == '__main__':
    main()