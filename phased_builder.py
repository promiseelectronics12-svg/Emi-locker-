#!/usr/bin/env python3
"""
EMI Locker Phased Builder with Checkpoints
===========================================
Two AI models work together in phases with user verification.

Phases:
  Phase 1: 50% - Core architecture + Security (Auto)
  Checkpoint: User verifies
  Phase 2: 25% - Backend + API (Auto)
  Checkpoint: User verifies
  Phase 3: 25% - Frontend + Mobile (Auto)
  Final output

Usage:
    python phased_builder.py --prd EMI_Locker_PRD_Final.docx
    python phased_builder.py --prd EMI_Locker_PRD_Final.docx --phase 1
    python phased_builder.py --prd EMI_Locker_PRD_Final.docx --resume
"""

import subprocess
import argparse
import json
import os
import sys
from pathlib import Path
from datetime import datetime
import time
import pickle

class PhasedBuilder:
    def __init__(self, guard_model: str, worker_model: str, project_dir: str):
        self.guard_model = guard_model
        self.worker_model = worker_model
        self.project_dir = Path(project_dir)
        self.log_file = self.project_dir / "build_log.md"
        self.state_file = self.project_dir / "build_state.pkl"
        self.checkpoint_file = self.project_dir / "checkpoint.json"
        
        # Phase definitions
        self.phases = {
            1: {
                "name": "Core Architecture & Security",
                "progress": 50,
                "modules": ["authentication", "security", "device-binding", "key-management"],
                "description": "Foundation layer - Device Owner, FRP, Certificate Pinning"
            },
            2: {
                "name": "Backend & API",
                "progress": 25,
                "modules": ["api-endpoints", "database", "firebase", "emi-logic"],
                "description": "Server-side - Node.js, PostgreSQL, Firebase"
            },
            3: {
                "name": "Frontend & Mobile",
                "progress": 25,
                "modules": ["admin-panel", "dealer-app", "user-app", "integration"],
                "description": "Client-side - React, Flutter, Kotlin"
            }
        }
        
        # Load or initialize state
        self.state = self.load_state()
    
    def load_state(self) -> dict:
        """Load build state from file"""
        if self.state_file.exists():
            try:
                with open(self.state_file, "rb") as f:
                    return pickle.load(f)
            except:
                pass
        
        return {
            "current_phase": 1,
            "completed_phases": [],
            "completed_modules": [],
            "plan": None,
            "started_at": datetime.now().isoformat()
        }
    
    def save_state(self):
        """Save build state to file"""
        with open(self.state_file, "wb") as f:
            pickle.dump(self.state, f)
    
    def log(self, message: str, level: str = "INFO"):
        """Log message"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_entry = f"[{timestamp}] [{level}] {message}"
        print(log_entry)
        
        with open(self.log_file, "a", encoding="utf-8") as f:
            f.write(log_entry + "\n")
    
    def run_opencode(self, model: str, message: str, timeout: int = 300) -> str:
        """Run OpenCode with specific model"""
        cmd = ["opencode", "run", "-m", model, message]
        
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                cwd=str(self.project_dir),
                timeout=timeout
            )
            
            if result.returncode == 0:
                return result.stdout
            else:
                self.log(f"OpenCode error: {result.stderr[:200]}", "ERROR")
                return None
                
        except subprocess.TimeoutExpired:
            self.log("Command timed out", "ERROR")
            return None
        except Exception as e:
            self.log(f"Exception: {str(e)}", "ERROR")
            return None
    
    def guard_create_plan(self, prd_path: str) -> dict:
        """Guard creates implementation plan"""
        self.log("GUARD: Reading PRD and creating plan...")
        
        message = f"""
Read the PRD at: {prd_path}

Create an implementation plan for EMI Locker with these phases:

Phase 1 (50%): Core Architecture & Security
  - authentication (JWT + 2FA)
  - security (certificate pinning, command signing)
  - device-binding (IMEI + Serial + SoC)
  - key-management (activation keys)

Phase 2 (25%): Backend & API
  - api-endpoints (REST API)
  - database (PostgreSQL schema)
  - firebase (realtime sync)
  - emi-logic (payment tracking)

Phase 3 (25%): Frontend & Mobile
  - admin-panel (React)
  - dealer-app (Flutter)
  - user-app (Kotlin)
  - integration (testing)

Output JSON:
{{
    "phases": {{
        "1": {{"modules": ["authentication", "security", "device-binding", "key-management"]}},
        "2": {{"modules": ["api-endpoints", "database", "firebase", "emi-logic"]}},
        "3": {{"modules": ["admin-panel", "dealer-app", "user-app", "integration"]}}
    }},
    "tech_stack": {{"backend": "Node.js", "frontend": "React", "mobile": ["Flutter", "Kotlin"]}},
    "security": ["certificate-pinning", "command-signing", "device-binding", "frp"]
}}
"""
        
        result = self.run_opencode(self.guard_model, message)
        
        if result:
            try:
                json_start = result.find('{')
                json_end = result.rfind('}') + 1
                if json_start != -1 and json_end != -1:
                    plan = json.loads(result[json_start:json_end])
                    self.log("GUARD: Plan created successfully")
                    return plan
            except json.JSONDecodeError:
                self.log("GUARD: Failed to parse plan", "ERROR")
        
        return None
    
    def worker_implement_module(self, module: str, phase: int) -> str:
        """Worker implements a module"""
        self.log(f"WORKER: Implementing {module} (Phase {phase})...")
        
        message = f"""
Implement the '{module}' module for EMI Locker.

Context: This is Phase {phase} - {self.phases[phase]['name']}

Create actual code files with:
- Proper file structure
- Error handling
- Comments
- Security best practices

Module: {module}
Phase: {phase}

Start implementing now. Create all necessary files.
"""
        
        result = self.run_opencode(self.worker_model, message, timeout=600)
        
        if result:
            self.log(f"WORKER: {module} implemented")
            return result
        else:
            self.log(f"WORKER: Failed to implement {module}", "ERROR")
            return None
    
    def guard_review_module(self, module: str, implementation: str) -> dict:
        """Guard reviews implementation"""
        self.log(f"GUARD: Reviewing {module}...")
        
        message = f"""
Review the implementation of '{module}'.

Implementation (first 1500 chars):
{implementation[:1500]}

Check for:
1. Security vulnerabilities
2. Code quality
3. Error handling
4. Best practices

Output JSON:
{{
    "module": "{module}",
    "status": "approved" or "needs_changes",
    "score": 0-100,
    "issues": []
}}
"""
        
        result = self.run_opencode(self.guard_model, message)
        
        if result:
            try:
                json_start = result.find('{')
                json_end = result.rfind('}') + 1
                if json_start != -1 and json_end != -1:
                    review = json.loads(result[json_start:json_end])
                    self.log(f"GUARD: Review complete - {review.get('status', 'unknown')}")
                    return review
            except json.JSONDecodeError:
                self.log("GUARD: Failed to parse review", "ERROR")
        
        return None
    
    def run_phase(self, phase: int, prd_path: str) -> bool:
        """Run a complete phase"""
        phase_info = self.phases[phase]
        
        self.log(f"\n{'='*60}")
        self.log(f"PHASE {phase}: {phase_info['name']}")
        self.log(f"Progress: {phase_info['progress']}%")
        self.log(f"Modules: {', '.join(phase_info['modules'])}")
        self.log(f"{'='*60}\n")
        
        modules = phase_info['modules']
        
        for i, module in enumerate(modules, 1):
            self.log(f"\n--- Module {i}/{len(modules)}: {module} ---")
            
            # Worker implements
            implementation = self.worker_implement_module(module, phase)
            
            if not implementation:
                self.log(f"Failed to implement {module}. Continuing...", "WARNING")
                continue
            
            # Guard reviews
            review = self.guard_review_module(module, implementation)
            
            if review and review.get("status") == "approved":
                self.log(f"✓ {module} APPROVED (Score: {review.get('score', 'N/A')})")
                self.state["completed_modules"].append(module)
            else:
                self.log(f"⚠ {module} needs attention")
        
        # Mark phase complete
        self.state["completed_phases"].append(phase)
        self.save_state()
        
        self.log(f"\n✓ Phase {phase} Complete!")
        return True
    
    def save_checkpoint(self, phase: int, progress: int):
        """Save checkpoint for user verification"""
        checkpoint = {
            "phase": phase,
            "progress": progress,
            "completed_modules": self.state["completed_modules"],
            "timestamp": datetime.now().isoformat(),
            "next_phase": phase + 1 if phase < 3 else None
        }
        
        with open(self.checkpoint_file, "w") as f:
            json.dump(checkpoint, f, indent=2)
        
        self.log(f"Checkpoint saved: {self.checkpoint_file}")
    
    def run_full_build(self, prd_path: str, start_phase: int = 1):
        """Run full build with checkpoints"""
        self.log("="*60)
        self.log("EMI LOCKER PHASED BUILDER")
        self.log("="*60)
        self.log(f"Guard Model: {self.guard_model}")
        self.log(f"Worker Model: {self.worker_model}")
        self.log(f"Starting Phase: {start_phase}")
        self.log("="*60)
        
        # Step 1: Guard creates plan (if starting fresh)
        if start_phase == 1:
            plan = self.guard_create_plan(prd_path)
            if plan:
                self.state["plan"] = plan
                self.save_state()
                
                # Save plan to file
                plan_file = self.project_dir / "implementation_plan.json"
                with open(plan_file, "w") as f:
                    json.dump(plan, f, indent=2)
        
        # Step 2: Run phases with checkpoints
        for phase in range(start_phase, 4):
            success = self.run_phase(phase, prd_path)
            
            if not success:
                self.log(f"Phase {phase} failed. Stopping.", "ERROR")
                return False
            
            # Save checkpoint after each phase
            progress = sum(self.phases[p]["progress"] for p in range(1, phase + 1))
            self.save_checkpoint(phase, progress)
            
            # Ask for verification (except after last phase)
            if phase < 3:
                self.log(f"\n{'*'*60}")
                self.log(f"CHECKPOINT: {progress}% Complete")
                self.log(f"Phase {phase} done. Verify results before Phase {phase+1}")
                self.log(f"Run: python phased_builder.py --resume")
                self.log(f"{'*'*60}\n")
                
                # In automated mode, continue automatically
                # In interactive mode, wait for user
                if not self.is_automated():
                    input("Press Enter to continue to next phase...")
        
        self.log("\n" + "="*60)
        self.log("BUILD COMPLETE - 100%")
        self.log("="*60)
        
        return True
    
    def is_automated(self) -> bool:
        """Check if running in automated mode"""
        return os.environ.get("AUTOMATED") == "1" or not sys.stdin.isatty()
    
    def resume_build(self, prd_path: str):
        """Resume from checkpoint"""
        if not self.checkpoint_file.exists():
            self.log("No checkpoint found. Starting fresh.", "WARNING")
            return self.run_full_build(prd_path)
        
        with open(self.checkpoint_file, "r") as f:
            checkpoint = json.load(f)
        
        next_phase = checkpoint.get("next_phase")
        if not next_phase:
            self.log("Build already complete!")
            return True
        
        self.log(f"Resuming from Phase {next_phase}")
        return self.run_full_build(prd_path, start_phase=next_phase)


def main():
    parser = argparse.ArgumentParser(description="EMI Locker Phased Builder")
    parser.add_argument("--prd", required=True, help="PRD file path")
    parser.add_argument("--guard-model", default="opencode/gpt-5-nano")
    parser.add_argument("--worker-model", default="minimax/MiniMax-M2.7")
    parser.add_argument("--project-dir", default=".")
    parser.add_argument("--phase", type=int, help="Start from specific phase")
    parser.add_argument("--resume", action="store_true", help="Resume from checkpoint")
    parser.add_argument("--auto", action="store_true", help="Run all phases automatically")
    
    args = parser.parse_args()
    
    # Set automated mode
    if args.auto:
        os.environ["AUTOMATED"] = "1"
    
    builder = PhasedBuilder(
        guard_model=args.guard_model,
        worker_model=args.worker_model,
        project_dir=args.project_dir
    )
    
    if args.resume:
        success = builder.resume_build(args.prd)
    elif args.phase:
        success = builder.run_full_build(args.prd, start_phase=args.phase)
    else:
        success = builder.run_full_build(args.prd)
    
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
