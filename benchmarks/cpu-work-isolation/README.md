# CPU work isolation

This small browser benchmark compares two Octane list shapes over the same
2,000-item array. One calls the CPU-heavy function directly inside `@for`; the
other calls it from a memoized `HeavyItem` component. It measures fresh mounts
and keyed updates that move the first array item to the end on every render.

```bash
pnpm --dir benchmarks/cpu-work-isolation dev
```

Open `http://localhost:5316` and press **Run benchmark**. The page warms up both
variants, alternates which one runs first, verifies the rendered item count and
order, and reports median mount and update timings. Update samples batch ten
renders to reduce timer noise and also report heavy-function calls per render.
The only runtime dependency is Octane; timing uses the browser's
`performance.now()`.
