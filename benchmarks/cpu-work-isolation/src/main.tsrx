import { createRoot, type ComponentBody } from 'octane';

const ITEM_COUNT = 2_000;
const WORK_PER_ITEM = 2_000;
const WARMUP_RUNS = 2;
const MEASURED_RUNS = 6;
const ITEMS = Array.from({ length: ITEM_COUNT }, (_, id) => id + 1);

interface ListProps {
	items: number[];
}

let heavyCallCount = 0;

// Integer arithmetic keeps the workload deterministic and prevents a browser
// from replacing the loop with a platform math call.
function heavyCpuWork(value: number): number {
	heavyCallCount++;
	let hash = value | 0;
	for (let i = 0; i < WORK_PER_ITEM; i++) {
		hash = Math.imul(hash ^ i, 0x45d9f3b);
		hash = hash << 13 | hash >>> 19;
	}
	return hash >>> 0;
}

function InlineList(props: ListProps) @{
	<ul>
		@for (const item of props.items; key item) {
			<li>{'' + heavyCpuWork(item)}</li>
		}
	</ul>
}

function HeavyItem(props: { item: number }) @{
	const result = '' + heavyCpuWork(props.item);
	<li>{result}</li>
}

function IsolatedList(props: ListProps) @{
	<ul>
		@for (const item of props.items; key item) {
			<HeavyItem item={item} />
		}
	</ul>
}

function median(values: number[]): number {
	const sorted = [...values].sort((a, b) => a - b);
	const middle = sorted.length >> 1;
	return (sorted[middle - 1] + sorted[middle]) / 2;
}

function measureMount(host: HTMLElement, Component: ComponentBody<ListProps>): number {
	const root = createRoot(host);
	const callsBefore = heavyCallCount;
	const startedAt = performance.now();
	root.render(Component, { items: ITEMS });
	const elapsed = performance.now() - startedAt;

	if (
		heavyCallCount - callsBefore !== ITEM_COUNT || host.querySelectorAll('li').length !== ITEM_COUNT
	) {
		throw new Error('benchmark did not render and compute every item');
	}

	root.unmount();
	return elapsed;
}

function formatSamples(samples: number[]): string {
	return samples.map((sample) => sample.toFixed(2)).join(', ');
}

async function runBenchmark(): Promise<void> {
	const host = document.getElementById('benchmark-host');
	const output = document.getElementById('results');
	if (host === null || output === null) throw new Error('missing benchmark elements');

	output.textContent = 'Running...';
	await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));

	for (let i = 0; i < WARMUP_RUNS; i++) {
		measureMount(host, InlineList);
		measureMount(host, IsolatedList);
	}

	const inline: number[] = [];
	const isolated: number[] = [];
	for (let i = 0; i < MEASURED_RUNS; i++) {
		// Alternate first position so one case does not always get the warmer CPU.
		if ((i & 1) === 0) {
			inline.push(measureMount(host, InlineList));
			isolated.push(measureMount(host, IsolatedList));
		} else {
			isolated.push(measureMount(host, IsolatedList));
			inline.push(measureMount(host, InlineList));
		}
	}

	output.textContent = [
		`Inline @for median: ${median(inline).toFixed(2)} ms`,
		`Isolated component median: ${median(isolated).toFixed(2)} ms`,
		'',
		`Inline samples: ${formatSamples(inline)} ms`,
		`Isolated samples: ${formatSamples(isolated)} ms`,
	].join('\n');
}

function App() @{
	<main>
		<h1>CPU work inside @for vs an isolated component</h1>
		<p>
			{'Each fresh mount renders ' + ITEM_COUNT +
				' items and runs the same CPU function once per item.'}
		</p>
		<button onClick={runBenchmark}>Run benchmark</button>
		<pre id="results">Press the button to run.</pre>
		<div id="benchmark-host" hidden></div>
	</main>
}

const app = document.getElementById('app');
if (app === null) throw new Error('missing #app');
createRoot(app).render(App);
