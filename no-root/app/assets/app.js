'use strict';
const element = id => document.getElementById(id);
const quote = value => "'" + String(value).replace(/'/g, "'\\''") + "'";
const cli = 'sh /data/adb/modules/xguard/system/bin/xguard';
let sequence = 0;
let status = null;
let stats = null;
let activeTab = 'home';
let hitRules = [];
let toastTimer;
let pending = false;
let activityTimer;
let activityLoading = false;
let activityPayload = null;
let activityFilter = 'all';
let activitySignature = '';
let dataRevision = 0;
let domainLoadSequence = 0;
const tabLoads = new Map();
const tabLoadedAt = new Map();
const noRoot = Boolean(window.XGuard && ((window.XGuard.getMode && window.XGuard.getMode() === 'vpn') || window.XGuard.mode === 'vpn'));
let rootReady = noRoot || !window.XGuard;
try { rootReady = rootReady || localStorage.getItem('xguard.rootConfirmed.v1') === '1'; } catch {}

function exec(args) {
  return new Promise((resolve, reject) => {
    if (!window.ksu && !window.XGuard) { reject(new Error('请在 XGuard App 中打开')); return; }
    const callback = 'xguardCallback' + (++sequence);
    const timer = setTimeout(() => { delete window[callback]; reject(new Error('操作超时，请查看日志')); }, 300000);
    window[callback] = (errno, stdout, stderr) => {
      clearTimeout(timer);
      delete window[callback];
      if (Number(errno) !== 0) reject(new Error(String(stdout || stderr || '执行失败').trim()));
      else resolve(String(stdout || ''));
    };
    try {
      if (window.XGuard) window.XGuard.execute(JSON.stringify(args), callback);
      else window.ksu.exec(cli + ' ' + args.map(quote).join(' '), '{}', callback);
    }
    catch (error) { clearTimeout(timer); delete window[callback]; reject(error); }
  });
}
const run = (...args) => exec(['run', 'shield', ...args]);
const json = async promise => JSON.parse(await promise);
const number = value => Number(value || 0).toLocaleString('zh-CN');
const age = value => value ? new Date(Number(value) * 1000).toLocaleString('zh-CN') : '尚无记录';
function toast(message) { element('toast').textContent = message; element('toast').hidden = false; clearTimeout(toastTimer); toastTimer = setTimeout(() => { element('toast').hidden = true; }, 4200); }
function row(title, detail, action) {
  const wrapper = document.createElement('div'); wrapper.className = 'row';
  const text = document.createElement('span'); const heading = document.createElement('b'); heading.textContent = title;
  const description = document.createElement('small'); description.textContent = detail; text.append(heading, description); wrapper.append(text);
  if (action) wrapper.append(action);
  return wrapper;
}
function button(label, handler) { const control = document.createElement('button'); control.textContent = label; control.onclick = () => task(handler, control); return control; }
function fill(id, rows, empty = '暂无内容') { element(id).replaceChildren(...rows); if (!rows.length) { const message = document.createElement('p'); message.className = 'empty'; message.textContent = empty; element(id).append(message); } }
function confirmAction(title, message) {
  return new Promise(resolve => {
    const dialog = element('confirm-dialog'); element('confirm-title').textContent = title; element('confirm-message').textContent = message;
    element('confirm-yes').onclick = () => { dialog.close(); resolve(true); };
    element('confirm-no').onclick = () => { dialog.close(); resolve(false); };
    dialog.oncancel = () => resolve(false); dialog.showModal();
  });
}
async function task(handler, control) {
  if (window.XGuard && !rootReady) { if (!element('root-dialog').open) element('root-dialog').showModal(); return; }
  if (pending) { toast('正在处理上一项操作，请稍候'); return; }
  dataRevision++;
  pending = true; document.querySelector('.app-shell').setAttribute('aria-busy', 'true');
  if (control) control.disabled = true;
  try { await handler(); } catch (error) { toast(error.message || String(error)); }
  finally {
    pending = false; document.querySelector('.app-shell').setAttribute('aria-busy', 'false');
    if (control) control.disabled = false;
  }
}
function requireEnabled() { if (!status?.features?.[0]?.enabled || status.features[0].conflict) throw new Error('请先开启 XGuard 防护并处理冲突'); }
function validDomain(value, wildcard = false) { const domain = wildcard ? value.replace(/^\*\./, '') : value; return domain.length <= 253 && /^[a-z0-9_](?:[a-z0-9_.-]*[a-z0-9_])?$/i.test(domain) && !domain.includes('..'); }
function domainValue(wildcard = false) { const value = element('domain').value.trim().toLowerCase(); if (!validDomain(value, wildcard)) throw new Error('请输入有效域名'); return value; }

async function refresh() {
  const results = await Promise.allSettled([json(exec(['status'])), json(run('stats'))]);
  if (results[0].status === 'rejected') { element('connection').textContent = results[0].reason.message; element('toggle').disabled = true; return; }
  status = results[0].value;
  const feature = status.features[0];
  element('toggle').disabled = false; element('toggle').setAttribute('aria-checked', String(feature.enabled));
  element('protection-title').textContent = status.safe_mode ? '安全模式' : feature.enabled ? '防护已开启' : '防护已暂停';
  element('summary').textContent = feature.summary || '尚无状态';
  element('connection').textContent = status.safe_mode ? '安全模式已开启' : feature.enabled ? 'XGuard 防护已开启' : '防护已关闭';
  const warning = feature.conflict_reason || (feature.conflict ? '模块冲突：' + feature.conflict : '') || (feature.health !== 'ok' ? feature.health : '') || (status.safe_mode ? '关闭安全模式并重启后可恢复防护。' : '');
  element('warning').textContent = warning; element('warning').hidden = !warning;
  element('runtime').textContent = (noRoot ? '运行方式：' : 'Root：') + status.root + ' · 服务：' + status.daemon;
  element('version').textContent = status.version;
  element('header-version').textContent = String(status.version).replace(/^v/, '');
  if (results[1].status === 'fulfilled') {
    stats = results[1].value;
    const modes = { hosts: 'HOSTS 生效', proxy: '代理服务接管', 'dns-vpn': '本地 VPN DNS 拦截', off: '尚未生效' };
    element('mode').textContent = feature.enabled ? (modes[stats.mode] || stats.mode) : '防护关闭';
    element('rule-count').textContent = number(stats.hosts_rules); element('locked-count').textContent = number(stats.splash_locked_apps); element('source-count').textContent = number(stats.sources);
    element('update-info').textContent = (stats.updating ? '正在更新 · ' : '') + '上次更新：' + age(stats.last_ok) + (stats.capped ? ' · 已达到规则上限' : '');
    element('guard').checked = Boolean(Number(stats.guard)); element('proxy-yield').checked = Boolean(Number(stats.proxy_yield)); element('hide').checked = Boolean(Number(stats.hide)); element('mount-mode').value = stats.mount_mode || 'auto'; element('max-rules').value = stats.hosts_max;
  } else { element('update-info').textContent = '规则状态读取失败：' + results[1].reason.message; }
  tabLoadedAt.clear();
  await loadTab(true);
}
function loadTab(force = false) {
  if (!status) return Promise.resolve();
  const id = activeTab;
  if (id === 'home' || id === 'settings') return Promise.resolve();
  if (tabLoads.has(id)) return tabLoads.get(id);
  if (!force && Date.now() - (tabLoadedAt.get(id) || 0) < (id === 'activity' ? 1500 : 15000)) return Promise.resolve();
  const operation = id === 'sources' ? loadSources() : id === 'splash' ? loadSplash() : Promise.all([loadDomains(), loadActivity()]);
  const promise = operation.then(() => tabLoadedAt.set(id, Date.now())).finally(() => tabLoads.delete(id));
  tabLoads.set(id, promise); return promise;
}
async function loadDomains() {
  const request = ++domainLoadSequence;
  const [allowed, blocked] = await Promise.all([json(run('allow')), json(run('block'))]);
  if (request !== domainLoadSequence) return;
  fill('domains', [['allow', allowed.allow || [], '放行'], ['block', blocked.block || [], '自定义拦截']].flatMap(([kind, list, label]) => list.map(domain => row(domain, label, button('移除', async () => { requireEnabled(); await run(kind, 'remove', domain); await refresh(); })))), '没有自定义域名规则');
}
function activityRow(item) {
  const wrapper = document.createElement('div'); wrapper.className = 'activity-row';
  const copy = document.createElement('div'); copy.className = 'domain-copy';
  const domain = document.createElement('strong'); domain.textContent = item.domain;
  const detail = document.createElement('small');
  const protocol = document.createElement('span'); protocol.className = 'protocol-tag'; protocol.textContent = item.source.toUpperCase();
  const time = document.createElement('span'); time.textContent = new Date(Number(item.time) * 1000).toLocaleTimeString('zh-CN', {hour12:false});
  const verdict = document.createElement('span'); verdict.textContent = item.rule_blocked ? '规则命中' : '观察到连接'; verdict.className = item.rule_blocked ? 'hit-tag' : '';
  detail.append(protocol, time, verdict); copy.append(domain, detail);
  const actions = document.createElement('div'); actions.className = 'domain-actions';
  const allow = button('放行', () => changeDomain('allow', item.domain));
  const block = button('封禁', () => changeDomain('block', item.domain)); block.className = 'block-action';
  actions.append(allow, block); wrapper.append(copy, actions); return wrapper;
}
function renderActivity(force = false) {
  const payload = activityPayload || {}; const collector = payload.collector || {}; const snapshot = payload.snapshot || {};
  const running = collector.running && Date.now() / 1000 - Number(snapshot.updated || 0) < 12;
  element('monitor-dot').classList.toggle('active', Boolean(running));
  element('monitor-state').textContent = running ? '正在采集网络域名' : collector.enabled === false ? '采集已暂停' : '采集未就绪';
  element('monitor-toggle').textContent = collector.enabled === false ? '开始采集' : '暂停采集';
  element('monitor-detail').textContent = running ? '被动观察 DNS，不改变其他网络转发。' : collector.error || (collector.enabled === false ? '点击开始采集，继续观察新的连接。' : '请开启本地 VPN 防护；如仍未就绪，请检查系统 VPN 权限与通知栏服务。');
  element('activity-updated').textContent = snapshot.updated ? '更新于 ' + new Date(snapshot.updated * 1000).toLocaleTimeString('zh-CN', {hour12:false}) : '等待采集数据';
  const unique = new Map();
  for (const item of (snapshot.items || []).slice().reverse()) { if (validDomain(item.domain || '') && ['dns','tls'].includes(item.source) && !unique.has(item.domain + item.source)) unique.set(item.domain + item.source, item); }
  const all = [...unique.values()]; element('activity-total').textContent = number(all.length);
  const search = element('activity-search').value.trim().toLowerCase();
  const items = all.filter(item => item.domain.includes(search) && (activityFilter === 'all' || activityFilter === 'blocked' && item.rule_blocked || item.source === activityFilter));
  const signature = JSON.stringify([items, running, collector.enabled, search, activityFilter]);
  if (!force && signature === activitySignature) return; activitySignature = signature;
  const target = element('activity-list'); target.replaceChildren(...items.slice(0, 100).map(activityRow));
  if (!items.length) { const empty = document.createElement('div'); empty.className = 'empty'; empty.textContent = search || activityFilter !== 'all' ? '没有匹配的域名' : running ? '等待新的网络连接' : '暂无域名记录'; const hint = document.createElement('small'); hint.textContent = running ? '打开其他应用或网页后返回。加密流量与缓存命中可能不产生可见域名。' : '开启采集后，这里会显示真实的 DNS / TLS 域名。'; empty.append(hint); target.append(empty); }
}
async function loadActivity() {
  if (activityLoading) return; activityLoading = true;
  const revision = dataRevision;
  try { const payload = await json(run('activity')); if (revision !== dataRevision) return; activityPayload = payload; if (activeTab === 'activity') renderActivity(); }
  catch (error) { element('monitor-state').textContent = '读取采集失败'; element('monitor-detail').textContent = error.message || String(error); element('monitor-dot').classList.remove('active'); }
  finally { activityLoading = false; }
}
async function changeDomain(kind, domain) {
  requireEnabled(); await run(kind, 'add', domain);
  const result = await json(run('query', domain));
  if (kind === 'block' && !result.blocked) throw new Error('域名没有写入封禁规则，请检查放行名单或保护名单');
  toast(kind === 'allow' ? '已放行此域名' : '已加入封禁规则，新连接生效');
  for (const item of activityPayload?.snapshot?.items || []) if (item.domain === domain) item.rule_blocked = kind === 'block';
  renderActivity(true); await loadDomains();
}
function switchPage(id) {
  if (activeTab === id) return;
  activeTab = id; document.querySelectorAll('.page').forEach(page => { page.hidden = page.id !== id; });
  document.querySelectorAll('nav button').forEach(tab => tab.setAttribute('aria-selected', String(tab.dataset.tab === id)));
  clearInterval(activityTimer); activityTimer = null; window.scrollTo(0, 0);
  if (id === 'activity') activityTimer = setInterval(() => { if (!document.hidden && !pending) loadActivity(); }, 2000);
  if (id === 'activity' && activityPayload) renderActivity();
  // Navigation never waits for su / network / list loading. Each tab deduplicates
  // its own background request; a late response only updates that tab's content.
  void loadTab().catch(error => { if (activeTab === id) toast(error.message); });
}
async function loadSources() {
  const sources = await json(run('sources'));
  const list = sources.list || stats?.source_list || [];
  fill('source-list', list.filter(source => !source.custom).map(source => {
    const toggle = document.createElement('input'); toggle.type = 'checkbox'; toggle.checked = source.enabled; toggle.setAttribute('aria-label', source.name);
    toggle.onchange = () => task(async () => { requireEnabled(); await run('sources', source.enabled ? 'disable' : 'enable', source.id); toast('来源已更新'); await refresh(); }, toggle);
    return row(source.name, number(source.count) + ' 条 · ' + (source.err || source.desc || source.result), toggle);
  }));
  const interval = String(sources.interval_h ?? 24);
  if (!Array.from(element('interval').options).some(option => option.value === interval)) { const option = document.createElement('option'); option.value = interval; option.textContent = '每 ' + interval + ' 小时'; element('interval').append(option); }
  element('interval').value = interval;
  element('auto-info').textContent = '后台状态：' + (stats?.auto_state || '待命') + ' · 下次：' + age(stats?.auto_next);
  fill('custom-sources', list.filter(source => source.custom).map(source => row(source.url, number(source.count) + ' 条 · ' + (source.err || source.result), button('删除', async () => { requireEnabled(); await run('sources', 'remove', source.url); await refresh(); }))), '尚未添加自定义来源');
}
async function loadSplash() {
  const [hits, rules] = await Promise.all([json(run('hits')), json(run('rules'))]); hitRules = hits.rules || []; renderHits();
  fill('user-rules', (rules.user || []).map(rule => row(rule.pkg, rule.path, button('删除', async () => { requireEnabled(); if (await confirmAction('删除开屏规则', '删除后会解锁该目录。')) { await run('rules', 'remove', rule.pkg, rule.path); await refresh(); } }))), '没有自定义开屏规则');
}
function renderHits() {
  const grouped = new Map(); const filter = element('filter-apps').value.toLowerCase();
  for (const rule of hitRules) { if (!rule.pkg.toLowerCase().includes(filter)) continue; if (!grouped.has(rule.pkg)) grouped.set(rule.pkg, []); grouped.get(rule.pkg).push(rule); }
  fill('splash-hits', Array.from(grouped, ([pkg, rules]) => {
    const skipped = rules.some(rule => rule.state === 'skipped'); const absent = rules.every(rule => rule.state === 'absent');
    const detail = absent ? '未安装' : skipped ? '已单独解锁' : '已锁定 ' + rules.filter(rule => rule.state === 'locked').length + ' / ' + rules.length + ' 条';
    return row(pkg, detail, absent ? null : button(skipped ? '恢复锁定' : '解锁', async () => { requireEnabled(); await run(skipped ? 'relock' : 'unlock', pkg); await refresh(); }));
  }), '没有匹配的开屏规则');
}
async function addRule(pkg, path) { requireEnabled(); if (!/^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$/.test(pkg) || !path) throw new Error('请填写有效包名与路径'); await run('rules', 'add', pkg, path); toast('已添加并锁定'); }

document.querySelectorAll('nav button').forEach(control => { control.onclick = () => switchPage(control.dataset.tab); });
element('refresh').onclick = () => { if (!rootReady && window.XGuard) element('root-dialog').showModal(); else task(refresh, element('refresh')); };
element('toggle').onclick = () => task(async () => { if (status.safe_mode) throw new Error('请先关闭安全模式并重启'); if (noRoot && window.XGuard.isVpnPrepared && !window.XGuard.isVpnPrepared()) await requestVpnAccess(); await exec([status.features[0].enabled ? 'disable' : 'enable', 'shield']); await refresh(); }, element('toggle'));
element('update').onclick = () => task(async () => { requireEnabled(); toast('正在下载规则，请稍候…'); await run('update'); toast('规则更新完成'); await refresh(); }, element('update'));
element('test').onclick = () => task(async () => {
  const dialog = element('check-dialog');
  element('check-state').textContent = '正在检查规则、挂载和解析状态…';
  element('test-result').hidden = true; element('check-details').open = false;
  dialog.showModal();
  try {
    const result = await json(run('test'));
    const verdicts = {ok:'防护正常', off:'防护未开启', proxy:'由代理服务接管', no_rules:'暂无可用规则', not_mounted:'规则尚未挂载', resolve_leak:'解析检查未通过', app_unmounted:'部分应用未加载规则'};
    element('check-state').textContent = (verdicts[result.verdict] || '检查完成') + (result.warnings?.length ? ' · ' + result.warnings.length + ' 项提示，请查看诊断' : '');
    element('test-result').hidden = false; element('test-result').textContent = JSON.stringify(result, null, 2);
  } catch (error) { element('check-state').textContent = '检查失败：' + error.message; }
}, element('test'));
element('query-domain').onclick = () => task(async () => { const result = await json(run('query', domainValue())); element('domain-result').textContent = result.allowed ? '当前已放行' : result.blocked ? '当前已封禁' : result.in_source ? '命中规则源，当前拦截' : '未命中规则'; });
for (const kind of ['allow', 'block']) element(kind + '-domain').onclick = () => task(async () => { const value = domainValue(kind === 'allow'); if (value.startsWith('*.')) { requireEnabled(); await run(kind, 'add', value); toast('通配放行已保存'); await loadDomains(); } else await changeDomain(kind, value); }, element(kind + '-domain'));
element('interval').onchange = () => task(async () => { await run('sources', 'interval', element('interval').value); toast('更新间隔已保存'); await loadSources(); });
element('add-source').onclick = () => task(async () => { requireEnabled(); const url = element('source-url').value.trim(); if (!/^https?:\/\/\S+$/.test(url)) throw new Error('地址需要以 http:// 或 https:// 开头'); await run('sources', 'add', url); element('source-url').value = ''; toast('已添加，更新规则后下载'); await refresh(); });
element('reset-sources').onclick = () => task(async () => { requireEnabled(); if (await confirmAction('恢复默认来源', '恢复默认内置来源并清空自定义来源。')) { await run('sources', 'reset'); await refresh(); } });
element('filter-apps').oninput = renderHits;
element('add-rule').onclick = () => task(async () => { await addRule(element('package').value.trim(), element('rule-path').value.trim()); await refresh(); });
element('discover').onclick = () => task(async () => { const pkg = element('package').value.trim(); if (pkg && !/^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$/.test(pkg)) throw new Error('包名格式无效'); toast('正在扫描缓存目录…'); const result = await json(run('discover', ...(pkg ? [pkg] : []))); fill('candidates', (result.candidates || []).map(candidate => row(candidate.pkg, candidate.path + ' · ' + number(candidate.kb) + ' KB', button('加入', async () => { await addRule(candidate.pkg, candidate.path); await refresh(); }))), '没有发现新的疑似开屏缓存'); }, element('discover'));
element('guard').onchange = () => task(async () => { requireEnabled(); if (element('guard').checked && !await confirmAction('开启 HTTPDNS IP 拦截', '这可能影响支付、网盘或登录。遇到异常请关闭。')) { element('guard').checked = false; return; } await run('guard', element('guard').checked ? 'on' : 'off'); await refresh(); });
for (const [id, key] of [['proxy-yield', 'proxy_yield'], ['hide', 'hide']]) element(id).onchange = () => task(async () => { requireEnabled(); await run('set', key, element(id).checked ? '1' : '0'); toast(key === 'hide' ? '已保存，重启后完全生效' : '已保存'); await refresh(); });
element('mount-mode').onchange = () => task(async () => { requireEnabled(); await run('set', 'mount_mode', element('mount-mode').value); await refresh(); });
element('save-max').onclick = () => task(async () => { requireEnabled(); await run('set', 'hosts_max', element('max-rules').value); toast('规则上限已保存'); await refresh(); });
element('logs').onclick = () => task(async () => { const [featureLog, suiteLog] = await Promise.all([exec(['log']), run('stats')]); element('log-output').hidden = false; element('log-output').textContent = (featureLog || '暂无日志') + '\n\n' + suiteLog; });
element('safe-mode').onclick = () => task(async () => { const enabled = !status.safe_mode; if (await confirmAction(enabled ? '开启安全模式' : '关闭安全模式', '重启手机后生效。')) { await exec(['safe', enabled ? 'on' : 'off']); toast('已保存，请重启手机'); await refresh(); } });
element('activity-open').onclick = () => switchPage('activity');
element('activity-refresh').onclick = () => task(loadActivity, element('activity-refresh'));
element('activity-clear').onclick = () => task(async () => { if (await confirmAction('清空域名记录', '清空最近观察到的域名，防护规则会保留。')) { activityPayload = await json(run('activity', 'clear')); renderActivity(true); } }, element('activity-clear'));
element('monitor-toggle').onclick = () => task(async () => { activityPayload = await json(run('activity', activityPayload?.collector?.enabled === false ? 'enable' : 'disable')); renderActivity(true); }, element('monitor-toggle'));
element('activity-search').oninput = () => renderActivity(true);
document.querySelectorAll('[data-filter]').forEach(control => { control.onclick = () => { activityFilter = control.dataset.filter; document.querySelectorAll('[data-filter]').forEach(button => button.setAttribute('aria-selected', String(button === control))); renderActivity(true); }; });
document.addEventListener('visibilitychange', () => { if (!document.hidden && activeTab === 'activity' && !pending) loadActivity(); });
element('show-license').onclick = () => element('license-dialog').showModal();
window.xguardBack = () => {
  const dialog = document.querySelector('dialog[open]');
  if (dialog) { dialog.dispatchEvent(new Event('cancel')); dialog.close(); return true; }
  if (activeTab !== 'home') { switchPage('home'); return true; }
  return false;
};
element('root-later').onclick = () => {
  element('root-dialog').close(); element('connection').textContent = '尚未开启本地 VPN，点击右上角重新连接';
};
element('root-dialog').oncancel = () => { element('connection').textContent = '尚未开启本地 VPN，点击右上角重新连接'; };
function requestVpnAccess() {
  return new Promise((resolve, reject) => {
    const callback = 'xguardCallback' + (++sequence);
    const timer = setTimeout(() => { delete window[callback]; reject(new Error('VPN 授权超时，请重试')); }, 120000);
    window[callback] = (code, output) => { clearTimeout(timer); delete window[callback]; if (Number(code) === 0) { rootReady = true; try { localStorage.setItem('xguard.rootConfirmed.v1','1'); } catch {} resolve(); } else reject(new Error(String(output || '本地 VPN 权限未授予'))); };
    try { if (noRoot && window.XGuard.requestVpn) window.XGuard.requestVpn(callback); else window.XGuard.requestRoot(callback); } catch (error) { clearTimeout(timer); delete window[callback]; reject(error); }
  });
}
element('root-authorize').onclick = async () => {
  const control = element('root-authorize'); control.disabled = true;
  element('root-status').textContent = '等待系统 VPN 授权…';
  try {
    if (window.XGuard?.requestVpn || window.XGuard?.requestRoot) await requestVpnAccess();
    else throw new Error('当前容器不支持本地 VPN，请使用 XGuard App');
    rootReady = true;
    try { localStorage.setItem('xguard.rootConfirmed.v1','1'); } catch {}
    element('root-dialog').close(); await task(refresh);
  } catch (error) { element('root-status').textContent = error.message; }
  finally { control.disabled = false; }
};
for (const dialog of document.querySelectorAll('dialog')) {
  dialog.addEventListener('click', event => {
    if (event.target !== dialog) return;
    const r = dialog.getBoundingClientRect();
    if (event.clientX < r.left || event.clientX > r.right || event.clientY < r.top || event.clientY > r.bottom) {
      dialog.dispatchEvent(new Event('cancel')); dialog.close();
    }
  });
}
if (window.XGuard && !rootReady) { element('root-dialog').showModal(); element('connection').textContent = noRoot ? '等待授予本地 VPN 权限' : '等待授予 Root 权限'; }
else if (noRoot && window.XGuard.isVpnPrepared && !window.XGuard.isVpnPrepared()) { element('root-dialog').showModal(); element('connection').textContent = '点击开启本地 VPN 防护'; }
else task(refresh);
