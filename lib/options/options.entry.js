/* @flow */

import './handleBlocking';
import * as Context from '../environment/foreground/context';
import * as Core from '../core/init';
import { allowedModules } from '../core/modules';
import * as SettingsConsole from './settingsConsole';

// The options page depends on the context object in order to generate correct links and perform requests against Reddit
Context.retrieveFromParent().then(async () => {
	allowedModules.push('nightMode', 'notifications');

	Core.init();

	await Promise.all([Core.loadI18n, Core.loadOptions]);

	SettingsConsole.start();

	// Signal to settingsNavigation that it seems to be going well
	Context.postMessageToParent({ loadSuccess: true });

	// settingsNavigation sends the context again on every load event of the frame and waits for
	// loadSuccess. Safari fires that event again when the console follows one of its own
	// #res:settings links, without loading a new page, so answer every later context too.
	window.addEventListener('message', (event: MessageEvent) => {
		const data: any = event.data;
		if (Context.isMessageFromParent(event) && data && typeof data === 'object' && data.context) {
			Context.postMessageToParent({ loadSuccess: true });
		}
	});
}).catch(e => {
	console.error(e);
	Context.postMessageToParent({ failedToLoad: true });
});
