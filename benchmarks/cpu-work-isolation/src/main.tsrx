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
			<li data-item={item}>{'' + heavyCpuWork(item)}</li>
		}
	</ul>
}

function HeavyItem(props: { item: number }) @{
	const result = '' + heavyCpuWork(props.item);
	<li data-item={props.item}>{result}</li>
}
const IsolatedHeavyItem = memo(HeavyItem);

function IsolatedList(props: ListProps) @{
	<ul>
		@for (const item of props.items; key item) {
			<IsolatedHeavyItem item={item} />
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

interface UpdateSamples {
	inlineCalls: number[];
	inlineTimes: number[];
	isolatedCalls: number[];
	isolatedTimes: number[];
}

function shiftedArrays(items: number[]): number[][] {
	const arrays = new Array<number[]>(UPDATES_PER_SAMPLE);
	let next = items;
	for (let i = 0; i < UPDATES_PER_SAMPLE; i++) {
		next = [...next.slice(1), next[0]];
		arrays[i] = next;
	}
	return arrays;
}

function measureUpdateBatch(render: (items: number[]) => void, arrays: number[][]) {
	const callsBefore = heavyCallCount;
	const startedAt = performance.now();
	for (const items of arrays) render(items);
	return {
		calls: (heavyCallCount - callsBefore) / UPDATES_PER_SAMPLE,
		elapsed: (performance.now() - startedAt) / UPDATES_PER_SAMPLE,
	};
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

function measureUpdates(host: HTMLElement): UpdateSamples {
	const inlineHost = document.createElement('div');
	const isolatedHost = document.createElement('div');
	host.append(inlineHost, isolatedHost);

	const inlineRoot = createRoot(inlineHost);
	const isolatedRoot = createRoot(isolatedHost);
	let inlineItems = ITEMS;
	let isolatedItems = ITEMS;
	inlineRoot.render(InlineList, { items: inlineItems });
	isolatedRoot.render(IsolatedList, { items: isolatedItems });

	const samples: UpdateSamples = {
		inlineCalls: [],
		inlineTimes: [],
		isolatedCalls: [],
		isolatedTimes: [],
	};

	const updateInline = (record: boolean) => {
		const arrays = shiftedArrays(inlineItems);
		const sample = measureUpdateBatch(
			(items) => flushSync(() => inlineRoot.render(InlineList, { items })),
			arrays,
		);
		inlineItems = arrays[arrays.length - 1];
		if (record) {
			samples.inlineCalls.push(sample.calls);
			samples.inlineTimes.push(sample.elapsed);
		}
	};
	const updateIsolated = (record: boolean) => {
		const arrays = shiftedArrays(isolatedItems);
		const sample = measureUpdateBatch(
			(items) => flushSync(() => isolatedRoot.render(IsolatedList, { items })),
			arrays,
		);
		isolatedItems = arrays[arrays.length - 1];
		if (record) {
			samples.isolatedCalls.push(sample.calls);
			samples.isolatedTimes.push(sample.elapsed);
		}
	};

	for (let i = 0; i < WARMUP_RUNS; i++) {
		updateInline(false);
		updateIsolated(false);
	}
	for (let i = 0; i < UPDATE_SAMPLES; i++) {
		if ((i & 1) === 0) {
			updateInline(true);
			updateIsolated(true);
		} else {
			updateIsolated(true);
			updateInline(true);
		}
	}

	validateOrder(inlineHost, inlineItems);
	validateOrder(isolatedHost, isolatedItems);
	inlineRoot.unmount();
	isolatedRoot.unmount();
	return samples;
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
	const updates = measureUpdates(host);
	const inlineUpdateMedian = median(updates.inlineTimes);
	const isolatedUpdateMedian = median(updates.isolatedTimes);

	output.textContent = [
		'Mount',
		`Inline @for median: ${median(inline).toFixed(2)} ms`,
		`Isolated memo component median: ${median(isolated).toFixed(2)} ms`,
		'',
		`Inline samples: ${formatSamples(inline)} ms`,
		`Isolated samples: ${formatSamples(isolated)} ms`,
		'',
		'Shift first item to end',
		`Inline @for median: ${median(updates.inlineTimes).toFixed(2)} ms/update`,
		`Isolated memo component median: ${median(updates.isolatedTimes).toFixed(2)} ms/update`,
		`Memo isolation speedup: ${(inlineUpdateMedian / isolatedUpdateMedian).toFixed(1)}x`,
		`Inline heavy calls: ${median(updates.inlineCalls).toFixed(0)}/update`,
		`Isolated memo heavy calls: ${median(updates.isolatedCalls).toFixed(0)}/update`,
		'',
		`Inline update samples: ${formatSamples(updates.inlineTimes)} ms`,
		`Isolated update samples: ${formatSamples(updates.isolatedTimes)} ms`,
	].join('\n');
}

function App() @{
	<main>
		<h1>CPU work inside @for vs an isolated component</h1>
		<p>
			{'Each fresh mount renders ' + ITEM_COUNT +
				' items and runs the same CPU function once per item.'}
		</p>
		<p>Updates move the first keyed item to the end on every render.</p>
		<button onClick={runBenchmark}>Run benchmark</button>
		<pre id="results">Press the button to run.</pre>
		<div id="benchmark-host" hidden></div>
	</main>
}

const app = document.getElementById('app');
if (app === null) throw new Error('missing #app');
createRoot(app).render(App);
