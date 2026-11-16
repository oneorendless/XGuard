(() => {
  'use strict';
  const system = matchMedia('(prefers-color-scheme: dark)');
  let preference = 'system';
  try { preference = localStorage.getItem('xguard.theme.v1') || 'system'; } catch {}
  if (!['light','dark','system'].includes(preference)) preference = 'system';
  function apply() {
    const dark = preference === 'dark' || preference === 'system' && system.matches;
    document.documentElement.dataset.theme = dark ? 'dark' : 'light';
    document.documentElement.dataset.themePreference = preference;
    try { window.XGuard?.setTheme?.(dark); } catch {}
  }
  window.XGuardTheme = { get preference() { return preference; }, set(value) {
    if (!['light','dark','system'].includes(value)) return;
    preference = value;
    try { localStorage.setItem('xguard.theme.v1', value); } catch {}
    apply();
  }};
  system.addEventListener('change', apply);
  apply();
})();
