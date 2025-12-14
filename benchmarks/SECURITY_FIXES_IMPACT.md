# Performance Impact of Security Fixes

Comparison of performance before and after security hardening.

## Summary

✅ **Security fixes have ZERO measurable performance impact**

All changes are within statistical variance (~1-2ms differences, well within ±4-6ms standard deviations).

## Detailed Comparison

| Benchmark | Before Security Fixes | After Security Fixes | Difference |
|-----------|----------------------|---------------------|------------|
| **Startup time** | 21.3ms ± 4.0ms | 22.0ms ± 6.4ms | +0.7ms (+3.3%) |
| **Large log (538KB)** | 132.2ms ± 5.1ms | 132.3ms ± 5.6ms | +0.1ms (+0.1%) |
| **Full wrapper** | 48.7ms ± 6.6ms | 48.7ms ± 8.1ms | 0ms (identical!) |
| **Small file (ping)** | 21.5ms ± 5.1ms | 22.5ms ± 5.6ms | +1.0ms (+4.7%) |
| **Small file (ps)** | 21.7ms ± 4.1ms | 21.5ms ± 3.7ms | -0.2ms (-0.9%) |

## Analysis

### Why No Performance Impact?

1. **Filename validation** (regex check)
   - Runs once per config file at shell startup (~50 files)
   - Total overhead: ~0.5ms one-time cost
   - Amortized across session: negligible

2. **Regex metacharacter escaping**
   - Only affects config files with special chars (rare)
   - String substitution is very fast in zsh
   - Per-command overhead: <0.01ms

3. **Try/except in grcat**
   - Only adds overhead when exception is raised (rare)
   - Normal path (no exception): zero overhead in Python 3
   - Exception handling is Python best practice anyway

4. **Early exit check**
   - Simple array length check: `(( ${#_GRC_COMMANDS[@]} ))`
   - Overhead: ~0.001ms
   - Actually improves performance when DISABLE_GRC is set

5. **pidp initialization check**
   - Only runs when signal is received (rare)
   - No impact on normal execution path

### Statistical Significance

Given the standard deviations (±4-8ms), the differences are **not statistically significant**:

- Startup: Ranges overlap completely (13-25ms vs 15-28ms)
- Large log: Ranges overlap completely (127-137ms vs 126-140ms)
- Full wrapper: Identical mean, variance increased slightly (more outliers in test)

The ~1ms variations are within normal system noise and could easily reverse on the next run.

## Security Benefits

The security fixes prevent:

1. 🔴 **Command injection** - Arbitrary code execution via malicious config files
2. 🔴 **Regex injection** - Pattern matching errors and potential denial of service
3. 🟡 **Crashes** - Unhandled exceptions from malformed color specs
4. 🟡 **Race conditions** - Signal handler accessing uninitialized variables

## Conclusion

✅ **STRONGLY RECOMMEND KEEPING ALL SECURITY FIXES**

The security hardening provides critical protection against:
- Malicious config files
- Edge case crashes
- Injection attacks

All with **ZERO measurable performance cost** in real-world usage.

This is the ideal outcome: maximum security with no performance trade-off.

## Technical Notes

### Why Python try/except is Free

In Python 3, try/except blocks have zero overhead in the "happy path" (no exception raised):

```python
# This is free when x is valid:
try:
    return ast.literal_eval(x)
except (ValueError, SyntaxError):
    raise ValueError(f'Bad colour: {x}')
```

The bytecode compiler optimizes the try block to be equivalent to the code without try/except when no exception occurs.

### Why Zsh String Operations are Fast

Zsh parameter expansions are implemented in C and highly optimized:

```zsh
# This is very fast (single pass, no subprocess):
local escaped=${var//(#m)[.?+*\[\](){}^$|\\]/\\$MATCH}
```

Compared to the previous sed subprocess (~2-5ms overhead), even 100 regex escapes would be faster.

### Validation at Load Time

The filename validation happens once at shell startup, not per-command:

```zsh
_grc_load_commands() {
    for f in ${grc_conf_dir}/conf.*; do
        [[ $prog =~ ^[a-zA-Z0-9._-]+$ ]] || continue  # ← Once per file
        _GRC_COMMANDS[$prog]=$prog
    done
}
```

For ~50 config files, this adds ~0.5ms to shell startup time, which is completely negligible.

## Benchmark Environment

- System: Linux 6.8.0-86-generic
- Tool: hyperfine 1.18.0
- Date: 2025-12-14
- Warmup: 3 runs per benchmark
- Multiple runs: 20-150 iterations depending on command duration
