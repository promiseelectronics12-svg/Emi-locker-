# How Two Models Work Together

## The Big Question: How Do Two Models Run Together?

Answer: **They don't run at the same time. They take turns automatically.**

```
┌─────────────────────────────────────────────────────────────────┐
│                    HOW IT ACTUALLY WORKS                        │
└─────────────────────────────────────────────────────────────────┘

STEP 1: You run the script
        │
        ▼
STEP 2: Script calls OpenCode with GUARD model
        │ "Read PRD and create plan"
        │
        ▼
STEP 3: Guard model responds with plan
        │
        ▼
STEP 4: Script calls OpenCode with WORKER model
        │ "Implement authentication module"
        │
        ▼
STEP 5: Worker model responds with code
        │
        ▼
STEP 6: Script calls OpenCode with GUARD model
        │ "Review this code"
        │
        ▼
STEP 7: Guard model responds with review
        │
        ▼
STEP 8: Repeat for next module
        │
        ▼
STEP 9: Checkpoint - User verifies
        │
        ▼
STEP 10: Continue to next phase
```

## Visual Example

```
┌─────────────────────────────────────────────────────────────────┐
│                    PHASE 1 (50% Complete)                       │
└─────────────────────────────────────────────────────────────────┘

Time    Model       Action
─────   ─────       ──────
0:00    GUARD       "Reading PRD..."
0:15    GUARD       "Creating plan..."
0:30    GUARD       "Plan ready. Starting implementation."
0:31    WORKER      "Implementing authentication..."
1:30    WORKER      "Authentication done."
1:31    GUARD       "Reviewing authentication..."
1:45    GUARD       "Score: 92/100. Approved."
1:46    WORKER      "Implementing security..."
2:45    WORKER      "Security done."
2:46    GUARD       "Reviewing security..."
3:00    GUARD       "Score: 88/100. Approved."
3:01    WORKER      "Implementing device-binding..."
4:00    WORKER      "Device-binding done."
4:01    GUARD       "Reviewing device-binding..."
4:15    GUARD       "Score: 90/100. Approved."
4:16    WORKER      "Implementing key-management..."
5:15    WORKER      "Key-management done."
5:16    GUARD       "Reviewing key-management..."
5:30    GUARD       "Score: 85/100. Approved."
5:31    ─────       "PHASE 1 COMPLETE (50%)"
5:32    ─────       "CHECKPOINT: Verify results"
```

## The Key Insight

**The models DON'T run simultaneously.** They take turns:

```
┌─────────────────────────────────────────────────────────────────┐
│                    TURN-BASED SYSTEM                            │
└─────────────────────────────────────────────────────────────────┘

Turn 1: GUARD analyzes → saves result
Turn 2: WORKER implements → saves result
Turn 3: GUARD reviews → saves result
Turn 4: WORKER fixes → saves result
Turn 5: GUARD approves → moves to next module
...repeat...

Each turn is a separate OpenCode call.
The script orchestrates the turns automatically.
```

## How OpenCode Calls Work

```python
# Turn 1: Guard creates plan
result1 = subprocess.run(["opencode", "run", "-m", "gpt-5-nano", "Create plan..."])

# Turn 2: Worker implements
result2 = subprocess.run(["opencode", "run", "-m", "minimax/MiniMax-M2.7", "Implement..."])

# Turn 3: Guard reviews
result3 = subprocess.run(["opencode", "run", "-m", "gpt-5-nano", "Review..."])
```

**Each call is independent.** The script passes context between them.

## Checkpoints (User Verification)

```
┌─────────────────────────────────────────────────────────────────┐
│                    CHECKPOINT SYSTEM                            │
└─────────────────────────────────────────────────────────────────┘

Phase 1 (50%) → CHECKPOINT → User verifies → Phase 2 (25%)
                              │
                              ▼
                    "Looks good! Continue."
                              │
                              ▼
Phase 2 (25%) → CHECKPOINT → User verifies → Phase 3 (25%)
                              │
                              ▼
                    "Approved! Continue."
                              │
                              ▼
Phase 3 (25%) → COMPLETE → Final output
```

## What You See

```
$ python phased_builder.py --prd EMI_Locker_PRD_Final.docx

[2026-05-02 18:00:00] GUARD: Reading PRD...
[2026-05-02 18:00:15] GUARD: Plan created
[2026-05-02 18:00:16] WORKER: Implementing authentication...
[2026-05-02 18:01:30] WORKER: Done
[2026-05-02 18:01:31] GUARD: Reviewing... Score: 92
[2026-05-02 18:01:45] ✓ authentication APPROVED
[2026-05-02 18:01:46] WORKER: Implementing security...
...

CHECKPOINT: 50% Complete
Verify results before Phase 2
Press Enter to continue...
```

## Summary

| Question | Answer |
|----------|--------|
| Do models run at same time? | ❌ No, they take turns |
| How do they communicate? | Script passes context |
| Who orchestrates? | Python script |
| How fast? | ~5-10 min per module |
| Can I pause? | ✅ Yes, at checkpoints |
| Can I resume? | ✅ Yes, from checkpoint |

## The Magic

**The Python script is the conductor.** It:
1. Calls Guard when needed
2. Calls Worker when needed
3. Passes results between them
4. Saves state to files
5. Pauses at checkpoints

**You just run the script and wait!**
