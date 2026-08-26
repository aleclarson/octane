import { createRoot, flushSync, memo, type ComponentBody } from 'octane';

const ITEM_COUNT = 2_000;
const WORK_PER_ITEM = 2_000;
const WARMUP_RUNS = 2;
const MEASURED_RUNS = 6;
const UPDATE_SAMPLES = 12;
const UPDATES_PER_SAMPLE = 10;
const ITEMS = Array.from({ length: ITEM_COUNT }, (_, id) => id + 1);

interface ListProps {
	items: number[];
	seed: number;
}

type CaseKey =
	| 'inlineDeterministic'
	| 'normalDeterministic'
	| 'memoDeterministic'
	| 'inlineRandom'
	| 'normalRandom'
	| 'memoRandom';

interface CaseDefinition {
	Component: ComponentBody<ListProps>;
	key: CaseKey;
	label: string;
}

// Use a bare callee instead of a member call to isolate the compiler's purity analysis.
const { imul } = Math;

// Integer arithmetic keeps the workload deterministic and prevents a browser
// from replacing the loop with a platform math call.
function heavyCpuWork(value: number): number {
	let hash = value | 0;
	for (let i = 0; i < WORK_PER_ITEM; i++) {
		hash = imul(hash ^ i, 0x45d9f3b);
		hash = hash << 13 | hash >>> 19;
	}
	return hash >>> 0;
}

function InlineList(props: ListProps) @{
	<ul>
		@for (const item of props.items; key item) {
			<li data-item={item}>{'' + heavyCpuWork(item)}</li>
		}
	</ul>
}

function InlineRandomSeedList(props: ListProps) @{
	<ul>
		@for (const item of props.items; key item) {
			<li data-item={item}>{'' + heavyCpuWork(item ^ props.seed)}</li>
		}
	</ul>
}

function HeavyItem(props: { item: number }) @{
	const result = '' + heavyCpuWork(props.item);
	<li data-item={props.item}>{result}</li>
}
const IsolatedHeavyItem = memo(HeavyItem);

function RandomSeedHeavyItem(props: { item: number; seed: number }) @{
	const result = '' + heavyCpuWork(props.item ^ props.seed);
	<li data-item={props.item}>{result}</li>
}
const IsolatedRandomSeedHeavyItem = memo(RandomSeedHeavyItem);

function NormalComponentList(props: ListProps) @{
	<ul>
		@for (const item of props.items; key item) {
			<HeavyItem item={item} />
		}
	</ul>
}

function MemoComponentList(props: ListProps) @{
	<ul>
		@for (const item of props.items; key item) {
			<IsolatedHeavyItem item={item} />
		}
	</ul>
}

function NormalRandomSeedComponentList(props: ListProps) @{
	<ul>
		@for (const item of props.items; key item) {
			<RandomSeedHeavyItem item={item} seed={props.seed} />
		}
	</ul>
}

function MemoRandomSeedComponentList(props: ListProps) @{
	<ul>
		@for (const item of props.items; key item) {
			<IsolatedRandomSeedHeavyItem item={item} seed={props.seed} />
		}
	</ul>
}

const CASES: CaseDefinition[] = [
	{ key: 'inlineDeterministic', label: 'Inline @for, deterministic', Component: InlineList },
	{
		key: 'normalDeterministic',
		label: 'Normal component, deterministic',
		Component: NormalComponentList,
	},
	{
		key: 'memoDeterministic',
		label: 'Memo component, deterministic',
		Component: MemoComponentList,
	},
	{ key: 'inlineRandom', label: 'Inline @for, random seed', Component: InlineRandomSeedList },
	{
		key: 'normalRandom',
		label: 'Normal component, random seed',
		Component: NormalRandomSeedComponentList,
	},
	{
		key: 'memoRandom',
		label: 'Memo component, random seed',
		Component: MemoRandomSeedComponentList,
	},
];

function randomSeed(): number {
	return Math.random() * 0x1_0000_0000 >>> 0;
}

function median(values: number[]): number {
	const sorted = [...values].sort((a, b) => a - b);
	const middle = sorted.length >> 1;
	return (sorted[middle - 1] + sorted[middle]) / 2;
}

function measureMount(host: HTMLElement, Component: ComponentBody<ListProps>): number {
	const root = createRoot(host);
	const startedAt = performance.now();
	root.render(Component, { items: ITEMS, seed: randomSeed() });
	const elapsed = performance.now() - startedAt;

	if (host.querySelectorAll('li').length !== ITEM_COUNT) {
		throw new Error('benchmark did not render every item');
	}

	root.unmount();
	return elapsed;
}

function formatSamples(samples: number[]): string {
	return samples.map((sample) => sample.toFixed(2)).join(', ');
}

interface CaseSamples {
	times: number[];
}

type BenchmarkSamples = Record<CaseKey, CaseSamples>;

function createSamples(): BenchmarkSamples {
	return {
		inlineDeterministic: { times: [] },
		normalDeterministic: { times: [] },
		memoDeterministic: { times: [] },
		inlineRandom: { times: [] },
		normalRandom: { times: [] },
		memoRandom: { times: [] },
	};
}

function shiftedRenders(items: number[]): ListProps[] {
	const renders = new Array<ListProps>(UPDATES_PER_SAMPLE);
	let next = items;
	for (let i = 0; i < UPDATES_PER_SAMPLE; i++) {
		next = [...next.slice(1), next[0]];
		renders[i] = { items: next, seed: randomSeed() };
	}
	return renders;
}

function measureUpdateBatch(render: (props: ListProps) => void, renders: ListProps[]) {
	const startedAt = performance.now();
	for (const props of renders) render(props);
	return (performance.now() - startedAt) / UPDATES_PER_SAMPLE;
}

function validateOrder(host: HTMLElement, items: number[]): void {
	const rows = host.querySelectorAll('li');
	if (rows.length !== ITEM_COUNT) {
		throw new Error(`wrong keyed row count: expected ${ITEM_COUNT}, received ${rows.length}`);
	}
	for (let i = 0; i < items.length; i++) {
		const actual = rows[i].getAttribute('data-item');
		if (actual !== '' + items[i]) {
			throw new Error(`wrong keyed item at index ${i}: expected ${items[i]}, received ${actual}`);
		}
	}
}

interface UpdateState {
	definition: CaseDefinition;
	host: HTMLElement;
	items: number[];
	root: ReturnType<typeof createRoot>;
}

function forEachRotatedCase(offset: number, visit: (definition: CaseDefinition) => void): void {
	for (let i = 0; i < CASES.length; i++) visit(CASES[(i + offset) % CASES.length]);
}

function measureUpdates(host: HTMLElement): BenchmarkSamples {
	const states = new Map<CaseKey, UpdateState>();
	for (const definition of CASES) {
		const caseHost = document.createElement('div');
		host.append(caseHost);
		const root = createRoot(caseHost);
		root.render(definition.Component, { items: ITEMS, seed: randomSeed() });
		states.set(definition.key, { definition, host: caseHost, items: ITEMS, root });
	}

	const samples = createSamples();
	const update = (definition: CaseDefinition, record: boolean) => {
		const state = states.get(definition.key)!;
		const renders = shiftedRenders(state.items);
		const elapsed = measureUpdateBatch(
			(props) => flushSync(() => state.root.render(definition.Component, props)),
			renders,
		);
		state.items = renders[renders.length - 1].items;
		if (record) samples[definition.key].times.push(elapsed);
	};

	for (let i = 0; i < WARMUP_RUNS; i++) {
		forEachRotatedCase(i, (definition) => update(definition, false));
	}
	for (let i = 0; i < UPDATE_SAMPLES; i++) {
		forEachRotatedCase(i, (definition) => update(definition, true));
	}

	for (const state of states.values()) {
		validateOrder(state.host, state.items);
		state.root.unmount();
	}
	return samples;
}

async function runBenchmark(): Promise<void> {
	const host = document.getElementById('benchmark-host');
	const output = document.getElementById('results');
	if (host === null || output === null) throw new Error('missing benchmark elements');

	output.textContent = 'Running...';
	await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));

	for (let i = 0; i < WARMUP_RUNS; i++) {
		forEachRotatedCase(i, (definition) => measureMount(host, definition.Component));
	}

	const mounts = createSamples();
	for (let i = 0; i < MEASURED_RUNS; i++) {
		forEachRotatedCase(i, (definition) => {
			mounts[definition.key].times.push(measureMount(host, definition.Component));
		});
	}
	const updates = measureUpdates(host);

	const lines = ['Mount'];
	for (const definition of CASES) {
		lines.push(`${definition.label}: ${median(mounts[definition.key].times).toFixed(2)} ms`);
	}
	lines.push('', 'Shift first item to end');
	for (const definition of CASES) {
		const samples = updates[definition.key];
		lines.push(`${definition.label}: ${median(samples.times).toFixed(2)} ms/update`);
	}
	lines.push(
		'',
		`Random / deterministic inline: ${(median(updates.inlineRandom.times) /
			median(updates.inlineDeterministic.times)).toFixed(2)}x`,
		`Random / deterministic normal component: ${(median(updates.normalRandom.times) /
			median(updates.normalDeterministic.times)).toFixed(2)}x`,
		`Random / deterministic memo component: ${(median(updates.memoRandom.times) /
			median(updates.memoDeterministic.times)).toFixed(2)}x`,
		'',
		'Update samples',
	);
	for (const definition of CASES) {
		lines.push(`${definition.label}: ${formatSamples(updates[definition.key].times)} ms`);
	}
	output.textContent = lines.join('\n');
}

function App() @{
	<main>
		<h1>CPU work inside @for vs an isolated component</h1>
		<p>
			{'Each fresh mount renders ' + ITEM_COUNT +
				' items and runs the same CPU function once per item.'}
		</p>
		<p>Updates move the first keyed item to the end and give seeded cases a new random seed.</p>
		<button onClick={runBenchmark}>Run benchmark</button>
		<pre id="results">Press the button to run.</pre>
		<div id="benchmark-host" hidden></div>
	</main>
}

const app = document.getElementById('app');
if (app === null) throw new Error('missing #app');
createRoot(app).render(App);
