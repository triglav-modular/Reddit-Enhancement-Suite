/* @flow */

import { sendMessage } from './messaging';
import { openNewTab } from './tabs';

export function download(url: string, filename?: string) {
	// resolve relative URLs
	const href = new URL(url, location.href).href;

	if (process.env.BUILD_TARGET === 'safari') {
		saveFromPage(href, filename);
		return;
	}

	// Firefox and Chrome <a download> is same-origin only
	sendMessage('download', { url: href, filename });
}

// Safari has no downloads API. A blob URL is same-origin, so `<a download>`
// saves it under the given name. Media whose host refuses a cross-origin read
// opens in a new tab instead, to be saved from there.
async function saveFromPage(url: string, filename?: string) {
	let blob;
	try {
		const response = await fetch(url, { credentials: 'omit' });
		if (!response.ok) throw new Error(`HTTP ${response.status}`);
		blob = await response.blob();
	} catch (e) {
		console.warn('Could not fetch for download, opening instead:', url, e);
		openNewTab(url);
		return;
	}

	const objectURL = URL.createObjectURL(blob);
	const link = document.createElement('a');
	link.href = objectURL;
	link.download = filename || decodeURIComponent(new URL(url).pathname.split('/').pop() || '') || 'download';
	link.style.display = 'none';
	(document.body || document.documentElement).append(link);
	link.click();
	link.remove();
	setTimeout(() => { URL.revokeObjectURL(objectURL); }, 60 * 1000);
}
