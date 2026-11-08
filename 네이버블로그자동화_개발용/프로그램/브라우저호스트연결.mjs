// Run inside an authorized desktop host with the documented cua API.
// A child CLI process does not inherit a verified browser connection.
// Never copy host identities, tokens, pipes or permission settings into a child.
export async function connectNaverHost(cua) {
  if (!cua?.getState || !cua?.getTab) throw new Error('DESKTOP_BROWSER_HOST_REQUIRED');
  const state = await cua.getState({ emit: false });
  if ((state.errors ?? []).some(e => /Local browser use is disabled/i.test(e))) {
    throw new Error('BROWSER_HOST_PERMISSION');
  }
  const candidates = [];
  for (const browser of state.browsers ?? []) {
    if (browser.type !== 'extension' || browser.family !== 'chrome') continue;
    for (const tab of browser.tabs ?? []) {
      let url;
      try { url = new URL(tab.url); } catch { continue; }
      if (url.protocol === 'https:' && url.hostname === 'blog.naver.com' &&
          (url.pathname === '/ij1128' || url.pathname.startsWith('/ij1128/'))) {
        candidates.push({ browserId: browser.id, tabId: tab.id });
      }
    }
  }
  if (!candidates.length) throw new Error('NAVER_TAB_UNAVAILABLE');
  if (new Set(candidates.map(c => c.browserId)).size !== 1) {
    throw new Error('MULTIPLE_NAVER_BROWSER_PROFILES');
  }
  const selected = candidates[0];
  // getTab performs the host's access checks; an exception is never bypassed.
  const tab = await cua.getTab(selected.tabId, { browser: selected.browserId });
  await tab.getAXState({ emit: false });
  return { ...selected, tab, connectionVerified: true };
}
