/* @flow */

import test from 'ava';

import { normalizeVisitURL } from '../visits.js';

test('normalizeVisitURL keys a Reddit page by its path on every host', t => {
	const key = 'https://www.reddit.com/r/pics/comments/abc123/title/';
	t.is(normalizeVisitURL('https://old.reddit.com/r/pics/comments/abc123/title/'), key);
	t.is(normalizeVisitURL('https://www.reddit.com/r/pics/comments/abc123/title/?sort=new#comment'), key);
	t.is(normalizeVisitURL('https://reddit.com/r/pics/comments/abc123/title'), key);
	t.is(normalizeVisitURL('http://np.reddit.com/r/pics/comments/abc123/title/'), key);
});

test('normalizeVisitURL keeps the query of other sites and drops the fragment', t => {
	t.is(normalizeVisitURL('https://example.com/watch?v=1#t=30'), 'https://example.com/watch?v=1');
	t.is(normalizeVisitURL('https://i.redd.it/abc.jpeg'), 'https://i.redd.it/abc.jpeg');
});

test('normalizeVisitURL does not confuse look-alike hosts with Reddit', t => {
	t.is(normalizeVisitURL('https://notreddit.com/r/pics/?a=1'), 'https://notreddit.com/r/pics/?a=1');
	t.is(normalizeVisitURL('https://reddit.com.example/r/pics/?a=1'), 'https://reddit.com.example/r/pics/?a=1');
});

test('normalizeVisitURL refuses non-web URLs', t => {
	t.is(normalizeVisitURL('mailto:someone@example.com'), null);
	t.is(normalizeVisitURL('data:text/plain,hello'), null);
	t.is(normalizeVisitURL('not a url'), null);
	t.is(normalizeVisitURL('safari-web-extension://abc/options.html'), null);
});
