/* Local preferences and static documentation search. No external requests. */
(() => {
  const root = document.documentElement;
  const theme = document.getElementById('theme-toggle');
  const applyTheme = (value) => {
    root.dataset.theme = value === 'dark' ? 'dark' : 'light';
    theme.textContent = value === 'dark' ? 'Light theme' : 'Dark theme';
  };
  try { applyTheme(localStorage.getItem('mq-docs-theme')); } catch { applyTheme('light'); }
  theme.hidden = false;
  theme.addEventListener('click', () => {
    applyTheme(root.dataset.theme === 'dark' ? 'light' : 'dark');
    try { localStorage.setItem('mq-docs-theme', root.dataset.theme); } catch { /* Optional preference. */ }
  });
  if (matchMedia('(max-width: 760px)').matches) document.querySelector('.guide-menu').open = false;
  const search = document.querySelector('.search');
  const input = document.getElementById('search-input');
  const status = document.getElementById('search-status');
  const results = document.getElementById('search-results');
  let index;
  let request = 0;
  search.hidden = false;
  input.addEventListener('input', async () => {
    const current = ++request;
    const terms = input.value.toLowerCase().trim().split(/\s+/).filter(Boolean);
    results.replaceChildren();
    status.textContent = '';
    if (!terms.length) return;
    try {
      if (!index) index = fetch(search.dataset.index).then(response => {
        if (!response.ok) throw new Error('Index unavailable');
        return response.json();
      });
      const data = await index;
      if (current !== request) return;
      const matches = data.docs.filter(doc => terms.every(term =>
        (doc.title + ' ' + doc.text).toLowerCase().includes(term))).slice(0, 8);
      status.textContent = matches.length ? 'Matching sections' : 'No matches. Try a shorter search.';
      for (const doc of matches) {
        const link = document.createElement('a');
        const target = new URL(doc.location, new URL(search.dataset.root, location.href));
        if (target.origin !== location.origin) continue;
        link.href = target.href;
        link.textContent = doc.title;
        const item = document.createElement('li');
        item.append(link);
        results.append(item);
      }
    } catch {
      index = undefined;
      if (current === request) status.textContent = 'Search is unavailable. Use the documentation menu.';
    }
  });
})();
