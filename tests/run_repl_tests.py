#!/usr/bin/env python3
import subprocess
import json
import sys
import os
import signal
from pathlib import Path

ROOT_DIR = Path(__file__).parent.parent
APP_BIN = ROOT_DIR / ".build" / "debug" / "RightLayout"

def kill_existing_instances():
    """Kill any existing RightLayout processes."""
    try:
        subprocess.run(["pkill", "-f", "RightLayout"], stderr=subprocess.DEVNULL, timeout=2)
    except:
        pass

def run_repl_tests():
    # Always cleanup first
    kill_existing_instances()
    import time
    time.sleep(0.5)  # Give time for processes to die
    
    print(f"Launching REPL: {APP_BIN}")
    
    proc = subprocess.Popen(
        [str(APP_BIN), "--cli"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=sys.stderr,
        text=True,
        bufsize=1
    )
    
    try:
        # Wait for ready with timeout
        import select
        ready_timeout = 10  # seconds
        ready = False
        
        while ready_timeout > 0:
            # Check if stdout has data
            rlist, _, _ = select.select([proc.stdout], [], [], 1.0)
            if rlist:
                line = proc.stdout.readline()
                if not line:
                    print("Process died unexpectedly")
                    return 1
                if "RightLayout REPL Ready" in line:
                    print("✅ REPL Ready")
                    ready = True
                    break
            ready_timeout -= 1
        
        if not ready:
            print("❌ Timeout waiting for REPL Ready")
            proc.kill()
            return 1
                
        # Helper to query with timeout
        def query(text):
            proc.stdin.write(f"CORRECT:{text}\n")
            proc.stdin.flush()
            
            # Wait for response with timeout
            rlist, _, _ = select.select([proc.stdout], [], [], 5.0)
            if not rlist:
                return None
            
            out_line = proc.stdout.readline()
            if not out_line:
                return None
            try:
                return json.loads(out_line)
            except json.JSONDecodeError as e:
                print(f"JSON Error: {e} in '{out_line}'")
                return None

        # Test Cases
        cases = [
            {"input": "bp,bhfntkm", "expect_corrected": "избиратель", "desc": "Ticket 64: Dictionary word with comma"},
            {"input": "ghbdtn", "expect_corrected": "привет", "desc": "Simple conversion"},
        ]
        
        failed = 0
        passed = 0
        
        for case in cases:
            inp = case["input"]
            desc = case["desc"]
            print(f"Testing: {desc} ('{inp}') ... ", end="")
            
            res = query(inp)
            if not res:
                print("❌ No response (timeout)")
                failed += 1
                continue
                
            corrected = res.get("corrected")
            action = res.get("action")
            
            expected = case.get("expect_corrected")
            if expected and corrected == expected:
                print(f"✅ Passed ({action})")
                passed += 1
            else:
                print(f"❌ Failed. Got '{corrected}', Expected '{expected}'")
                failed += 1
                
        # Clean exit
        proc.stdin.write("EXIT\n")
        proc.stdin.flush()
        proc.wait(timeout=2)
        
        print(f"\nSummary: {passed} passed, {failed} failed.")
        return 1 if failed > 0 else 0
        
    except Exception as e:
        print(f"Error: {e}")
        return 1
    finally:
        # Always cleanup
        try:
            proc.kill()
        except:
            pass
        kill_existing_instances()

if __name__ == "__main__":
    sys.exit(run_repl_tests())
