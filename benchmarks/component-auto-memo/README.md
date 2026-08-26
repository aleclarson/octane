# Component auto-memoization

This production-browser benchmark isolates one compiler question: does Octane
re-execute a normal child component when a parent update preserves the child's
type, keyed identity, and props?

It compares three keyed 2,000-item lists:

- a normal child whose `item` and `seed` props stay unchanged;
- the same stable child wrapped in `memo()` as the bailout control;
- the normal child with a changing `seed` prop as the recomputation control.

Every update moves the first array item to the end. The benchmark uses CPU time
as the signal and does not add render counters inside the pure workload.

```bash
pnpm --dir benchmarks/component-auto-memo dev
```

Open `http://localhost:5317` and press **Run benchmark**. A production build can
be served with `pnpm --dir benchmarks/component-auto-memo build` followed by
`pnpm --dir benchmarks/component-auto-memo preview`.
