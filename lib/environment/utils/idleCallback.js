/* @flow */

// Safari has no requestIdleCallback. The Safari build injects these in place
// of the globals (esbuild `inject`), so every caller gets a working version
// whether or not the browser has one.

type IdleDeadline = { didTimeout: boolean, timeRemaining: () => number };
type IdleOptions = { timeout?: number };

const native = typeof globalThis.requestIdleCallback === 'function';

// A frame's worth of work, as Chrome allows an idle callback at most 50 ms.
const BUDGET = 50;

export const requestIdleCallback: (callback: IdleDeadline => unknown, options?: IdleOptions) => number = native ?
	(callback, options) => globalThis.requestIdleCallback(callback, options) :
	callback => {
		const start = Date.now();
		return setTimeout(() => {
			callback({ didTimeout: false, timeRemaining: () => Math.max(0, BUDGET - (Date.now() - start)) });
		}, 1);
	};

export const cancelIdleCallback: (handle: number) => void = native ?
	handle => globalThis.cancelIdleCallback(handle) :
	handle => { clearTimeout(handle); };
