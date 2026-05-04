# EMI Locker Autonomous Builder

## Overview

This system allows two AI models to work together autonomously:
- **Guard Model**: Reviews, plans, ensures quality (Inspector)
- **Worker Model**: Implements, executes, generates code (Executor)

**No manual switching required** - the system runs automatically!

## Quick Start

### Option 1: Run Batch File (Easiest)
```bash
run_autonomous_build.bat
```

### Option 2: Run Python Script
```bash
python autonomous_builder.py --prd EMI_Locker_PRD_Final.docx
```

### Option 3: Custom Models
```bash
python autonomous_builder.py \
    --prd EMI_Locker_PRD_Final.docx \
    --guard-model gpt-5-nano \
    --worker-model minimax/MiniMax-M2.7
```

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                    AUTONOMOUS WORKFLOW                       │
└─────────────────────────────────────────────────────────────┘

Step 1: Guard reads PRD
        │
        ▼
Step 2: Guard creates implementation plan
        │
        ▼
Step 3: Worker implements each module
        │
        ▼
Step 4: Guard reviews implementation
        │
        ├── Approved → Next module
        │
        └── Issues found → Worker fixes issues
                │
                └── Loop until approved (max 3 iterations)
```

## Available Models

### Guard Models (Inspector)
- `opencode/gpt-5-nano` - Fast, good for planning
- `opencode/big-pickle` - Balanced performance
- `alibaba/qwen-max` - High quality analysis

### Worker Models (Executor)
- `minimax/MiniMax-M2.7` - Code generation specialist
- `minimax/MiniMax-M2.7-highspeed` - Faster version
- `minimax-coding-plan/MiniMax-M2.7` - Coding optimized

## Command Line Options

| Option | Default | Description |
|--------|---------|-------------|
| `--prd` | EMI_Locker_PRD_Final.docx | PRD file path |
| `--guard-model` | opencode/gpt-5-nano | Guard/Inspector model |
| `--worker-model` | minimax/MiniMax-M2.7 | Worker/Executor model |
| `--project-dir` | . | Project directory |
| `--max-iterations` | 3 | Max fix iterations per module |

## Output Files

After running, check these files:

1. **implementation_plan.json**
   - Guard's implementation plan
   - Module breakdown
   - Security requirements

2. **build_log.md**
   - Detailed build logs
   - Timestamps
   - Model outputs
   - Review results

3. **Generated Code Files**
   - Actual implementation
   - Organized by module

## Example Output

```
[2026-05-02 18:00:00] [INFO] ============================================================
[2026-05-02 18:00:00] [INFO] EMI LOCKER AUTONOMOUS BUILDER
[2026-05-02 18:00:00] [INFO] ============================================================
[2026-05-02 18:00:00] [INFO] Guard Model: opencode/gpt-5-nano
[2026-05-02 18:00:00] [INFO] Worker Model: minimax/MiniMax-M2.7
[2026-05-02 18:00:01] [INFO] Guard Model: Analyzing PRD...
[2026-05-02 18:00:15] [INFO] Guard Model: Plan created successfully
[2026-05-02 18:00:16] [INFO] Found 8 modules to implement
[2026-05-02 18:00:17] [INFO] Module 1/8: authentication
[2026-05-02 18:00:18] [INFO] Worker Model: Implementing module: authentication
[2026-05-02 18:01:30] [INFO] Worker Model: Module authentication implemented
[2026-05-02 18:01:31] [INFO] Guard Model: Reviewing implementation of authentication...
[2026-05-02 18:01:45] [INFO] Guard Model: Review complete - Status: approved
[2026-05-02 18:01:46] [INFO] ✓ Module authentication APPROVED (Score: 92)
...
```

## Troubleshooting

### Issue: "python not found"
**Solution**: Install Python 3.10+ from https://python.org

### Issue: "opencode not found"
**Solution**: Make sure OpenCode is installed and in PATH

### Issue: Model not available
**Solution**: Run `opencode models` to see available models

### Issue: Timeout errors
**Solution**: Increase timeout in autonomous_builder.py (line 85)

## Advanced Usage

### Run with Different Models for Different Tasks
```bash
# Use GPT for planning, Minimax for coding
python autonomous_builder.py \
    --guard-model opencode/gpt-5-nano \
    --worker-model minimax/MiniMax-M2.7-highspeed
```

### Run in Specific Directory
```bash
python autonomous_builder.py \
    --prd EMI_Locker_PRD_Final.docx \
    --project-dir ./emi-locker-project
```

### Increase Iterations for Complex Modules
```bash
python autonomous_builder.py \
    --prd EMI_Locker_PRD_Final.docx \
    --max-iterations 5
```

## Integration with Graphify

After running the autonomous builder, you can use Graphify to build a knowledge graph:

```bash
# Build knowledge graph from generated code
graphify .

# Watch for changes
graphify watch .

# Query the graph
graphify query "How does authentication work?"
```

## Next Steps

1. Run the autonomous builder
2. Review generated code in `build_log.md`
3. Test the implementation
4. Use Graphify for code navigation
5. Deploy to production

## Support

If you encounter issues:
1. Check `build_log.md` for error details
2. Verify model availability with `opencode models`
3. Ensure PRD file exists and is readable
4. Check Python and OpenCode installation

---

**Happy Building! 🚀**
