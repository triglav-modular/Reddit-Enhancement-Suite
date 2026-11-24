// Test-only service worker: records the errors of RES's background, then
// loads it. RES ignores message types it does not know, so the harness's own
// message reaches only this listener.
const harnessErrors = [];
const describe = value => (value && (value.stack || value.message)) || String(value);
self.addEventListener('error', e => { harnessErrors.push(`error: ${describe(e.error || e.message)}`); });
self.addEventListener('unhandledrejection', e => { harnessErrors.push(`unhandledrejection: ${describe(e.reason)}`); });
const consoleError = console.error.bind(console);
console.error = (...args) => {
	harnessErrors.push(`console.error: ${args.map(describe).join(' ')}`);
	consoleError(...args);
};
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
	if (message && message.type === 'harness.errors') sendResponse({ data: harnessErrors });
});
importScripts('background.entry.js');
