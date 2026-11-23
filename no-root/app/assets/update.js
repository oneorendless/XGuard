(() => {
  const bridge = window.XGuard;
  if (typeof bridge?.openAppUpdate !== 'function') return;
  const button = document.getElementById('app-update-check');
  const dialog = document.getElementById('app-update-dialog');
  const note = document.getElementById('app-update-status');
  const download = document.getElementById('app-update-download');
  const vpn = bridge.getMode?.() === 'vpn';
  let update;
  let checking = false;
  let manualCheck = false;

  const showUpdate = () => {
    if (!update || document.hidden || document.querySelector('dialog[open]')) return;
    document.getElementById('app-update-version').textContent = `当前版本 ${update.current} → 新版本 ${update.latest}`;
    document.getElementById('app-update-help').textContent = vpn
      ? '下载免 Root 版 APK 后，打开下载的文件，按 Android 提示覆盖安装。'
      : '下载模块 ZIP 后，在 Root 管理器中从本地安装模块并重启。请勿仅安装配套 APK。';
    download.textContent = vpn ? '下载 APK' : '下载模块 ZIP';
    dialog.showModal();
  };

  async function check(manual = false) {
    manualCheck ||= manual;
    if (checking) return;
    checking = true;
    update = null;
    if (manual) note.textContent = '正在检查 XGuard 版本…';
    try {
      const result = JSON.parse(await exec(['app-update']));
      if (result.state === 'available') {
        update = result;
        note.textContent = `发现新版本 ${result.latest}`;
        showUpdate();
      } else if (manualCheck) {
        note.textContent = result.state === 'missing'
          ? `已发布 ${result.latest}，但暂无适用于当前版本的安装包`
          : `已是最新版本（${result.current}）`;
      }
    } catch {
      if (manualCheck) note.textContent = '检查失败，请确认可访问 GitHub 后重试';
    } finally {
      checking = false;
      manualCheck = false;
    }
  }

  document.getElementById('app-update-card').hidden = false;
  button.onclick = () => { void check(true); };
  download.onclick = () => { bridge.openAppUpdate(); dialog.close(); };
  dialog.addEventListener('close', () => { update = null; });
  document.addEventListener('close', event => { if (event.target !== dialog) showUpdate(); }, true);
  document.addEventListener('visibilitychange', showUpdate);
  void check();
})();
