#!/usr/bin/env python3
"""
Summary Report Generator for GolfFinder Testing Pipeline
Creates comprehensive HTML and JSON reports from test results
"""

import json
import os
import argparse
import glob
from datetime import datetime
from typing import Dict, List, Any, Optional

def load_test_results(results_directory: str) -> Dict[str, Any]:
    """Load all test results from directory"""
    results = {
        'unit_tests': {},
        'integration_tests': {},
        'performance_tests': {},
        'security_tests': {},
        'quality_gates': {},
        'coverage_data': {},
        'metadata': {
            'generation_time': datetime.now().isoformat(),
            'results_directory': results_directory
        }
    }
    
    # Load individual test result files
    result_files = {
        'unit_coverage.json': 'unit_tests',
        'integration_results.json': 'integration_tests', 
        'performance_analysis.json': 'performance_tests',
        'security_scan.json': 'security_tests',
        'quality_gate_report.json': 'quality_gates',
        'comprehensive_validation_report.json': 'comprehensive'
    }
    
    for filename, key in result_files.items():
        filepath = os.path.join(results_directory, filename)
        if os.path.exists(filepath):
            try:
                with open(filepath, 'r') as f:
                    results[key] = json.load(f)
            except Exception as e:
                print(f"Warning: Could not load {filename}: {e}")
                results[key] = {'error': str(e)}
    
    return results

def calculate_summary_metrics(results: Dict[str, Any]) -> Dict[str, Any]:
    """Calculate summary metrics from all test results"""
    summary = {
        'overall_status': 'UNKNOWN',
        'total_tests': 0,
        'total_passed': 0,
        'total_failed': 0,
        'overall_coverage': 0.0,
        'quality_score': 0.0,
        'test_plan_breakdown': {},
        'critical_issues': [],
        'recommendations': []
    }
    
    # Extract metrics from comprehensive report if available
    if 'comprehensive' in results and results['comprehensive']:
        comp = results['comprehensive']
        summary['overall_status'] = 'PASSED' if comp.get('overall_success', False) else 'FAILED'
        summary['total_tests'] = comp.get('total_tests', 0)
        summary['total_passed'] = comp.get('total_passed', 0)
        summary['total_failed'] = comp.get('total_failed', 0)
        summary['overall_coverage'] = comp.get('overall_coverage', 0.0)
        summary['quality_score'] = comp.get('overall_quality_score', 0.0)
        
        # Test plan breakdown
        for test_result in comp.get('test_plan_results', []):
            summary['test_plan_breakdown'][test_result['test_plan']] = {
                'success': test_result['success'],
                'quality_score': test_result['quality_score'],
                'execution_time': test_result['execution_time_seconds'],
                'coverage': test_result['coverage_percentage']
            }
        
        summary['recommendations'] = comp.get('recommendations', [])
    
    # Add critical issues from quality gates
    if 'quality_gates' in results and results['quality_gates']:
        qg = results['quality_gates']
        if 'detailed_results' in qg and 'critical_failures' in qg['detailed_results']:
            summary['critical_issues'] = qg['detailed_results']['critical_failures']
    
    return summary

def generate_html_report(results: Dict[str, Any], summary: Dict[str, Any]) -> str:
    """Generate comprehensive HTML report"""
    
    status_emoji = "✅" if summary['overall_status'] == 'PASSED' else "❌"
    status_color = "#28a745" if summary['overall_status'] == 'PASSED' else "#dc3545"
    
    html = f"""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Golf Finder - Comprehensive Test Report</title>
    <style>
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: 20px;
            background-color: #f8f9fa;
        }}
        .container {{
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            overflow: hidden;
        }}
        .header {{
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 2rem;
            text-align: center;
        }}
        .header h1 {{
            margin: 0;
            font-size: 2.5rem;
        }}
        .subtitle {{
            margin: 0.5rem 0 0 0;
            opacity: 0.9;
            font-size: 1.1rem;
        }}
        .status-badge {{
            display: inline-block;
            padding: 0.5rem 1rem;
            background: {status_color};
            color: white;
            border-radius: 25px;
            font-weight: bold;
            margin: 1rem 0;
        }}
        .metrics-grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 1rem;
            padding: 2rem;
        }}
        .metric-card {{
            background: #f8f9fa;
            padding: 1.5rem;
            border-radius: 8px;
            border-left: 4px solid #007bff;
            text-align: center;
        }}
        .metric-value {{
            font-size: 2rem;
            font-weight: bold;
            color: #333;
        }}
        .metric-label {{
            color: #666;
            margin-top: 0.5rem;
        }}
        .section {{
            padding: 2rem;
            border-bottom: 1px solid #eee;
        }}
        .section:last-child {{
            border-bottom: none;
        }}
        .section h2 {{
            margin-top: 0;
            color: #333;
        }}
        .test-plan-grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 1rem;
            margin-top: 1rem;
        }}
        .test-plan-card {{
            background: #f8f9fa;
            padding: 1rem;
            border-radius: 8px;
            border: 1px solid #dee2e6;
        }}
        .test-plan-header {{
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 1rem;
        }}
        .test-plan-name {{
            font-weight: bold;
            font-size: 1.1rem;
        }}
        .test-plan-status {{
            padding: 0.25rem 0.5rem;
            border-radius: 15px;
            font-size: 0.8rem;
            font-weight: bold;
        }}
        .status-passed {{
            background: #d4edda;
            color: #155724;
        }}
        .status-failed {{
            background: #f8d7da;
            color: #721c24;
        }}
        .progress-bar {{
            width: 100%;
            height: 20px;
            background: #e9ecef;
            border-radius: 10px;
            overflow: hidden;
            margin: 0.5rem 0;
        }}
        .progress-fill {{
            height: 100%;
            background: linear-gradient(90deg, #28a745, #20c997);
            transition: width 0.3s ease;
        }}
        .issues-list {{
            background: #fff3cd;
            border: 1px solid #ffeaa7;
            border-radius: 8px;
            padding: 1rem;
            margin-top: 1rem;
        }}
        .issue-item {{
            margin: 0.5rem 0;
            padding: 0.5rem;
            background: white;
            border-radius: 4px;
            border-left: 3px solid #f39c12;
        }}
        .recommendations {{
            background: #d1ecf1;
            border: 1px solid #bee5eb;
            border-radius: 8px;
            padding: 1rem;
            margin-top: 1rem;
        }}
        .rec-item {{
            margin: 0.5rem 0;
            padding: 0.5rem;
            background: white;
            border-radius: 4px;
            border-left: 3px solid #17a2b8;
        }}
        .timestamp {{
            color: #666;
            font-size: 0.9rem;
            text-align: center;
            padding: 1rem;
            background: #f8f9fa;
        }}
        @media (max-width: 768px) {{
            .metrics-grid {{
                grid-template-columns: 1fr;
            }}
            .test-plan-grid {{
                grid-template-columns: 1fr;
            }}
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🏌️ Golf Finder SwiftUI</h1>
            <p class="subtitle">Comprehensive Testing Report</p>
            <div class="status-badge">{status_emoji} {summary['overall_status']}</div>
        </div>
        
        <div class="metrics-grid">
            <div class="metric-card">
                <div class="metric-value">{summary['quality_score']:.1f}</div>
                <div class="metric-label">Quality Score</div>
            </div>
            <div class="metric-card">
                <div class="metric-value">{summary['overall_coverage']:.1f}%</div>
                <div class="metric-label">Test Coverage</div>
            </div>
            <div class="metric-card">
                <div class="metric-value">{summary['total_tests']}</div>
                <div class="metric-label">Total Tests</div>
            </div>
            <div class="metric-card">
                <div class="metric-value">{summary['total_passed']}</div>
                <div class="metric-label">Tests Passed</div>
            </div>
        </div>
"""
    
    # Test Plan Results Section
    if summary['test_plan_breakdown']:
        html += """
        <div class="section">
            <h2>📋 Test Plan Results</h2>
            <div class="test-plan-grid">
"""
        
        for plan_name, plan_data in summary['test_plan_breakdown'].items():
            status_class = "status-passed" if plan_data['success'] else "status-failed"
            status_text = "✅ PASSED" if plan_data['success'] else "❌ FAILED"
            coverage_width = min(100, plan_data['coverage'])
            
            html += f"""
                <div class="test-plan-card">
                    <div class="test-plan-header">
                        <div class="test-plan-name">{plan_name}</div>
                        <div class="test-plan-status {status_class}">{status_text}</div>
                    </div>
                    <div>
                        <strong>Quality Score:</strong> {plan_data['quality_score']:.1f}/100
                    </div>
                    <div>
                        <strong>Coverage:</strong> {plan_data['coverage']:.1f}%
                        <div class="progress-bar">
                            <div class="progress-fill" style="width: {coverage_width}%"></div>
                        </div>
                    </div>
                    <div>
                        <strong>Execution Time:</strong> {plan_data['execution_time']:.1f}s
                    </div>
                </div>
"""
        
        html += """
            </div>
        </div>
"""
    
    # Critical Issues Section
    if summary['critical_issues']:
        html += """
        <div class="section">
            <h2>🚨 Critical Issues</h2>
            <div class="issues-list">
"""
        
        for issue in summary['critical_issues']:
            html += f"""
                <div class="issue-item">
                    <strong>{issue.get('check', 'Unknown Check')}:</strong> {issue.get('message', 'No message available')}
                </div>
"""
        
        html += """
            </div>
        </div>
"""
    
    # Recommendations Section
    if summary['recommendations']:
        html += """
        <div class="section">
            <h2>💡 Recommendations</h2>
            <div class="recommendations">
"""
        
        for rec in summary['recommendations']:
            html += f"""
                <div class="rec-item">{rec}</div>
"""
        
        html += """
            </div>
        </div>
"""
    
    # Raw Data Section (collapsible)
    html += f"""
        <div class="section">
            <h2>📊 Detailed Results</h2>
            <details>
                <summary>View Raw Data (JSON)</summary>
                <pre style="background: #f8f9fa; padding: 1rem; border-radius: 4px; overflow-x: auto;">
{json.dumps(results, indent=2)}
                </pre>
            </details>
        </div>
        
        <div class="timestamp">
            Generated on {datetime.now().strftime('%Y-%m-%d at %H:%M:%S UTC')}
        </div>
    </div>
</body>
</html>
"""
    
    return html

def main():
    parser = argparse.ArgumentParser(description='Generate comprehensive test summary report')
    parser.add_argument('--input', required=True, help='Directory containing test results')
    parser.add_argument('--output', required=True, help='Output path for HTML report')
    parser.add_argument('--json-output', help='Optional JSON output path')
    
    args = parser.parse_args()
    
    # Load test results
    print(f"Loading test results from {args.input}...")
    results = load_test_results(args.input)
    
    # Calculate summary metrics
    print("Calculating summary metrics...")
    summary = calculate_summary_metrics(results)
    
    # Generate HTML report
    print(f"Generating HTML report...")
    html_content = generate_html_report(results, summary)
    
    # Write HTML report
    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    with open(args.output, 'w') as f:
        f.write(html_content)
    
    print(f"✅ HTML report generated: {args.output}")
    
    # Generate JSON report if requested
    if args.json_output:
        json_report = {
            'summary': summary,
            'detailed_results': results
        }
        
        os.makedirs(os.path.dirname(args.json_output), exist_ok=True)
        with open(args.json_output, 'w') as f:
            json.dump(json_report, f, indent=2)
        
        print(f"✅ JSON report generated: {args.json_output}")
    
    # Print summary to console
    print("\n" + "="*60)
    print("📋 SUMMARY REPORT")
    print("="*60)
    print(f"Overall Status: {'✅' if summary['overall_status'] == 'PASSED' else '❌'} {summary['overall_status']}")
    print(f"Quality Score: {summary['quality_score']:.1f}/100")
    print(f"Test Coverage: {summary['overall_coverage']:.1f}%")
    print(f"Total Tests: {summary['total_tests']}")
    print(f"Tests Passed: {summary['total_passed']}")
    print(f"Tests Failed: {summary['total_failed']}")
    
    if summary['critical_issues']:
        print(f"\n🚨 Critical Issues: {len(summary['critical_issues'])}")
        for issue in summary['critical_issues'][:3]:  # Show first 3
            print(f"  • {issue.get('check', 'Unknown')}: {issue.get('message', 'No message')}")
        if len(summary['critical_issues']) > 3:
            print(f"  ... and {len(summary['critical_issues']) - 3} more")
    
    if summary['recommendations']:
        print(f"\n💡 Top Recommendations:")
        for rec in summary['recommendations'][:3]:  # Show first 3
            print(f"  • {rec}")
        if len(summary['recommendations']) > 3:
            print(f"  ... and {len(summary['recommendations']) - 3} more")
    
    print("="*60)
    
    # Exit with appropriate code
    exit_code = 0 if summary['overall_status'] == 'PASSED' else 1
    exit(exit_code)

if __name__ == '__main__':
    main()