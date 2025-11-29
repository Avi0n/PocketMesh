#!/usr/bin/env python3
"""
MeshCore Enum Sync Generator

This script downloads the latest MeshCore Python library from GitHub,
extracts enum definitions from Python source files using AST parsing,
and generates Swift enums by extending the existing protocol enums in
PocketMeshKit/Protocol/ProtocolFrame.swift.

Usage:
    uv run meshcore_enum_generator.py --dry-run --verbose
    uv run meshcore-sync --help
"""

import ast
import json
import re
import tempfile
import zipfile
import time
import requests
import argparse
import sys
import shutil
import subprocess
from pathlib import Path
from typing import Dict, List, Tuple, Optional, Set
from dataclasses import dataclass
from urllib.parse import urlparse
from datetime import datetime

# Try to import rich for better UI, fallback to basic print
try:
    from rich.console import Console
    from rich.table import Table
    from rich.panel import Panel
    RICH_AVAILABLE = True
except ImportError:
    RICH_AVAILABLE = False
    Console = None

@dataclass
class EnumCase:
    """Represents a single enum case extracted from Python source"""
    name: str
    value: int
    source_file: str
    line_number: int
    original_name: str  # Keep original SCREAMING_SNAKE_CASE

@dataclass
class EnumDefinition:
    """Represents a complete enum definition from Python source"""
    name: str
    cases: List[EnumCase]
    base_type: str  # 'IntEnum', 'Enum', etc.
    source_file: str

@dataclass
class ReleaseInfo:
    """Information about a GitHub release"""
    tag: str
    name: str
    download_url: str
    published_at: str

@dataclass
class SwiftEnumCase:
    """Represents a Swift enum case from the existing ProtocolFrame.swift"""
    name: str
    value: int
    comment: Optional[str] = None
    line_number: Optional[int] = None

@dataclass
class ChangeAnalysis:
    """Analysis of differences between Python and Swift enums"""
    target_enum: str
    additions: List[EnumCase]
    updates: List[Tuple[EnumCase, SwiftEnumCase]]  # (new, existing)
    duplicates: List[EnumCase]
    swift_extras: List[SwiftEnumCase]  # Cases in Swift not in Python

class MeshCoreExtractor:
    """Extract enum definitions from MeshCore Python source using AST parsing"""

    def __init__(self, source_dir: Path):
        self.source_dir = source_dir
        self.enums: Dict[str, EnumDefinition] = {}

    def extract_all_enums(self) -> Dict[str, EnumDefinition]:
        """Extract all IntEnum definitions from source directory"""
        self.enums = {}

        for py_file in self.source_dir.rglob("*.py"):
            try:
                with open(py_file, 'r', encoding='utf-8') as f:
                    content = f.read()

                tree = ast.parse(content)
                for node in ast.walk(tree):
                    if isinstance(node, ast.ClassDef):
                        enum_def = self._extract_int_enum(node, py_file)
                        if enum_def:
                            self.enums[enum_def.name] = enum_def

            except (SyntaxError, UnicodeDecodeError) as e:
                print(f"Warning: Skipping {py_file}: {e}")
                continue

        return self.enums

    def _extract_int_enum(self, class_node: ast.ClassDef, source_file: Path) -> Optional[EnumDefinition]:
        """Extract IntEnum definition from AST class node"""
        # Check if class inherits from IntEnum
        if not self._is_int_enum_subclass(class_node):
            return None

        cases = []
        base_type = 'Enum'  # Default to Enum
        for node in class_node.body:
            if isinstance(node, ast.Assign):
                case = self._extract_enum_case(node, source_file)
                if case:
                    cases.append(case)

        # Only accept enums with at least 2 numeric cases
        if len(cases) < 2:
            return None

        # Skip commands directory and sub-enums (BinaryReqType, ControlType)
        skip_enum_names = {'BinaryReqType', 'ControlType'}
        if (class_node.name in skip_enum_names or
            'commands' in str(source_file.relative_to(self.source_dir)).lower()):
            return None

        # Extract only PacketType for core protocol sync (eliminates false positives)
        if class_node.name != 'PacketType':
            return None

        # Determine actual base type
        for base in class_node.bases:
            if isinstance(base, ast.Name):
                if base.id == 'IntEnum':
                    base_type = 'IntEnum'
                    break
                elif base.id == 'Enum':
                    base_type = 'Enum'
                    break

        return EnumDefinition(
            name=class_node.name,
            cases=cases,
            base_type=base_type,
            source_file=str(source_file.relative_to(self.source_dir))
        )

    def _is_int_enum_subclass(self, class_node: ast.ClassDef) -> bool:
        """Check if class inherits from IntEnum or regular Enum"""
        # Skip command handler classes and bases
        class_name_lower = class_node.name.lower()
        if any(skip_word in class_name_lower for skip_word in ['command', 'handler', 'base']):
            return False

        for base in class_node.bases:
            if isinstance(base, ast.Name):
                if base.id in ['IntEnum', 'Enum']:
                    return True
            elif isinstance(base, ast.Attribute):
                if base.attr in ['IntEnum', 'Enum']:
                    return True
        return False

    def _extract_enum_case(self, assign_node: ast.Assign, source_file: Path) -> Optional[EnumCase]:
        """Extract individual enum case from assignment node"""
        if len(assign_node.targets) != 1:
            return None

        target = assign_node.targets[0]
        if not isinstance(target, ast.Name):
            return None

        enum_name = target.id
        value = self._evaluate_constant(assign_node.value)

        if value is None or not isinstance(value, int):
            return None

        return EnumCase(
            name=self._normalize_name(enum_name),
            value=int(value),
            source_file=str(source_file),
            line_number=assign_node.lineno,
            original_name=enum_name
        )

    def _evaluate_constant(self, node: ast.AST) -> Optional[int]:
        """Evaluate AST node to get integer constant value"""
        if isinstance(node, ast.Constant):
            return node.value if isinstance(node.value, int) else None
        elif isinstance(node, ast.Num):  # Python < 3.8 compatibility
            return node.n if isinstance(node.n, int) else None
        elif isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.USub):
            inner = self._evaluate_constant(node.operand)
            return -inner if inner is not None else None
        return None

    def _normalize_name(self, name: str) -> str:
        """Convert SCREAMING_SNAKE_CASE to lowerCamelCase"""
        parts = name.lower().split('_')
        if not parts:
            return name
        return parts[0] + ''.join(p.capitalize() for p in parts[1:])

    def map_to_swift_enums(self) -> Dict[str, List[EnumCase]]:
        """Map extracted Python enums to Swift targets with dynamic detection and deduplication"""
        swift_enums = {'CommandCode': [], 'ResponseCode': [], 'PushCode': []}
        seen_cases: Set[Tuple[str, int]] = set()  # (normalized_name, value)

        for enum_def in self.enums.values():
            target_enums = self._detect_target_enums_dynamic(enum_def)

            for case in enum_def.cases:
                case_key = (case.name, case.value)

                if case_key in seen_cases:
                    continue  # Skip duplicates

                seen_cases.add(case_key)

                for target in target_enums:
                    swift_enums[target].append(case)

        return swift_enums

    def _detect_target_enums_dynamic(self, enum_def: EnumDefinition) -> List[str]:
        """Dynamically determine target Swift enums based on naming and value patterns"""
        enum_name = enum_def.name.lower()
        values = [case.value for case in enum_def.cases]

        # Pattern-based detection for known enum types
        if any(keyword in enum_name for keyword in ['req', 'cmd', 'command', 'binary']):
            return ['CommandCode']

        if any(keyword in enum_name for keyword in ['resp', 'response', 'event']):
            # Separate by value range for responses vs push notifications
            if any(v >= 0x80 for v in values):
                return ['PushCode']
            else:
                return ['ResponseCode']

        # Handle PacketType specifically (mixed values)
        if 'packet' in enum_name:
            # For PacketType, return both and let the analyzer filter by value range
            return ['ResponseCode', 'PushCode']

        # Skip EventType (string values) and other non-numeric enums
        if any(keyword in enum_name for keyword in ['event', 'type']) and not values:
            return []

        # Fallback: analyze value ranges to determine target enums
        if not values:
            return []

        if all(v < 0x80 for v in values):
            return ['ResponseCode']
        elif all(v >= 0x80 for v in values):
            return ['PushCode']
        else:
            # Mixed values - likely PacketType or similar, split appropriately
            return ['ResponseCode', 'PushCode']

class GitHubDownloader:
    """Download and extract MeshCore Python releases from GitHub"""

    MESHCORE_REPO = "meshcore-dev/meshcore_py"
    GITHUB_API = "https://api.github.com/repos"
    TIMEOUT = 30
    MAX_RETRIES = 3

    def __init__(self, temp_dir: Optional[Path] = None):
        self.temp_dir = temp_dir or Path(tempfile.mkdtemp(prefix="meshcore_sync_"))
        self.session = requests.Session()
        self.session.headers.update({
            'Accept': 'application/vnd.github.v3+json',
            'User-Agent': 'meshcore-enum-sync/1.0'
        })

    def get_latest_release_info(self) -> ReleaseInfo:
        """Fetch latest release information from GitHub API with retries"""
        for attempt in range(self.MAX_RETRIES):
            try:
                url = f"{self.GITHUB_API}/{self.MESHCORE_REPO}/releases/latest"
                response = self.session.get(url, timeout=self.TIMEOUT)
                response.raise_for_status()
                data = response.json()

                # Find source archive (not just the wheel)
                download_url = None
                for asset in data.get('assets', []):
                    if asset['name'].endswith('.zip') and 'source' in asset['name'].lower():
                        download_url = asset['browser_download_url']
                        break

                # Fallback to source archive if no source-specific zip
                if not download_url:
                    download_url = f"https://github.com/{self.MESHCORE_REPO}/archive/{data['tag_name']}.zip"

                return ReleaseInfo(
                    tag=data['tag_name'],
                    name=data['name'],
                    download_url=download_url,
                    published_at=data['published_at']
                )

            except (requests.RequestException, KeyError, ValueError) as e:
                if attempt == self.MAX_RETRIES - 1:
                    raise RuntimeError(f"Failed to fetch release info after {self.MAX_RETRIES} attempts: {e}")
                time.sleep(2 ** attempt)  # Exponential backoff
                continue

    def download_release(self, tag_name: Optional[str] = None) -> Path:
        """Download and extract specific release to temporary directory"""
        if tag_name:
            # Download specific tag
            url = f"https://github.com/{self.MESHCORE_REPO}/archive/{tag_name}.zip"
            release_info = ReleaseInfo(
                tag=tag_name,
                name=f"Release {tag_name}",
                download_url=url,
                published_at="unknown"
            )
        else:
            release_info = self.get_latest_release_info()

        print(f"Downloading {release_info.tag} from {release_info.download_url}")

        # Download file
        zip_path = self.temp_dir / f"{release_info.tag}.zip"
        for attempt in range(self.MAX_RETRIES):
            try:
                response = self.session.get(release_info.download_url, timeout=self.TIMEOUT, stream=True)
                response.raise_for_status()

                with open(zip_path, 'wb') as f:
                    for chunk in response.iter_content(chunk_size=8192):
                        f.write(chunk)

                break

            except requests.RequestException as e:
                if attempt == self.MAX_RETRIES - 1:
                    raise RuntimeError(f"Failed to download release after {self.MAX_RETRIES} attempts: {e}")
                time.sleep(2 ** attempt)
                continue

        # Extract archive
        extract_dir = self.temp_dir / "source"
        with zipfile.ZipFile(zip_path, 'r') as zip_ref:
            zip_ref.extractall(extract_dir)

        # Find the extracted source directory (usually repo-name-tag)
        extracted_dirs = [d for d in extract_dir.iterdir() if d.is_dir()]
        if not extracted_dirs:
            raise RuntimeError("No source directory found in extracted archive")

        source_dir = extracted_dirs[0]  # Usually only one directory
        print(f"Extracted to: {source_dir}")

        return source_dir

    def cleanup(self):
        """Clean up temporary files"""
        import shutil
        if self.temp_dir.exists():
            shutil.rmtree(self.temp_dir)

class SwiftAnalyzer:
    """Analyze Swift files and generate enum case code"""

    def __init__(self, protocol_frame_path: Path, version_tag: str):
        self.protocol_frame_path = protocol_frame_path
        self.version_tag = version_tag
        self.swift_enums = self._parse_existing_enums()

    def _parse_existing_enums(self) -> Dict[str, List[SwiftEnumCase]]:
        """Parse existing Swift enum definitions from ProtocolFrame.swift"""
        enums = {'CommandCode': [], 'ResponseCode': [], 'PushCode': []}

        try:
            with open(self.protocol_frame_path, 'r', encoding='utf-8') as f:
                content = f.read()

            # Find enum blocks
            for enum_name in enums.keys():
                enum_pattern = fr'public enum {enum_name}: UInt8, Sendable\s*\{{(.*?)\s*\}}'
                enum_match = re.search(enum_pattern, content, re.MULTILINE | re.DOTALL)

                if enum_match:
                    enum_body = enum_match.group(1)
                    case_pattern = r'case\s+(\w+)\s*=\s*([^/\n]+)(?:\s*//\s*(.*))?'

                    for line_num, line in enumerate(enum_body.split('\n'), start=enum_match.start()):
                        case_match = re.search(case_pattern, line)
                        if case_match:
                            case_name = case_match.group(1)
                            value_str = case_match.group(2).strip()
                            comment = case_match.group(3)

                            # Parse value (handles hex and decimal)
                            value = self._parse_swift_value(value_str)
                            if value is not None:
                                enums[enum_name].append(SwiftEnumCase(
                                    name=case_name,
                                    value=value,
                                    comment=comment,
                                    line_number=line_num
                                ))

        except FileNotFoundError:
            raise RuntimeError(f"ProtocolFrame.swift not found at {self.protocol_frame_path}")
        except Exception as e:
            raise RuntimeError(f"Failed to parse ProtocolFrame.swift: {e}")

        return enums

    def _parse_swift_value(self, value_str: str) -> Optional[int]:
        """Parse Swift value string to integer"""
        value_str = value_str.strip().rstrip(',')  # Remove trailing comma

        if value_str.startswith('0x') or value_str.startswith('0X'):
            return int(value_str, 16)
        else:
            return int(value_str)

    def analyze_changes(self, python_enums: Dict[str, List[EnumCase]]) -> List[ChangeAnalysis]:
        """Analyze differences between Python and Swift enums"""
        analyses = []

        for enum_name in ['CommandCode', 'ResponseCode', 'PushCode']:
            python_cases = python_enums.get(enum_name, [])
            swift_cases = self.swift_enums.get(enum_name, [])

            # Filter PacketType cases by value range
            if enum_name == 'ResponseCode':
                python_cases = [c for c in python_cases if c.value < 0x80]
            elif enum_name == 'PushCode':
                python_cases = [c for c in python_cases if c.value >= 0x80]

            analysis = self._analyze_enum_changes(enum_name, python_cases, swift_cases)
            analyses.append(analysis)

        return analyses

    def _analyze_enum_changes(self, enum_name: str, python_cases: List[EnumCase], swift_cases: List[SwiftEnumCase]) -> ChangeAnalysis:
        """Analyze changes for a specific enum"""
        swift_case_map = {case.name: case for case in swift_cases}
        swift_value_map = {case.value: case for case in swift_cases}

        additions = []
        updates = []
        duplicates = []
        swift_extras = []

        # Normalize Swift names to lowerCamelCase for better matching
        def normalize_swift_name(name: str) -> str:
            """Local normalize for Swift names (already camelCase -> lower)"""
            parts = re.split(r'([A-Z][a-z]*)', name)
            return ''.join(p.lower() for p in parts if p).replace('_', '')

        swift_normalized_map = {(normalize_swift_name(case.name), case.value): case for case in swift_cases}
        swift_value_map = {case.value: case for case in swift_cases}

        for py_case in python_cases:
            py_key = (py_case.name.lower(), py_case.value)
            # Check for exact normalized name + value match (covered)
            if py_key in swift_normalized_map:
                continue  # Exact match, fully covered
            # Check for value match with different name (duplicate value)
            elif py_case.value in swift_value_map:
                duplicates.append(py_case)
            else:
                additions.append(py_case)

        # Find Swift cases not in Python
        py_case_names = {case.name for case in python_cases}
        py_case_values = {case.value for case in python_cases}

        for swift_case in swift_cases:
            if swift_case.name not in py_case_names and swift_case.value not in py_case_values:
                swift_extras.append(swift_case)

        return ChangeAnalysis(
            target_enum=enum_name,
            additions=additions,
            updates=updates,
            duplicates=duplicates,
            swift_extras=swift_extras
        )

    def generate_swift_cases(self, cases: List[EnumCase]) -> str:
        """Generate Swift enum case code with consistent formatting"""
        if not cases:
            return ""

        lines = []
        for case in sorted(cases, key=lambda c: c.value):
            # Use consistent hex formatting: hex for push codes (>= 0x80), decimal otherwise
            value_str = self._format_swift_value(case.value, case.original_name)

            # Generate comment with source information
            comment = f" // Python: {case.original_name} ({Path(case.source_file).name} v{self.version_tag})"

            lines.append(f"    case {case.name} = {value_str}{comment}")

        return "\n".join(lines)

    def _format_swift_value(self, value: int, source_context: str = "") -> str:
        """Format value consistently with Swift conventions"""
        # Use hex for values >= 0x80 (push codes) or when source context suggests hex
        if value >= 0x80 or source_context.startswith('0x'):
            return f"0x{value:02X}"
        else:
            return str(value)

    def insert_cases_into_swift_file(self, content: str, target_enum: str, new_cases_code: str) -> str:
        """Insert new enum cases into the Swift file content with proper sorting and comma handling"""

        # Find the target enum with more robust regex pattern
        enum_pattern = fr'public enum {target_enum}: UInt8, Sendable\s*\{{(.*?)\s*\}}'
        enum_match = re.search(enum_pattern, content, re.MULTILINE | re.DOTALL)

        if not enum_match:
            # Fallback to line-by-line parsing for more reliability
            content = self._parse_enum_by_lines(content, target_enum, new_cases_code)
            return content

        enum_body = enum_match.group(1)
        closing_brace = enum_match.group(2)

        # Parse existing cases for sorting
        existing_cases = self.swift_enums.get(target_enum, [])
        new_cases = self._parse_new_cases_from_code(new_cases_code)

        if not new_cases:
            return content  # No new cases to insert

        # Merge existing and new cases, then sort by value (standard Swift practice)
        all_cases = existing_cases + new_cases
        sorted_cases = sorted(all_cases, key=lambda c: c.value)

        # Generate complete enum content with proper comma handling
        enum_lines = []
        for i, case in enumerate(sorted_cases):
            comment_part = f" // {case.comment}" if case.comment else ""
            comma_part = "," if i < len(sorted_cases) - 1 else ""  # No comma on last case

            if case.value < 256 and (case.name.startswith(('node', 'path', 'send', 'set', 'get', 'req', 'resp')) or case.value >= 0x80):
                value_str = f"0x{case.value:02X}"
            else:
                value_str = str(case.value)

            enum_lines.append(f"    case {case.name} = {value_str}{comment_part}{comma_part}")

        new_enum_body_content = "\n".join(enum_lines)
        new_enum_body = f"public enum {target_enum}: UInt8, Sendable {{\n{new_enum_body_content}\n{closing_brace.strip()}}}"

        # Replace the entire enum block with more robust pattern
        full_enum_pattern = fr'public enum {target_enum}: UInt8, Sendable\s*\{{.*?\s*\}}'
        new_content = re.sub(full_enum_pattern, new_enum_body, content, flags=re.MULTILINE | re.DOTALL)

        return new_content

    def _parse_enum_by_lines(self, content: str, enum_name: str, new_cases_code: str) -> str:
        """Fallback line-by-line enum parsing for more reliable extraction"""
        lines = content.split('\n')
        start_line = None
        end_line = None
        brace_count = 0

        for i, line in enumerate(lines):
            if f'public enum {enum_name}: UInt8, Sendable' in line:
                start_line = i
                brace_count = line.count('{') - line.count('}')
            elif start_line is not None:
                brace_count += line.count('{') - line.count('}')
                if brace_count <= 0:
                    end_line = i
                    break

        if start_line is None or end_line is None:
            raise RuntimeError(f"Could not find {enum_name} enum using line-by-line parsing")

        # Insert new cases before the closing brace
        lines.insert(end_line, new_cases_code)
        return '\n'.join(lines)

    def _parse_new_cases_from_code(self, new_cases_code: str) -> List[SwiftEnumCase]:
        """Parse new enum cases from generated Swift code"""
        cases = []
        for line in new_cases_code.strip().split('\n'):
            if line.strip().startswith('case '):
                # Parse: "    case name = value // comment"
                match = re.match(r'\s*case\s+(\w+)\s*=\s*([^/\s]+)(?:\s*//\s*(.*))?', line.strip())
                if match:
                    name = match.group(1)
                    value_str = match.group(2)
                    comment = match.group(3)

                    # Parse value
                    if value_str.startswith('0x') or value_str.startswith('0X'):
                        value = int(value_str, 16)
                    else:
                        value = int(value_str)

                    cases.append(SwiftEnumCase(
                        name=name,
                        value=value,
                        comment=comment
                    ))
        return cases

    def validate_swift_syntax(self, content: str) -> Tuple[bool, str]:
        """Validate Swift syntax using swiftc and optionally format with SwiftFormat"""
        try:
            # Write content to temporary file
            temp_file = self.protocol_frame_path.parent / f".temp_{self.protocol_frame_path.name}"
            with open(temp_file, 'w', encoding='utf-8') as f:
                f.write(content)

            # Run swiftc syntax check
            result = subprocess.run(
                ['swiftc', '-parse', str(temp_file)],
                capture_output=True,
                text=True,
                timeout=30
            )

            syntax_valid = result.returncode == 0
            error_output = result.stderr

            # Optional: Run SwiftFormat if available
            if syntax_valid:
                swiftformat_result = self._run_swiftformat(temp_file)
                if swiftformat_result:
                    # Read formatted content back
                    with open(temp_file, 'r', encoding='utf-8') as f:
                        formatted_content = f.read()

                    # Re-validate formatted content
                    format_check_result = subprocess.run(
                        ['swiftc', '-parse', str(temp_file)],
                        capture_output=True,
                        text=True,
                        timeout=30
                    )

                    if format_check_result.returncode == 0:
                        temp_file.unlink(missing_ok=True)
                        return True, formatted_content  # Return formatted content
                    else:
                        error_output += f"\nSwiftFormat introduced syntax errors: {format_check_result.stderr}"

            # Clean up
            temp_file.unlink(missing_ok=True)

            return syntax_valid, error_output

        except subprocess.TimeoutExpired:
            return False, "Swift validation timed out"
        except Exception as e:
            return False, f"Validation error: {e}"

    def _run_swiftformat(self, file_path: Path) -> bool:
        """Run SwiftFormat on file if available"""
        try:
            import shutil
            swiftformat_path = shutil.which('swiftformat')
            if not swiftformat_path:
                return False

            result = subprocess.run(
                [swiftformat_path, '--quiet', str(file_path)],
                capture_output=True,
                timeout=30
            )
            return result.returncode == 0

        except (subprocess.TimeoutExpired, Exception):
            return False

class MeshCoreSyncApp:
    """Main application orchestrating the enum synchronization process"""

    def __init__(self, protocol_frame_path: Path, temp_dir: Optional[Path] = None):
        self.protocol_frame_path = protocol_frame_path
        self.temp_dir = temp_dir or Path(tempfile.mkdtemp(prefix="meshcore_sync_"))
        self.console = Console() if RICH_AVAILABLE else None
        self.downloader = GitHubDownloader(self.temp_dir)
        self.version_tag = None

    def run(self, dry_run: bool = True, auto_approve: bool = False,
            baseline_version: Optional[str] = None, verbose: bool = False,
            skip_backup: bool = False, max_additions: int = 50) -> int:
        """Main application execution flow"""
        try:
            if verbose:
                self._print(f"🚀 Starting MeshCore enum synchronization")
                self._print(f"📁 Target file: {self.protocol_frame_path}")

            # Step 1: Download and extract MeshCore source
            self._print("📥 Downloading MeshCore Python library...")
            source_dir = self.downloader.download_release(baseline_version)
            self.version_tag = self._extract_version_from_path(source_dir)

            if verbose:
                self._print(f"📦 Extracted version: {self.version_tag}")

            # Step 2: Extract enums from Python source
            self._print("🔍 Extracting enum definitions...")
            extractor = MeshCoreExtractor(source_dir)
            python_enums = extractor.extract_all_enums()
            mapped_enums = extractor.map_to_swift_enums()

            if verbose:
                for enum_name, cases in mapped_enums.items():
                    self._print(f"  {enum_name}: {len(cases)} cases")

            # Step 3: Analyze changes
            self._print("⚖️  Analyzing changes...")
            analyzer = SwiftAnalyzer(self.protocol_frame_path, self.version_tag)
            analyses = analyzer.analyze_changes(mapped_enums)

            # Step 3.5: Safety check for too many additions
            total_additions = sum(len(a.additions) for a in analyses)
            if total_additions > max_additions and not auto_approve:
                self._print(f"⚠️  Warning: {total_additions} additions exceed safety limit of {max_additions}")
                self._print("This may indicate incorrect enum mapping or version mismatch.")
                response = input("Proceed anyway? (y/n): ").lower().strip()
                if response not in ('y', 'yes'):
                    self._print("🛑 Aborted due to safety limit")
                    return 0

            # Step 4: Show summary and get approval
            if not self._show_change_summary(analyses, dry_run, auto_approve):
                return 0

            if dry_run:
                self._print("🔍 Dry run complete - no changes made")
                return 0

            # Step 5: Apply changes
            self._print("✏️  Applying changes...")
            if not self._apply_changes(analyses, analyzer, skip_backup):
                return 1

            # Step 6: Update version comment
            self._update_version_comment()

            self._print(f"✅ Synchronization complete! (backup: {self.protocol_frame_path}.backup.{datetime.now().strftime('%Y%m%d_%H%M%S')})")
            return 0

        except Exception as e:
            self._print(f"❌ Error: {e}")
            if verbose:
                import traceback
                traceback.print_exc()
            return 1

        finally:
            self.downloader.cleanup()

    def _extract_version_from_path(self, source_dir: Path) -> str:
        """Extract version from path with robust fallback to release tag"""
        dir_name = source_dir.name

        # Try to extract from directory name (meshcore_py-2.2.1 pattern)
        if '-' in dir_name:
            potential_version = dir_name.split('-', 1)[1]
            # Validate that it looks like a version number
            if potential_version.replace('.', '').replace('v', '').isdigit():
                return potential_version.lstrip('v')

        return "unknown"

    def _show_change_summary(self, analyses: List[ChangeAnalysis], dry_run: bool, auto_approve: bool) -> bool:
        """Show comprehensive change summary and get approval"""
        total_additions = sum(len(a.additions) for a in analyses)
        total_updates = sum(len(a.updates) for a in analyses)
        total_duplicates = sum(len(a.duplicates) for a in analyses)

        if total_additions == 0 and total_updates == 0:
            self._print("✅ No changes detected - enums are already in sync!")
            return False

        if self.console:
            # Rich formatting
            table = Table(title="📊 Change Summary")
            table.add_column("Enum", style="cyan")
            table.add_column("Additions", style="green")
            table.add_column("Updates", style="yellow")
            table.add_column("Duplicates", style="red")
            table.add_column("Swift Extras", style="magenta")

            for analysis in analyses:
                # Show duplicate values with warnings
                duplicate_info = str(len(analysis.duplicates))
                if analysis.duplicates:
                    duplicate_values = [f"{case.name}={case.value}" for case in analysis.duplicates[:3]]
                    if len(analysis.duplicates) > 3:
                        duplicate_values.append(f"+{len(analysis.duplicates) - 3} more")
                    duplicate_info = f"[red]{len(analysis.duplicates)}[/red]\n({', '.join(duplicate_values)})"

                table.add_row(
                    analysis.target_enum,
                    str(len(analysis.additions)),
                    str(len(analysis.updates)),
                    duplicate_info,
                    str(len(analysis.swift_extras))
                )

            table.add_row(
                "**Total**",
                f"[green]{total_additions}[/green]",
                f"[yellow]{total_updates}[/yellow]",
                f"[red]{total_duplicates}[/red]" if total_duplicates > 0 else "0",
                ""
            )

            self.console.print(table)

            # Show detailed duplicate warnings
            if total_duplicates > 0:
                self.console.print("\n⚠️  [bold red]Duplicate Value Warnings:[/bold red]")
                for analysis in analyses:
                    if analysis.duplicates:
                        self.console.print(f"\n[bold]{analysis.target_enum}:[/bold]")
                        for dup_case in analysis.duplicates:
                            self.console.print(f"  • {dup_case.original_name} (value {dup_case.value}) conflicts with existing case")

        else:
            # Basic formatting
            self._print("\n📊 Change Summary:")
            self._print("-" * 60)
            for analysis in analyses:
                dup_warning = f" dup{len(analysis.duplicates)}" if len(analysis.duplicates) > 0 else ""
                self._print(f"{analysis.target_enum}: +{len(analysis.additions)} ~{len(analysis.updates)}{dup_warning}")
                if analysis.duplicates:
                    self._print(f"  ⚠️  Duplicates: {', '.join(f'{case.name}={case.value}' for case in analysis.duplicates)}")
            self._print(f"Total: +{total_additions} additions, {total_updates} updates, {total_duplicates} duplicates")

        if dry_run:
            self._print("\n🔍 DRY RUN MODE - No changes will be applied")

        if auto_approve:
            self._print("🤖 AUTO-APPROVAL ENABLED")
            return True

        # Get user approval
        response = input("\nProceed with these changes? (y/n): ").lower().strip()
        return response in ('y', 'yes')

    def _apply_changes(self, analyses: List[ChangeAnalysis], analyzer: SwiftAnalyzer, skip_backup: bool = False) -> bool:
        """Apply approved changes to Swift file with proper content accumulation"""
        # Create backup (unless skipped)
        backup_path = None
        if not skip_backup:
            backup_path = self._create_backup()
        else:
            self._print("⚠️  Skipping backup creation (--force flag used)")

        try:
            # Read original content once
            with open(self.protocol_frame_path, 'r', encoding='utf-8') as f:
                content = f.read()

            for analysis in analyses:
                if not analysis.additions:
                    continue

                # Get user approval for each enum (unless auto-approved)
                if not self._get_enum_approval(analysis):
                    continue

                # Generate and insert new cases
                new_cases_code = analyzer.generate_swift_cases(analysis.additions)
                if new_cases_code:
                    # Pass content to insert method and get updated content back
                    content = analyzer.insert_cases_into_swift_file(content, analysis.target_enum, new_cases_code)
                    self._print(f"✅ Added {len(analysis.additions)} cases to {analysis.target_enum}")

            # Validate and format before writing
            is_valid, result = analyzer.validate_swift_syntax(content)
            if not is_valid:
                self._print(f"❌ Generated Swift code has syntax errors:")
                self._print(result)
                if backup_path:
                    self._restore_backup(backup_path)
                return False

            # Use formatted content if SwiftFormat was applied
            final_content = result if isinstance(result, str) else content

            # Write changes once at the end
            with open(self.protocol_frame_path, 'w', encoding='utf-8') as f:
                f.write(final_content)

            return True

        except Exception as e:
            self._print(f"❌ Error applying changes: {e}")
            if backup_path:
                self._restore_backup(backup_path)
            return False

    def _get_enum_approval(self, analysis: ChangeAnalysis) -> bool:
        """Get user approval for specific enum changes"""
        if not analysis.additions:
            return False

        self._print(f"\n📝 {analysis.target_enum} changes:")
        for case in analysis.additions[:5]:  # Show first 5
            self._print(f"  + {case.name} = {case.value} // {case.original_name}")
        if len(analysis.additions) > 5:
            self._print(f"  ... and {len(analysis.additions) - 5} more")

        response = input(f"Apply {len(analysis.additions)} changes to {analysis.target_enum}? (y/n/skip): ").lower().strip()
        return response in ('y', 'yes')

    def _create_backup(self) -> Path:
        """Create timestamped backup of ProtocolFrame.swift"""
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        backup_path = Path(f"{self.protocol_frame_path}.backup.{timestamp}")
        shutil.copy2(self.protocol_frame_path, backup_path)
        return backup_path

    def _restore_backup(self, backup_path: Path) -> bool:
        """Restore from backup"""
        try:
            shutil.copy2(backup_path, self.protocol_frame_path)
            self._print(f"🔄 Restored from backup: {backup_path}")
            return True
        except Exception as e:
            self._print(f"❌ Failed to restore backup: {e}")
            return False

    def _update_version_comment(self):
        """Update version comment in Swift file"""
        try:
            with open(self.protocol_frame_path, 'r') as f:
                content = f.read()

            version_comment = f"// Synced to MeshCore_py v{self.version_tag} on {datetime.now().strftime('%Y-%m-%d')}"

            if "// Synced to MeshCore_py" in content:
                # Update existing comment
                content = re.sub(
                    r'// Synced to MeshCore_py.*$',
                    version_comment,
                    content,
                    flags=re.MULTILINE
                )
            else:
                # Add comment at the beginning of the file
                content = f"{version_comment}\n\n{content}"

            with open(self.protocol_frame_path, 'w') as f:
                f.write(content)

        except Exception as e:
            self._print(f"⚠️  Warning: Could not update version comment: {e}")

    def _print(self, message: str):
        """Print message with optional rich formatting"""
        if self.console:
            self.console.print(message)
        else:
            print(message)

def create_argument_parser() -> argparse.ArgumentParser:
    """Create and configure command-line argument parser"""
    parser = argparse.ArgumentParser(
        description="Sync MeshCore Python enums with Swift ProtocolFrame.swift",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --dry-run                                    # Preview changes only
  %(prog)s --protocol-frame ./ProtocolFrame.swift       # Specify custom file
  %(prog)s --apply --verbose                            # Apply changes with verbose output
  %(prog)s --baseline v2.1.0                           # Compare against specific version
        """
    )

    parser.add_argument(
        '--protocol-frame',
        type=Path,
        default=Path(__file__).parent.parent.parent / 'PocketMeshKit/Protocol/ProtocolFrame.swift',
        help='Path to ProtocolFrame.swift file (default: PocketMeshKit/Protocol/ProtocolFrame.swift)'
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        default=True,
        help='Preview changes without applying (default enabled)'
    )
    parser.add_argument(
        '--apply',
        action='store_true',
        help='Apply changes (disables dry-run mode)'
    )
    parser.add_argument(
        '--auto-approve',
        action='store_true',
        help='Skip interactive approval prompts (use with caution)'
    )
    parser.add_argument(
        '--verbose',
        action='store_true',
        help='Enable verbose output with detailed information'
    )
    parser.add_argument(
        '--baseline',
        help='Compare against specific version tag instead of latest'
    )
    parser.add_argument(
        '--temp-dir',
        type=Path,
        help='Custom temporary directory for downloads'
    )
    parser.add_argument(
        '--force',
        action='store_true',
        help='Skip backup creation (use with extreme caution)'
    )
    parser.add_argument(
        '--max-additions',
        type=int,
        default=50,
        help='Maximum number of enum additions to prevent accidental bulk changes'
    )

    return parser

def main() -> int:
    """Main entry point for the script"""
    parser = create_argument_parser()
    args = parser.parse_args()

    # Validate protocol frame file exists
    if not args.protocol_frame.exists():
        print(f"❌ Error: ProtocolFrame.swift not found at {args.protocol_frame}")
        return 1

    # Safety checks
    if args.auto_approve and not args.apply:
        print("❌ Error: --auto-approve requires --apply (otherwise no changes would be made)")
        return 1

    if args.force and not args.apply:
        print("❌ Error: --force requires --apply (skipping backups only makes sense when applying changes)")
        return 1

    # Create and run app
    app = MeshCoreSyncApp(
        protocol_frame_path=args.protocol_frame,
        temp_dir=args.temp_dir
    )

    return app.run(
        dry_run=not args.apply,
        auto_approve=args.auto_approve,
        baseline_version=args.baseline,
        verbose=args.verbose,
        skip_backup=args.force,
        max_additions=args.max_additions
    )

if __name__ == '__main__':
    sys.exit(main())

# Phase 1 Complete - Core Enum Extraction with AST Parsing
# Phase 2 Complete - GitHub Download and Release Management
# Phase 3 Complete - Swift Analysis and Code Generation
# Phase 4 Complete - Main Application and CLI Interface