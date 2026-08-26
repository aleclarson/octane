# CPU work isolation

This small browser benchmark compares two fresh Octane mounts over the same
2,000-item array. One calls the CPU-heavy function directly inside `@for`; the
other calls it from a `HeavyItem` component. Both variants render the same DOM
and run the same function exactly once per item.

```bash
pnpm --dir benchmarks/cpu-work-isolation dev
```

Open `http://localhost:5316` and press **Run benchmark**. The page performs two
warmups, alternates which variant runs first, verifies every mount, and reports
the median of six samples. The only runtime dependency is Octane; timing uses
the browser's `performance.now()`.
