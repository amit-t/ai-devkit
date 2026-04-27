(function () {
  'use strict';

  // ===== THEME CYCLE: light → dark → cyberpunk =====
  const THEME_KEY = 'wb-theme';
  const CYCLE = ['light', 'dark', 'cyberpunk'];
  const ICON = { light: '🌙', dark: '🌃', cyberpunk: '⚡' };
  const body = document.body;
  const toggle = document.getElementById('theme-toggle');

  function apply(theme) {
    body.classList.remove('dark', 'cyberpunk');
    if (theme === 'dark') body.classList.add('dark');
    else if (theme === 'cyberpunk') body.classList.add('cyberpunk');
    if (toggle) {
      toggle.textContent = ICON[theme] || ICON.light;
      toggle.dataset.theme = theme;
      toggle.setAttribute('aria-label', 'Theme: ' + theme + '. Click to cycle.');
    }
  }

  function readStored() {
    const s = localStorage.getItem(THEME_KEY);
    if (CYCLE.indexOf(s) !== -1) return s;
    return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }

  apply(readStored());

  if (toggle) {
    toggle.addEventListener('click', function () {
      const current = toggle.dataset.theme || 'light';
      const next = CYCLE[(CYCLE.indexOf(current) + 1) % CYCLE.length];
      localStorage.setItem(THEME_KEY, next);
      apply(next);
    });
  }

  // ===== COPY BUTTONS ON <pre> =====
  function attachCopyButtons() {
    const pres = document.querySelectorAll('.markdown-body pre');
    pres.forEach(function (pre) {
      if (pre.querySelector('.copy-btn')) return;
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'copy-btn';
      btn.setAttribute('aria-label', 'Copy code');
      btn.textContent = 'Copy';
      btn.addEventListener('click', function () {
        const code = pre.querySelector('code') || pre;
        const text = code.innerText;
        navigator.clipboard.writeText(text).then(function () {
          btn.textContent = 'Copied';
          btn.classList.add('copied');
          setTimeout(function () {
            btn.textContent = 'Copy';
            btn.classList.remove('copied');
          }, 1600);
        });
      });
      pre.appendChild(btn);
    });
  }
  attachCopyButtons();
})();
