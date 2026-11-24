/* @flow */

import { sendMessage } from './messaging';
import { isPrivateBrowsing } from './privateBrowsing';

export async function addURLToHistory(url: string): Promise<void> {
	if (isPrivateBrowsing()) return;

	await sendMessage('addURLToHistory', url);
}

export function isURLVisited(url: string): Promise<boolean> {
	return sendMessage('isURLVisited', url);
}

/**
 * Safari has no history API, so the Safari build records visits itself: the
 * Reddit page this is, and every web link followed from it. Without this,
 * "visited" filters would only know the media RES opened.
 */
export function recordVisits() {
	if (process.env.BUILD_TARGET !== 'safari') return;
	if (window !== window.top || isPrivateBrowsing()) return;

	const record = (url: string) => { sendMessage('addURLToHistory', url).catch(() => {}); };
	record(location.href);

	const onFollow = (e: MouseEvent) => {
		if (e.type === 'auxclick' && e.button !== 1) return;
		const target = e.target instanceof Element ? e.target.closest<Element>('a[href]') : null;
		if (target instanceof HTMLAnchorElement && /^https?:$/.test(target.protocol)) record(target.href);
	};
	document.addEventListener('click', onFollow, true);
	document.addEventListener('auxclick', onFollow, true);
}
