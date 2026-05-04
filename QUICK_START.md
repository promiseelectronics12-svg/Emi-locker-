# EMI Locker - Quick Start Guide

## What You Have Now

✅ **Graphify** - Knowledge graph tool (installed)
✅ **Autonomous Builder** - Two AI models working together
✅ **MiniMax-M2.7** - Worker model (code generation)
✅ **GPT-5-Nano** - Guard model (review & planning)

## Step 1: Run Autonomous Builder

### Option A: Double-click to run
```
Double-click: run_autonomous_build.bat
```

### Option B: Command line
```bash
python autonomous_builder.py --prd EMI_Locker_PRD_Final.docx
```

## Step 2: Watch the Magic Happen

The system will automatically:

1. **Guard Model** reads your PRD
2. **Guard Model** creates implementation plan
3. **Worker Model** implements each module
4. **Guard Model** reviews the code
5. **Worker Model** fixes any issues
6. Repeat until all modules are complete

## Step 3: Check Results

After completion, check:

- `implementation_plan.json` - The plan
- `build_log.md` - Detailed logs
- Generated code files

## Step 4: Use Graphify for Navigation

```bash
# Build knowledge graph
graphify .

# Query the codebase
graphify query "How does device enrollment work?"
```

## That's It!

No manual switching between models. Just run and wait.

---

## Need Help?

Run: `run_autonomous_build.bat --help`
