// Test-only content script, added beside RES's in the harness copy of the
// extension. It shares RES's isolated world, so it sees RES's errors, and it
// relays the harness's questions from the page to RES's background.
(() => {
	document.documentElement.dataset.resHarness = 'injected';
	const errors = [];
	const describe = value => (value && (value.stack || value.message)) || String(value);
	addEventListener('error', e => { errors.push(`error: ${describe(e.error || e.message)}`); });
	addEventListener('unhandledrejection', e => { errors.push(`unhandledrejection: ${describe(e.reason)}`); });
	// WebKit reports an error thrown in a content script to `onerror` only as
	// "Script error.", so catch it where RES's callbacks are entered instead.
	const guard = fn => typeof fn !== 'function' || fn.__resHarness ? fn : Object.assign(function (...a) {
		try {
			return fn.apply(this, a);
		} catch (err) {
			errors.push(`thrown: ${describe(err)}`);
			throw err;
		}
	}, { __resHarness: true });
	for (const name of ['setTimeout', 'setInterval', 'requestAnimationFrame', 'queueMicrotask']) {
		const original = window[name];
		window[name] = function (fn, ...rest) { return original.call(this, guard(fn), ...rest); };
	}
	const wrapped = new WeakMap();
	const add = EventTarget.prototype.addEventListener;
	const remove = EventTarget.prototype.removeEventListener;
	EventTarget.prototype.addEventListener = function (type, fn, ...rest) {
		if (typeof fn === 'function' && !wrapped.has(fn)) wrapped.set(fn, guard(fn));
		return add.call(this, type, typeof fn === 'function' ? wrapped.get(fn) : fn, ...rest);
	};
	EventTarget.prototype.removeEventListener = function (type, fn, ...rest) {
		return remove.call(this, type, (typeof fn === 'function' && wrapped.get(fn)) || fn, ...rest);
	};
	const NativeMutationObserver = window.MutationObserver;
	window.MutationObserver = class extends NativeMutationObserver { constructor(fn) { super(guard(fn)); } };
	const then = Promise.prototype.then;
	Promise.prototype.then = function (onFulfilled, onRejected) { return then.call(this, guard(onFulfilled), guard(onRejected)); };
	const consoleError = console.error.bind(console);
	console.error = (...args) => {
		errors.push(`console.error: ${args.map(describe).join(' ')}`);
		consoleError(...args);
	};

	// Reddit answers a logged-out client's API calls with a login page. RES
	// needs one of them, /by_id/, to expand an i.redd.it image; answer it
	// from the post's own data in the page.
	const pageFetch = window.fetch.bind(window);
	window.fetch = (input, init) => {
		const url = new URL(typeof input === 'string' ? input : input.url, location.href);
		const byId = url.origin === location.origin && (/^\/by_id\/([\w,]+)\.json$/).exec(url.pathname);
		if (!byId) return pageFetch(input, init);
		const children = byId[1].split(',').map(name => {
			const thing = document.querySelector(`.thing[data-fullname="${name}"]`);
			const media = thing && thing.dataset.url;
			return { kind: 't3', data: {
				name, id: name.replace(/^t3_/, ''), url: media, title: thing && thing.querySelector('a.title').textContent,
				selftext_html: null,
				preview: media ? { images: [{ source: { url: media, width: 1080, height: 1080 }, resolutions: [], variants: {} }] } : undefined,
			} };
		});
		return Promise.resolve(new Response(JSON.stringify({ kind: 'Listing', data: { children } }), { headers: { 'Content-Type': 'application/json' } }));
	};

	addEventListener('message', async e => {
		if (e.source !== window || !e.data || e.data.resHarness !== 'request') return;
		const { id, op, arg } = e.data;
		let result;
		try {
			if (op === 'errors') {
				const reply = await browser.runtime.sendMessage({ type: 'harness.errors' });
				result = { content: errors, background: reply && reply.data };
			} else if (op === 'send') {
				result = await browser.runtime.sendMessage(arg);
			}
		} catch (err) {
			result = { error: describe(err) };
		}
		postMessage({ resHarness: 'response', id, result }, '*');
	});
})();
