#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

# Provide a Control Plane for running Sprint-scoped tests.
# Usage: python3 scripts/run_sprint.py 24
# Output: Test_Sprints/Sprint_24/results.xml

def load_manifest():
    path = Path("Test_Sprints/sprint_test_manifest.json")
    if not path.exists():
        print(f"Error: Manifest not found at {path}")
        sys.exit(1)
    with open(path) as f:
        return json.load(f)["sprints"]

def run_sprint(sprint_id, config):
    print(f"🚀 Running Tests for Sprint {sprint_id}: {config['name']}")
    
    # Prepare Output Dir
    out_dir = Path(f"Test_Sprints/Sprint_{sprint_id}")
    out_dir.mkdir(parents=True, exist_ok=True)
    
    xml_path = out_dir / "results.xml"
    
    # Build Filter
    # Swift test filter: "Class1|Class2"
    tests = config["tests"]
    filter_arg = "|".join(tests)
    
    cmd = [
        "swift", "test",
        "--filter", filter_arg,
        "--xunit-output", str(xml_path),
        "--disable-xctest",  # Prefer Swift Testing if possible, or omit if strictly XCTest
        "--enable-swift-testing"
    ]
    
    # Run
    print(f"Executing: {' '.join(cmd)}")
    try:
        subprocess.run(cmd, check=True)
        print(f"✅ Success! Results: {xml_path}")
    except subprocess.CalledProcessError:
        print(f"❌ Tests Failed for Sprint {sprint_id}")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("sprint_id", help="Sprint ID (e.g. 01, 24)")
    args = parser.parse_args()
    
    manifest = load_manifest()
    if args.sprint_id not in manifest:
        print(f"Error: Sprint {args.sprint_id} not found in manifest.")
        print("Available:", ", ".join(manifest.keys()))
        sys.exit(1)
        
    run_sprint(args.sprint_id, manifest[args.sprint_id])

if __name__ == "__main__":
    main()
