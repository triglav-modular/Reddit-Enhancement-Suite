/* @flow */

import { addListener } from './messaging';
import { addVisit } from './visits';

addListener('openNewTabs', ({ urls, focusIndex }, { tab }) => {
	urls.forEach((url, i) => {
		chrome.tabs.create({
			url,
			active: i === focusIndex,
			index: tab.index + 1 + i,
			openerTabId: tab.id,
			// Firefox needs cookieStoreId to open in correct container
			...(process.env.BUILD_TARGET === 'firefox' ? { cookieStoreId: tab.cookieStoreId } : {}),
		});
		// Safari has no history API; keep the extension's own record of what RES opened.
		if (process.env.BUILD_TARGET === 'safari' && !tab.incognito) {
			addVisit(url).catch(e => { console.error('Could not record visit', e); });
		}
	});
});

