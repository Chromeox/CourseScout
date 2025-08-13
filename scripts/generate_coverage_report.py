#!/usr/bin/env python3
"""
Coverage Report Generator for GolfFinder SwiftUI
Generates comprehensive coverage reports from Xcode test results
"""

import json
import argparse
import os
from typing import Dict, List, Any, Optional

def parse_xcode_coverage(coverage_data: Dict[str, Any]) -> Dict[str, Any]:
    """Parse Xcode coverage JSON data into structured format"""
    
    parsed = {
        'overall_coverage': 0.0,
        'file_coverage': {},
        'target_coverage': {},
        'low_coverage_files': [],
        'uncovered_lines': [],
        'summary': {
            'total_files': 0,
            'covered_lines': 0,
            'executable_lines': 0,
            'coverage_percentage': 0.0
        }
    }
    
    if 'targets' not in coverage_data:
        return parsed
    
    total_covered = 0
    total_executable = 0
    all_files = []
    
    for target in coverage_data['targets']:
        target_name = target.get('name', 'Unknown')
        target_covered = 0
        target_executable = 0
        target_files = []
        
        for file_data in target.get('files', []):
            file_name = file_data.get('name', 'Unknown')
            line_coverage = file_data.get('lineCoverage', 0.0)
            covered_lines = file_data.get('coveredLines', 0)
            executable_lines = file_data.get('executableLines', 0)
            
            coverage_percentage = line_coverage * 100
            
            file_info = {
                'name': file_name,
                'coverage_percentage': coverage_percentage,
                'covered_lines': covered_lines,
                'executable_lines': executable_lines,
                'target': target_name
            }
            
            parsed['file_coverage'][file_name] = coverage_percentage
            all_files.append(file_info)
            target_files.append(file_info)
            
            # Track low coverage files
            if coverage_percentage < 80.0 and executable_lines > 0:
                parsed['low_coverage_files'].append(file_info)
            
            # Accumulate totals
            target_covered += covered_lines
            target_executable += executable_lines
            total_covered += covered_lines
            total_executable += executable_lines
        
        # Store target-level coverage
        if target_executable > 0:
            target_coverage_pct = (target_covered / target_executable) * 100
        else:
            target_coverage_pct = 0.0
            
        parsed['target_coverage'][target_name] = {
            'coverage_percentage': target_coverage_pct,
            'covered_lines': target_covered,
            'executable_lines': target_executable,
            'file_count': len(target_files),
            'files': target_files
        }
    
    # Calculate overall coverage
    if total_executable > 0:
        overall_coverage = (total_covered / total_executable) * 100
    else:
        overall_coverage = 0.0
    
    parsed['overall_coverage'] = overall_coverage
    parsed['summary'] = {
        'total_files': len(all_files),
        'covered_lines': total_covered,
        'executable_lines': total_executable,
        'coverage_percentage': overall_coverage
    }
    
    # Sort low coverage files by coverage percentage
    parsed['low_coverage_files'].sort(key=lambda x: x['coverage_percentage'])
    
    return parsed

def generate_html_coverage_report(coverage_data: Dict[str, Any]) -> str:
    """Generate HTML coverage report"""
    
    overall_coverage = coverage_data['overall_coverage']
    summary = coverage_data['summary']
    
    # Determine coverage status and color
    if overall_coverage >= 90:
        status = "Excellent"
        status_color = "#28a745"
    elif overall_coverage >= 80:
        status = "Good"  
        status_color = "#ffc107"
    elif overall_coverage >= 70:
        status = "Fair"
        status_color = "#fd7e14"
    else:
        status = "Poor"
        status_color = "#dc3545"
    
    html = f"""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Golf Finder - Code Coverage Report</title>
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
        }}
        .header {{
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 2rem;
            text-align: center;
            border-radius: 8px 8px 0 0;
        }}
        .header h1 {{
            margin: 0;
            font-size: 2rem;
        }}
        .coverage-overview {{
            padding: 2rem;
            text-align: center;
            border-bottom: 1px solid #eee;
        }}
        .coverage-circle {{
            width: 120px;
            height: 120px;
            border-radius: 50%;
            background: conic-gradient({status_color} {overall_coverage * 3.6}deg, #e9ecef 0deg);
            display: inline-flex;
            align-items: center;
            justify-content: center;
            margin-bottom: 1rem;
            position: relative;
        }}
        .coverage-circle::before {{
            content: '';
            width: 80px;
            height: 80px;
            border-radius: 50%;
            background: white;
            position: absolute;
        }}
        .coverage-text {{
            font-size: 1.5rem;
            font-weight: bold;
            color: {status_color};
            z-index: 1;
        }}
        .status-badge {{
            display: inline-block;
            padding: 0.5rem 1rem;
            background: {status_color};
            color: white;
            border-radius: 20px;
            font-weight: bold;
            margin-top: 1rem;
        }}
        .metrics-grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 1rem;
            padding: 2rem;
            border-bottom: 1px solid #eee;
        }}
        .metric-card {{
            text-align: center;
            padding: 1rem;
            background: #f8f9fa;
            border-radius: 8px;
        }}
        .metric-value {{
            font-size: 1.8rem;
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
        .coverage-table {{
            width: 100%;
            border-collapse: collapse;
            margin-top: 1rem;
        }}
        .coverage-table th,
        .coverage-table td {{
            padding: 0.75rem;
            text-align: left;
            border-bottom: 1px solid #dee2e6;
        }}
        .coverage-table th {{
            background: #f8f9fa;
            font-weight: bold;
        }}
        .coverage-bar {{
            width: 100px;
            height: 20px;
            background: #e9ecef;
            border-radius: 10px;
            overflow: hidden;
            display: inline-block;
        }}
        .coverage-fill {{
            height: 100%;
            border-radius: 10px;
        }}
        .coverage-high {{ background: #28a745; }}
        .coverage-medium {{ background: #ffc107; }}
        .coverage-low {{ background: #dc3545; }}
        .file-name {{
            font-family: monospace;
            font-size: 0.9rem;
        }}
        .target-section {{
            margin-bottom: 2rem;
        }}
        .target-header {{
            background: #e9ecef;
            padding: 1rem;
            border-radius: 8px;
            margin-bottom: 1rem;
        }}
        .target-name {{
            font-size: 1.2rem;
            font-weight: bold;
            color: #333;
        }}
        .target-stats {{
            color: #666;
            margin-top: 0.5rem;
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📊 Code Coverage Report</h1>
            <p>Golf Finder SwiftUI Test Coverage Analysis</p>
        </div>
        
        <div class="coverage-overview">
            <div class="coverage-circle">
                <div class="coverage-text">{overall_coverage:.1f}%</div>
            </div>
            <div class="status-badge">{status} Coverage</div>
        </div>
        
        <div class="metrics-grid">
            <div class="metric-card">
                <div class="metric-value">{summary['total_files']}</div>
                <div class="metric-label">Total Files</div>
            </div>
            <div class="metric-card">
                <div class="metric-value">{summary['covered_lines']:,}</div>
                <div class="metric-label">Covered Lines</div>
            </div>
            <div class="metric-card">
                <div class="metric-value">{summary['executable_lines']:,}</div>
                <div class="metric-label">Executable Lines</div>
            </div>
            <div class="metric-card">
                <div class="metric-value">{len(coverage_data['low_coverage_files'])}</div>
                <div class="metric-label">Files Below 80%</div>
            </div>
        </div>
"""
    
    # Target coverage breakdown
    if coverage_data['target_coverage']:
        html += """
        <div class="section">
            <h2>🎯 Target Coverage Breakdown</h2>
"""
        
        for target_name, target_data in coverage_data['target_coverage'].items():
            coverage_pct = target_data['coverage_percentage']
            coverage_class = 'coverage-high' if coverage_pct >= 80 else 'coverage-medium' if coverage_pct >= 60 else 'coverage-low'
            
            html += f"""
            <div class="target-section">
                <div class="target-header">
                    <div class="target-name">{target_name}</div>
                    <div class="target-stats">
                        {target_data['file_count']} files • 
                        {target_data['covered_lines']:,} / {target_data['executable_lines']:,} lines covered • 
                        {coverage_pct:.1f}% coverage
                    </div>
                </div>
                
                <table class="coverage-table">
                    <thead>
                        <tr>
                            <th>File</th>
                            <th>Coverage</th>
                            <th>Lines Covered</th>
                            <th>Executable Lines</th>
                        </tr>
                    </thead>
                    <tbody>
"""
            
            # Sort files by coverage percentage
            sorted_files = sorted(target_data['files'], key=lambda x: x['coverage_percentage'])
            
            for file_info in sorted_files:
                file_coverage = file_info['coverage_percentage']
                file_class = 'coverage-high' if file_coverage >= 80 else 'coverage-medium' if file_coverage >= 60 else 'coverage-low'
                
                html += f"""
                        <tr>
                            <td class="file-name">{os.path.basename(file_info['name'])}</td>
                            <td>
                                <div class="coverage-bar">
                                    <div class="coverage-fill {file_class}" style="width: {file_coverage}%"></div>
                                </div>
                                {file_coverage:.1f}%
                            </td>
                            <td>{file_info['covered_lines']:,}</td>
                            <td>{file_info['executable_lines']:,}</td>
                        </tr>
"""
            
            html += """
                    </tbody>
                </table>
            </div>
"""
        
        html += """
        </div>
"""
    
    # Low coverage files section
    if coverage_data['low_coverage_files']:
        html += f"""
        <div class="section">
            <h2>⚠️ Files Needing Attention (Below 80% Coverage)</h2>
            <table class="coverage-table">
                <thead>
                    <tr>
                        <th>File</th>
                        <th>Target</th>
                        <th>Coverage</th>
                        <th>Lines Covered</th>
                        <th>Executable Lines</th>
                    </tr>
                </thead>
                <tbody>
"""
        
        for file_info in coverage_data['low_coverage_files']:
            coverage_pct = file_info['coverage_percentage']
            coverage_class = 'coverage-medium' if coverage_pct >= 60 else 'coverage-low'
            
            html += f"""
                    <tr>
                        <td class="file-name">{os.path.basename(file_info['name'])}</td>
                        <td>{file_info['target']}</td>
                        <td>
                            <div class="coverage-bar">
                                <div class="coverage-fill {coverage_class}" style="width: {coverage_pct}%"></div>
                            </div>
                            {coverage_pct:.1f}%
                        </td>
                        <td>{file_info['covered_lines']}</td>
                        <td>{file_info['executable_lines']}</td>
                    </tr>
"""
        
        html += """
                </tbody>
            </table>
        </div>
"""
    
    html += f"""
        <div class="section">
            <h2>📋 Coverage Summary</h2>
            <div style="color: #666;">
                <p><strong>Overall Assessment:</strong> {status} coverage at {overall_coverage:.1f}%</p>
                <p><strong>Files Analyzed:</strong> {summary['total_files']} files across all targets</p>
                <p><strong>Code Coverage:</strong> {summary['covered_lines']:,} of {summary['executable_lines']:,} executable lines covered</p>
                
                {f'<p><strong>Attention Needed:</strong> {len(coverage_data["low_coverage_files"])} files have coverage below 80%</p>' if coverage_data['low_coverage_files'] else '<p><strong>Great Job:</strong> All files meet the 80% coverage threshold!</p>'}
                
                <p><em>Generated on {__import__('datetime').datetime.now().strftime('%Y-%m-%d at %H:%M:%S')}</em></p>
            </div>
        </div>
    </div>
</body>
</html>
"""
    
    return html

def main():
    parser = argparse.ArgumentParser(description='Generate code coverage report from Xcode results')
    parser.add_argument('--input', required=True, help='Input coverage JSON file from xcrun xccov')
    parser.add_argument('--output', required=True, help='Output HTML report path')
    parser.add_argument('--json-output', help='Optional JSON output for parsed coverage data')
    parser.add_argument('--format', choices=['html', 'json', 'both'], default='html', help='Output format')
    
    args = parser.parse_args()
    
    # Load coverage data
    print(f"Loading coverage data from {args.input}...")
    try:
        with open(args.input, 'r') as f:
            raw_coverage = json.load(f)
    except Exception as e:
        print(f"Error loading coverage data: {e}")
        exit(1)
    
    # Parse coverage data
    print("Parsing coverage data...")
    parsed_coverage = parse_xcode_coverage(raw_coverage)
    
    # Generate reports
    if args.format in ['html', 'both']:
        print(f"Generating HTML report...")
        html_content = generate_html_coverage_report(parsed_coverage)
        
        os.makedirs(os.path.dirname(args.output), exist_ok=True)
        with open(args.output, 'w') as f:
            f.write(html_content)
        
        print(f"✅ HTML report generated: {args.output}")
    
    if args.format in ['json', 'both'] and args.json_output:
        print(f"Generating JSON report...")
        os.makedirs(os.path.dirname(args.json_output), exist_ok=True)
        with open(args.json_output, 'w') as f:
            json.dump(parsed_coverage, f, indent=2)
        
        print(f"✅ JSON report generated: {args.json_output}")
    
    # Print summary
    print("\n" + "="*50)
    print("📊 COVERAGE SUMMARY")
    print("="*50)
    print(f"Overall Coverage: {parsed_coverage['overall_coverage']:.1f}%")
    print(f"Total Files: {parsed_coverage['summary']['total_files']}")
    print(f"Covered Lines: {parsed_coverage['summary']['covered_lines']:,}")
    print(f"Executable Lines: {parsed_coverage['summary']['executable_lines']:,}")
    print(f"Low Coverage Files: {len(parsed_coverage['low_coverage_files'])}")
    
    if parsed_coverage['low_coverage_files']:
        print(f"\n⚠️ Files needing attention (first 5):")
        for file_info in parsed_coverage['low_coverage_files'][:5]:
            print(f"  • {os.path.basename(file_info['name'])}: {file_info['coverage_percentage']:.1f}%")
    
    print("="*50)

if __name__ == '__main__':
    main()