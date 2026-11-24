/* @flow */

import { apiToPromise } from '../utils/api';
import { addListener } from './messaging';
import { addVisit, isVisited, prune } from './visits';

if (process.env.BUILD_TARGET === 'safari') {
	// Safari has no history API: answer from the extension's own record.
	prune().catch(e => { console.error('Could not prune visits', e); });

	addListener('addURLToHistory', (url, { tab }) => {
		if (tab && tab.incognito) return;
		return addVisit(url);
	});

	addListener('isURLVisited', url => isVisited(url));
} else {
	addListener('addURLToHistory', url => {
		chrome.history.addUrl({ url });
	});

	addListener('isURLVisited', async url => {
		const visits = await apiToPromise(chrome.history.getVisits.bind(chrome.history))({ url });
		return visits.length > 0;
	});
}
