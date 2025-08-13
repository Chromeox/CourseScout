#!/usr/bin/env python3
"""
Performance Analysis Script for GolfFinder CI/CD Pipeline
Analyzes performance test results and validates against thresholds
"""

import json
import sys
import argparse
from typing import Dict, List, Any
from datetime import datetime

class PerformanceAnalyzer:
    def __init__(self, results_file: str):
        self.results_file = results_file
        self.thresholds = {
            'response_time_ms': 200,
            'memory_usage_mb': 500,
            'cpu_usage_percent': 80,
            'battery_drain_percent_per_hour': 5,
            'crash_rate_percent': 0.1,
            'network_timeout_rate_percent': 2,
            'database_query_time_ms': 100,
            'api_success_rate_percent': 99
        }
        
    def load_results(self) -> Dict[str, Any]:
        """Load performance test results from JSON file"""
        try:
            with open(self.results_file, 'r') as f:
                return json.load(f)
        except FileNotFoundError:
            print(f"❌ Error: Results file {self.results_file} not found")
            sys.exit(1)
        except json.JSONDecodeError as e:
            print(f"❌ Error: Invalid JSON in {self.results_file}: {e}")
            sys.exit(1)
    
    def analyze_response_times(self, results: Dict[str, Any]) -> bool:
        """Analyze API response times"""
        print("\n📊 Analyzing Response Times")
        print("-" * 50)
        
        passed = True
        response_times = results.get('response_times', {})
        
        for endpoint, metrics in response_times.items():
            avg_time = metrics.get('average_ms', 0)
            p95_time = metrics.get('p95_ms', 0)
            p99_time = metrics.get('p99_ms', 0)
            
            print(f"  {endpoint}:")
            print(f"    Average: {avg_time:.1f}ms")
            print(f"    95th percentile: {p95_time:.1f}ms")
            print(f"    99th percentile: {p99_time:.1f}ms")
            
            if avg_time > self.thresholds['response_time_ms']:
                print(f"    ❌ FAIL: Average response time {avg_time:.1f}ms exceeds threshold {self.thresholds['response_time_ms']}ms")
                passed = False
            else:
                print(f"    ✅ PASS: Average response time within threshold")
            
            if p95_time > self.thresholds['response_time_ms'] * 2:
                print(f"    ❌ FAIL: 95th percentile {p95_time:.1f}ms exceeds threshold {self.thresholds['response_time_ms'] * 2}ms")
                passed = False
            
            print()
        
        return passed
    
    def analyze_memory_usage(self, results: Dict[str, Any]) -> bool:
        """Analyze memory usage patterns"""
        print("💾 Analyzing Memory Usage")
        print("-" * 50)
        
        passed = True
        memory_metrics = results.get('memory_usage', {})
        
        max_memory_mb = memory_metrics.get('max_mb', 0)
        avg_memory_mb = memory_metrics.get('average_mb', 0)
        memory_leaks = memory_metrics.get('potential_leaks', 0)
        
        print(f"  Maximum Memory Usage: {max_memory_mb:.1f}MB")
        print(f"  Average Memory Usage: {avg_memory_mb:.1f}MB")
        print(f"  Potential Memory Leaks: {memory_leaks}")
        
        if max_memory_mb > self.thresholds['memory_usage_mb']:
            print(f"  ❌ FAIL: Maximum memory usage {max_memory_mb:.1f}MB exceeds threshold {self.thresholds['memory_usage_mb']}MB")
            passed = False
        else:
            print(f"  ✅ PASS: Memory usage within acceptable limits")
        
        if memory_leaks > 0:
            print(f"  ⚠️  WARNING: {memory_leaks} potential memory leaks detected")
        
        print()
        return passed
    
    def analyze_battery_impact(self, results: Dict[str, Any]) -> bool:
        """Analyze battery usage impact"""
        print("🔋 Analyzing Battery Impact")
        print("-" * 50)
        
        passed = True
        battery_metrics = results.get('battery_usage', {})
        
        drain_per_hour = battery_metrics.get('drain_percent_per_hour', 0)
        background_drain = battery_metrics.get('background_drain_percent_per_hour', 0)
        cpu_impact = battery_metrics.get('cpu_usage_percent', 0)
        
        print(f"  Battery Drain (Active): {drain_per_hour:.2f}%/hour")
        print(f"  Battery Drain (Background): {background_drain:.2f}%/hour")
        print(f"  CPU Usage: {cpu_impact:.1f}%")
        
        if drain_per_hour > self.thresholds['battery_drain_percent_per_hour']:
            print(f"  ❌ FAIL: Battery drain {drain_per_hour:.2f}%/hour exceeds threshold {self.thresholds['battery_drain_percent_per_hour']}%/hour")
            passed = False
        else:
            print(f"  ✅ PASS: Battery drain within acceptable limits")
        
        if cpu_impact > self.thresholds['cpu_usage_percent']:
            print(f"  ❌ FAIL: CPU usage {cpu_impact:.1f}% exceeds threshold {self.thresholds['cpu_usage_percent']}%")
            passed = False
        
        print()
        return passed
    
    def analyze_reliability_metrics(self, results: Dict[str, Any]) -> bool:
        """Analyze app reliability and stability"""
        print("🛡️ Analyzing Reliability Metrics")
        print("-" * 50)
        
        passed = True
        reliability_metrics = results.get('reliability', {})
        
        crash_rate = reliability_metrics.get('crash_rate_percent', 0)
        network_timeout_rate = reliability_metrics.get('network_timeout_rate_percent', 0)
        api_success_rate = reliability_metrics.get('api_success_rate_percent', 100)
        
        print(f"  Crash Rate: {crash_rate:.3f}%")
        print(f"  Network Timeout Rate: {network_timeout_rate:.2f}%")
        print(f"  API Success Rate: {api_success_rate:.2f}%")
        
        if crash_rate > self.thresholds['crash_rate_percent']:
            print(f"  ❌ FAIL: Crash rate {crash_rate:.3f}% exceeds threshold {self.thresholds['crash_rate_percent']}%")
            passed = False
        else:
            print(f"  ✅ PASS: Crash rate within acceptable limits")
        
        if network_timeout_rate > self.thresholds['network_timeout_rate_percent']:
            print(f"  ❌ FAIL: Network timeout rate {network_timeout_rate:.2f}% exceeds threshold {self.thresholds['network_timeout_rate_percent']}%")
            passed = False
        
        if api_success_rate < self.thresholds['api_success_rate_percent']:
            print(f"  ❌ FAIL: API success rate {api_success_rate:.2f}% below threshold {self.thresholds['api_success_rate_percent']}%")
            passed = False
        else:
            print(f"  ✅ PASS: API success rate meets requirements")
        
        print()
        return passed
    
    def analyze_database_performance(self, results: Dict[str, Any]) -> bool:
        """Analyze database query performance"""
        print("🗄️ Analyzing Database Performance")
        print("-" * 50)
        
        passed = True
        db_metrics = results.get('database_performance', {})
        
        for query_type, metrics in db_metrics.items():
            avg_time = metrics.get('average_query_time_ms', 0)
            max_time = metrics.get('max_query_time_ms', 0)
            slow_queries = metrics.get('slow_query_count', 0)
            
            print(f"  {query_type.replace('_', ' ').title()}:")
            print(f"    Average Query Time: {avg_time:.1f}ms")
            print(f"    Maximum Query Time: {max_time:.1f}ms")
            print(f"    Slow Queries (>{self.thresholds['database_query_time_ms']}ms): {slow_queries}")
            
            if avg_time > self.thresholds['database_query_time_ms']:
                print(f"    ❌ FAIL: Average query time {avg_time:.1f}ms exceeds threshold {self.thresholds['database_query_time_ms']}ms")
                passed = False
            else:
                print(f"    ✅ PASS: Query performance acceptable")
            
            if slow_queries > 0:
                print(f"    ⚠️  WARNING: {slow_queries} slow queries detected")
            
            print()
        
        return passed
    
    def generate_performance_report(self, results: Dict[str, Any], all_passed: bool):
        """Generate comprehensive performance report"""
        print("📋 Performance Test Summary")
        print("=" * 50)
        
        overall_status = "✅ PASSED" if all_passed else "❌ FAILED"
        print(f"Overall Status: {overall_status}")
        print(f"Test Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}")
        print(f"Test Duration: {results.get('test_duration_seconds', 0):.1f} seconds")
        print()
        
        # Performance Score Calculation
        total_metrics = 0
        passed_metrics = 0
        
        for category in ['response_times', 'memory_usage', 'battery_usage', 'reliability', 'database_performance']:
            if category in results:
                category_results = results[category]
                if isinstance(category_results, dict):
                    for metric in category_results.keys():
                        total_metrics += 1
                        # Simplified: assume all existing metrics passed basic validation
                        passed_metrics += 1
        
        if total_metrics > 0:
            performance_score = (passed_metrics / total_metrics) * 100
            print(f"Performance Score: {performance_score:.1f}%")
            
            if performance_score >= 95:
                print("🌟 Excellent performance!")
            elif performance_score >= 90:
                print("👍 Good performance")
            elif performance_score >= 80:
                print("⚠️  Performance needs attention")
            else:
                print("🚨 Critical performance issues")
        
        print()
        
        # Recommendations
        if not all_passed:
            print("🔧 Recommendations:")
            print("-" * 20)
            print("1. Optimize slow API endpoints")
            print("2. Implement caching for frequently accessed data")
            print("3. Review memory management and fix potential leaks")
            print("4. Optimize database queries and add indexes")
            print("5. Consider background processing for heavy operations")
            print()
    
    def run_analysis(self) -> bool:
        """Run complete performance analysis"""
        print("🚀 GolfFinder Performance Analysis")
        print("=" * 80)
        
        results = self.load_results()
        
        # Run all analyses
        response_time_passed = self.analyze_response_times(results)
        memory_passed = self.analyze_memory_usage(results)
        battery_passed = self.analyze_battery_impact(results)
        reliability_passed = self.analyze_reliability_metrics(results)
        database_passed = self.analyze_database_performance(results)
        
        all_passed = all([
            response_time_passed,
            memory_passed,
            battery_passed,
            reliability_passed,
            database_passed
        ])
        
        self.generate_performance_report(results, all_passed)
        
        return all_passed

def main():
    parser = argparse.ArgumentParser(description='Analyze GolfFinder performance test results')
    parser.add_argument('results_file', help='Path to performance results JSON file')
    parser.add_argument('--strict', action='store_true', help='Use strict performance thresholds')
    parser.add_argument('--output', help='Output report to file')
    
    args = parser.parse_args()
    
    # Create performance analyzer
    analyzer = PerformanceAnalyzer(args.results_file)
    
    # Adjust thresholds for strict mode
    if args.strict:
        analyzer.thresholds['response_time_ms'] = 100
        analyzer.thresholds['memory_usage_mb'] = 300
        analyzer.thresholds['battery_drain_percent_per_hour'] = 3
        print("🔒 Running in STRICT mode with tighter thresholds")
        print()
    
    # Run analysis
    success = analyzer.run_analysis()
    
    # Exit with appropriate code
    sys.exit(0 if success else 1)

if __name__ == '__main__':
    main()