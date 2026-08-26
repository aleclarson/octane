import { createRoot, flushSync, memo, type ComponentBody } from 'octane';

const ITEM_COUNT = 2_000;
const WORK_PER_ITEM = 2_000;
const WARMUP_RUNS = 3;
const UPDATE_SAMPLES = 15;
const UPDATES_PER_SAMPLE = 10;
const ITEMS = Array.from({ length: ITEM_COUNT }, (_, id) => id + 1);

interface ListProps {
	items: number[];
	seed: number;
}

type CaseKey = 'normalStable' | 'memoStable' | 'normalChanging';

interface CaseDefinition {
	changesChildProp: boolean;
	Component: ComponentBody<ListProps>;
	key: CaseKey;
	label: string;
}

// Use a bare callee instead of a member call to isolate the compiler's purity analysis.
const { imul } = Math;

function heavyCpuWork(value: number): number {
	let hash = value | 0;
	for (let i = 0; i < WORK_PER_ITEM; i++) {
		hash = imul(hash ^ i, 0x45d9f3b);
		hash = hash << 13 | hash >>> 19;
	}
	return hash >>> 0;
}

interface ItemProps {
	item: number;
	seed: number;
}

function HeavyItem(props: ItemProps) @{
	const result = '' + heavyCpuWork(props.item ^ props.seed);
	<li data-item={props.item} data-seed={props.seed}>{result}</li>
}
const MemoHeavyItem = memo(HeavyItem);

function NormalStableList(props: ListProps) @{
	<ul>
		@for (const item of props.items; key item) {
			<HeavyItem item={item} seed={0} />
		}
	</ul>
}

function MemoStableList(props: ListProps) @{
	<ul>
		@for (const item of props.items; key item) {
			<MemoHeavyItem item={item} seed={0} />
		}
	</ul>
}

function NormalChangingList(props: ListProps) @{
	<ul>
		@for (const item of props.items; key item) {
			<HeavyItem item={item} seed={props.seed} />
		}
	</ul>
}

const CASES: CaseDefinition[] = [
	{
		key: 'normalStable',
		label: 'Normal child, stable props',
		Component: NormalStableList,
		changesChildProp: false,
	},
	{
		key: 'memoStable',
		label: 'Memo child, stable props',
		Component: MemoStableList,
		changesChildProp: false,
	},
	{
		key: 'normalChanging',
		label: 'Normal child, changing prop',
		Component: NormalChangingList,
		changesChildProp: true,
	},
];

type BenchmarkSamples = Record<CaseKey, number[]>;

function createSamples(): BenchmarkSamples {
	return { normalStable: [], memoStable: [], normalChanging: [] };
}

function median(values: number[]): number {
	const sorted = [...values].sort((a, b) => a - b);
	const middle = sorted.length >> 1;
	return sorted[middle];
}

function formatSamples(samples: number[]): string {
	return samples.map((sample) => sample.toFixed(2)).join(', ');
}

interface UpdateState {
	definition: CaseDefinition;
	host: HTMLElement;
	items: number[];
	root: ReturnType<typeof createRoot>;
	seed: number;
}

function nextRenders(state: UpdateState): ListProps[] {
	const renders = new Array<ListProps>(UPDATES_PER_SAMPLE);
	let items = state.items;
	let seed = state.seed;
	for (let i = 0; i < UPDATES_PER_SAMPLE; i++) {
		items = [...items.slice(1), items[0]];
		seed++;
		renders[i] = { items, seed };
	}
	return renders;
}

function measureUpdateBatch(render: (props: ListProps) => void, renders: ListProps[]): number {
	const startedAt = performance.now();
	for (const props of renders) render(props);
	return (performance.now() - startedAt) / UPDATES_PER_SAMPLE;
}

function validateState(state: UpdateState): void {
	const rows = state.host.querySelectorAll('li');
	if (rows.length !== ITEM_COUNT) {
		throw new Error(`wrong row count: expected ${ITEM_COUNT}, received ${rows.length}`);
	}
	for (let i = 0; i < state.items.length; i++) {
		if (rows[i].getAttribute('data-item') !== '' + state.items[i]) {
			throw new Error(`wrong keyed item at index ${i}`);
		}
	}
	const expectedSeed = state.definition.changesChildProp ? state.seed : 0;
	if (rows[0].getAttribute('data-seed') !== '' + expectedSeed) {
		throw new Error(`wrong child seed: expected ${expectedSeed}`);
	}
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
		root.render(definition.Component, { items: ITEMS, seed: 0 });
		states.set(definition.key, { definition, host: caseHost, items: ITEMS, root, seed: 0 });
	}

	const samples = createSamples();
	const update = (definition: CaseDefinition, record: boolean) => {
		const state = states.get(definition.key)!;
		const renders = nextRenders(state);
		const elapsed = measureUpdateBatch(
			(props) => flushSync(() => state.root.render(definition.Component, props)),
			renders,
		);
		const last = renders[renders.length - 1];
		state.items = last.items;
		state.seed = last.seed;
		if (record) samples[definition.key].push(elapsed);
	};

	for (let i = 0; i < WARMUP_RUNS; i++) {
		forEachRotatedCase(i, (definition) => update(definition, false));
	}
	for (let i = 0; i < UPDATE_SAMPLES; i++) {
		forEachRotatedCase(i, (definition) => update(definition, true));
	}

	for (const state of states.values()) {
		validateState(state);
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
	const samples = measureUpdates(host);
	const normalStable = median(samples.normalStable);
	const memoStable = median(samples.memoStable);
	const normalChanging = median(samples.normalChanging);

	output.textContent = [
		`Normal child, stable props: ${normalStable.toFixed(2)} ms/update`,
		`Memo child, stable props: ${memoStable.toFixed(2)} ms/update`,
		`Normal child, changing prop: ${normalChanging.toFixed(2)} ms/update`,
		'',
		`Normal stable / memo stable: ${(normalStable / memoStable).toFixed(2)}x`,
		`Normal changing / normal stable: ${(normalChanging / normalStable).toFixed(2)}x`,
		'',
		'Update samples',
		`Normal child, stable props: ${formatSamples(samples.normalStable)} ms`,
		`Memo child, stable props: ${formatSamples(samples.memoStable)} ms`,
		`Normal child, changing prop: ${formatSamples(samples.normalChanging)} ms`,
	].join('\n');
}

function App() @{
	<main>
		<h1>Normal child auto-memoization</h1>
		<p>Every update rotates the keyed list. Only the changing control receives a new child prop.</p>
		<button onClick={runBenchmark}>Run benchmark</button>
		<pre id="results">Press the button to run.</pre>
		<div id="benchmark-host" hidden></div>
	</main>
}

const app = document.getElementById('app');
if (app === null) throw new Error('missing #app');
createRoot(app).render(App);
