# Backend Lint Cleanup Plan

Date: 2026-05-12

## Current Check Result

Command run:

```bash
cd backend
npx eslint src/ --format json -o eslint-report.json
npm run format:check
```

Initial status:

| Check | Result |
| --- | --- |
| ESLint full backend | Failing |
| Files with ESLint issues | 69 |
| Total ESLint messages | 483 |
| Prettier full backend | Failing |
| Files needing Prettier formatting | 104 |
| DB migration needed | No |

## Progress Update - 2026-05-12

Completed:

| Item | Before | After |
| --- | ---: | ---: |
| `import/no-unresolved` | 5 | 0 |
| `no-promise-executor-return` | 1 | 0 |
| `no-empty` | 0 | 0 |
| `radix` | 49 | 0 |
| Full ESLint messages | 483 | 124 |

Implementation notes:

- Replaced `bcrypt` imports with the already-installed `bcryptjs`.
- Added `exceljs` for NEIR export.
- Replaced AWS SDK v2 approach with `@aws-sdk/client-kms` v3 and basic AWS region validation.
- Removed the obsolete missing migration import from `src/seed/seed.js`; seed now calls the existing migration script.
- Refactored lock delivery retry delay through a `sleep()` helper.
- Tuned ESLint so intentional service-class methods do not block production cleanup.

Remaining active lint backlog:

| Rule | Count | Next action |
| --- | ---: | --- |
| `no-unused-vars` | 60 | Remove dead imports/locals carefully. |
| `no-await-in-loop` | 34 | Manual audit; keep retry/sequential flows with comments. |
| `no-use-before-define` | 9 | Move variables or convert to safe declarations. |
| `no-continue` | 7 | Manual readability cleanup. |
| `no-nested-ternary` | 5 | Replace with named variables/if blocks. |
| `default-param-last` | 3 | Review function signatures. |
| Small remaining style/safety rules | 6 | Handle with nearby module cleanup. |

## Rule Counts

| Rule | Count | Priority | Decision |
| --- | ---: | --- | --- |
| `class-methods-use-this` | 199 | Low | Last. Service classes intentionally use class structure; decide file-by-file or disable for service layer. |
| `no-unused-vars` | 60 | Medium | Remove dead imports/vars carefully. Keep required Express params with local disable comments. |
| `radix` | 49 | Low | Auto-fix safely with `eslint --fix`; verify tests/build afterward. |
| `no-use-before-define` | 40 | Medium | Move helper declarations above first use or convert safe helpers to function declarations. |
| `no-await-in-loop` | 34 | Medium | Audit manually. Retry loops stay sequential with comments; independent batch work can use `Promise.all`. |
| `import/order` | 20 | Low | Auto-fix/style pass. |
| `import/newline-after-import` | 18 | Low | Auto-fix/style pass. |
| `prefer-destructuring` | 16 | Low | Auto-fix or manual readability pass. |
| `object-shorthand` | 10 | Low | Auto-fix/style pass. |
| `no-continue` | 7 | Low | Manual readability pass or disable where loop intent is clearer. |
| `import/no-unresolved` | 5 | Critical | Fix before push/deploy. Runtime paths/packages are unresolved. |
| `no-nested-ternary` | 5 | Low | Manual readability pass. |
| `lines-between-class-members` | 4 | Low | Auto-fix/style pass. |
| `default-param-last` | 3 | Low | Manual API signature review. |
| Other single/low-count rules | 12 | Low/Medium | Handle with nearest module cleanup. |

## Critical Findings

### 1. `import/no-unresolved` x5

Current unresolved imports:

| File | Import | Recommended fix |
| --- | --- | --- |
| `src/modules/admin/adminController.js` | `bcrypt` | Use existing `bcryptjs` dependency unless native `bcrypt` is intentionally required. |
| `src/seed/seed.js` | `bcrypt` | Use existing `bcryptjs`. |
| `src/modules/fraud/fraudController.js` | `exceljs` | Install `exceljs` if NEIR export is a live feature, or guard/disable export until package is added. |
| `src/modules/devices/kmsSigningService.js` | `aws-sdk` | Install only if AWS KMS is used; otherwise guard optional AWS path and document it. |
| `src/seed/seed.js` | `../migrations/001_initial_schema` | Confirm whether this seed script is obsolete or restore the missing migration path. |

### 2. `no-promise-executor-return` x1

File:

`src/modules/lock/lockDeliveryService.js`

The retry delay uses `await new Promise(resolve => setTimeout(resolve, delay));`. This is simple to fix by wrapping the delay in a helper:

```js
function sleep(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}
```

Then call `await sleep(delay)`.

## Recommended Fix Order

1. Fix unresolved imports.
2. Fix `no-promise-executor-return`.
3. Run safe auto-fix for mechanical rules on backend only.
4. Re-run ESLint/Prettier and review the remaining diff.
5. Manually audit `no-await-in-loop`.
6. Clean unused variables and use-before-define by module.
7. Decide policy for `class-methods-use-this`.
8. Expand `lint:critical` only after each module is clean.

## Guardrail

Do not run full-project `prettier --write` and commit everything at once. Format one module group at a time to keep Git history readable and avoid hiding behavior changes inside a massive formatting diff.
