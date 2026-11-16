'use strict';
const element = id => document.getElementById(id);
const quote = value => "'" + String(value).replace(/'/g, "'\\''") + "'";
const cli = 'sh /data/adb/modules/xguard/system/bin/xguard';
let sequence = 0;
let status = null;
let stats = null;
let activeTab = 'home';
let hitRules = [];
let userRules = [];
let candidates = [];
const appInfo = new Map();
const appNames = { 'com.xunlei.downloadprovider':'迅雷', 'tv.danmaku.bili':'哔哩哔哩', 'com.zhihu.android':'知乎', 'com.autonavi.minimap':'高德地图', 'com.taobao.idlefish':'闲鱼', 'com.tencent.mobileqq':'QQ', 'com.netease.cloudmusic':'网易云音乐', 'cn.kuwo.player':'酷我音乐', 'cn.damai':'大麦', 'cn.missevan':'猫耳FM', 'com.sf.activity':'顺丰速运', 'com.anjuke.android.app':'安居客', 'com.mihoyo.hyperion':'米游社', 'com.umetrip.android.msky.app':'航旅纵横', 'ctrip.android.view':'携程旅行', 'com.hexin.plat.android':'同花顺', 'com.cn21.ecloud':'天翼云盘', 'com.xiaomi.smarthome':'米家' };
const isVpnMode = () => Boolean(window.XGuard?.getMode && window.XGuard.getMode() === 'vpn');
let toastTimer;
let pending = false;
let activityTimer;
let activityLoading = false;
let activityPayload = null;
let activityError = '';
let activityFilter = 'all';
let activitySignature = '';
let dataRevision = 0;
let refreshSequence = 0;
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
  const request = ++refreshSequence;
  const statsRequest = json(run('stats', 'quick')).then(value => ({value}), error => ({error}));
  let nextStatus;
  try { nextStatus = await json(exec(['status'])); }
  catch (error) { if (request !== refreshSequence) return; status = null; element('connection').textContent = error.message; element('toggle').disabled = true; element('traffic-state').textContent = '连接失败'; return; }
  if (request !== refreshSequence) return;
  status = nextStatus;
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
  if (activeTab === 'home' || activeTab === 'activity') void loadActivity();
  const result = await statsRequest;
  if (request !== refreshSequence) return;
  if (!result.error) {
    stats = result.value;
    const modes = { hosts: 'HOSTS 生效', proxy: '代理服务接管', 'dns-vpn': '本地 VPN DNS 拦截', off: '尚未生效' };
    element('mode').textContent = feature.enabled ? (modes[stats.mode] || stats.mode) : '防护关闭';
    element('rule-count').textContent = number(stats.hosts_rules); element('locked-count').textContent = isVpnMode() ? '需 Root' : stats.splash_locked_apps == null ? '—' : number(stats.splash_locked_apps); element('source-count').textContent = number(stats.sources);
    element('splash-metric-detail').textContent = isVpnMode() ? 'DNS 防护不锁缓存' : stats.locked_count_cached ? '最近核验锁定应用' : '已实际锁定应用';
    element('update-info').textContent = (stats.updating ? '正在更新 · ' : '') + '上次更新：' + age(stats.last_ok) + (stats.capped ? ' · 已达到规则上限' : '');
    element('guard').checked = Boolean(Number(stats.guard)); element('proxy-yield').checked = Boolean(Number(stats.proxy_yield)); element('hide').checked = Boolean(Number(stats.hide)); element('mount-mode').value = stats.mount_mode || 'auto'; element('max-rules').value = stats.hosts_max;
  } else { element('update-info').textContent = '规则状态读取失败：' + result.error.message; }
  renderTrafficStats();
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
  try { const payload = await json(run('activity')); if (revision !== dataRevision) return; activityPayload = payload; activityError = ''; renderTrafficStats(); if (activeTab === 'activity') renderActivity(); }
  catch (error) { if (revision !== dataRevision) return; activityError = error.message || String(error); renderTrafficStats(); element('monitor-state').textContent = '读取采集失败'; element('monitor-detail').textContent = activityError; element('monitor-dot').classList.remove('active'); }
  finally { activityLoading = false; }
}
function renderTrafficStats() {
  const vpn = isVpnMode(); const snapshot = activityPayload?.snapshot || {};
  const total = Number(vpn ? snapshot.totals?.queries || 0 : snapshot.observed || 0);
  const blocked = Number(vpn ? snapshot.totals?.blocked || 0 : snapshot.matched || 0);
  const percent = total ? Math.min(100, Math.max(0, blocked / total * 100)) : 0;
  element('traffic-title').textContent = vpn ? '拦截统计' : '防护统计';
  element('traffic-total-label').textContent = vpn ? 'DNS 请求' : '观察记录';
  element('traffic-blocked-label').textContent = vpn ? '已拦截' : '规则命中';
  element('traffic-ratio-label').textContent = vpn ? '拦截比例' : '命中比例';
  element('traffic-total').textContent = activityPayload ? number(total) : '—'; element('traffic-blocked').textContent = activityPayload ? number(blocked) : '—';
  element('traffic-ratio').textContent = activityPayload ? percent.toFixed(1) + '%' : '—'; element('traffic-progress').value = percent;
  element('traffic-note').textContent = vpn ? '累计自 ' + age(snapshot.totals?.started) + ' · 失败 ' + number(snapshot.totals?.failed) + ' 次。清空域名记录不重置计数。' : '本次采集期间的去重 DNS / TLS 观察记录；规则命中不等于实际拦截，hosts 提前阻断的请求无法计数。';
  const collector = activityPayload?.collector;
  const fresh = vpn || Date.now() / 1000 - Number(snapshot.updated || 0) < 12;
  element('traffic-state').textContent = activityError ? '统计读取失败' : collector?.enabled === false ? '采集已暂停' : collector?.running ? fresh ? '实时更新' : '数据未更新' : '等待服务';
  element('traffic-arc').setAttribute('stroke-dasharray', percent + ' ' + (100 - percent));
  element('traffic-arc').setAttribute('visibility', percent > 0 ? 'visible' : 'hidden');
  element('traffic-donut').setAttribute('aria-label', (vpn ? '拦截比例 ' : '规则命中比例 ') + percent.toFixed(1) + '%');
  element('traffic-progress').setAttribute('aria-label', vpn ? '拦截比例' : '命中比例');
  element('hosts-stats').hidden = vpn;
  element('hosts-rule-count').textContent = stats ? number(stats.hosts_rules) : '—';
  const hostsActive = status?.features?.[0]?.enabled && stats?.mode === 'hosts';
  element('hosts-state').textContent = !status || !stats ? '正在读取' : !status.features[0].enabled ? '防护已暂停' : stats.mode === 'proxy' ? '代理接管' : hostsActive ? '已挂载' : '尚未挂载';
  element('hosts-state').classList.toggle('active', Boolean(hostsActive));
  element('hosts-matched-domains').textContent = activityPayload ? number(new Set((snapshot.items || []).filter(item => item.rule_blocked).map(item => item.domain)).size) : '—';
  renderRecentTraffic(snapshot, vpn);
}
function renderRecentTraffic(snapshot, vpn) {
  const now = Math.floor(Date.now() / 60000), buckets = Array.from({length:12}, () => ({total:0, matched:0}));
  const ranked = new Map(), items = snapshot.items || [];
  for (const item of items) {
    if (!validDomain(item.domain || '') || !['dns','tls'].includes(item.source)) continue;
    const index = Math.floor(Number(item.time) / 60) - now + 11;
    if (index >= 0 && index < 12) { buckets[index].total++; if (item.rule_blocked) buckets[index].matched++; }
    if (item.rule_blocked) ranked.set(item.domain, (ranked.get(item.domain) || 0) + 1);
  }
  const maximum = Math.max(1, ...buckets.map(bucket => bucket.total));
  const ns = 'http://www.w3.org/2000/svg', chart = element('traffic-chart'); chart.replaceChildren();
  buckets.forEach((bucket, index) => {
    for (const [count, kind] of [[bucket.total, 'chart-observed'], [bucket.matched, 'chart-matched']]) {
      const bar = document.createElementNS(ns, 'rect'), height = count / maximum * 76;
      for (const [key, value] of Object.entries({x:index * 24 + 4, y:84 - height, width:16, height, rx:3, class:kind})) bar.setAttribute(key, value);
      const title = document.createElementNS(ns, 'title'); title.textContent = (11 - index) + ' 分钟前：' + bucket.total + ' 条记录，' + bucket.matched + (vpn ? ' 条拦截' : ' 条命中'); bar.append(title); chart.append(bar);
    }
  });
  chart.setAttribute('aria-label', '近 12 分钟最近记录分布，共 ' + buckets.reduce((sum, bucket) => sum + bucket.total, 0) + ' 条，其中 ' + buckets.reduce((sum, bucket) => sum + bucket.matched, 0) + (vpn ? ' 条拦截' : ' 条规则命中'));
  element('chart-matched-label').textContent = vpn ? '拦截' : '命中';
  element('traffic-chart-note').textContent = '仅展示保留的最近 ' + number(items.length) + ' 条域名记录；图表与排行并非全量请求统计。';
  element('traffic-top-title').textContent = vpn ? '近期拦截域名' : '近期规则命中域名';
  const top = [...ranked].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])).slice(0, 5);
  fill('traffic-top', top.map(([domain, count]) => row(domain, number(count) + (vpn ? ' 条拦截记录' : ' 条规则匹配记录'))), vpn ? '近期暂无拦截记录' : '近期暂无可见规则命中');
}
async function changeDomain(kind, domain) {
  requireEnabled(); await run(kind, 'add', domain);
  const result = await json(run('query', domain));
  if (kind === 'block' && !result.blocked) throw new Error('域名没有写入封禁规则，请检查放行名单或保护名单');
  toast(kind === 'allow' ? '已放行此域名' : '已加入封禁规则，新连接生效');
  if (!isVpnMode()) for (const item of activityPayload?.snapshot?.items || []) if (item.domain === domain) item.rule_blocked = kind === 'block';
  renderActivity(true); renderTrafficStats(); await loadDomains();
}
function switchPage(id) {
  if (activeTab === id) return;
  activeTab = id; document.querySelectorAll('.page').forEach(page => { page.hidden = page.id !== id; });
  document.querySelectorAll('nav button').forEach(tab => tab.setAttribute('aria-selected', String(tab.dataset.tab === id)));
  clearInterval(activityTimer); activityTimer = null; window.scrollTo(0, 0);
  if (id === 'activity') activityTimer = setInterval(() => { if (!document.hidden && !pending) loadActivity(); }, 2000);
  if (id === 'activity' && activityPayload) renderActivity();
  if (id === 'home') void loadActivity();
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
  element('interval').value = interval; syncUpdateInterval(); element('interval-open').disabled = false;
  element('auto-info').textContent = '后台状态：' + (stats?.auto_state || '待命') + ' · 下次：' + age(stats?.auto_next);
  fill('custom-sources', list.filter(source => source.custom).map(source => row(source.url, number(source.count) + ' 条 · ' + (source.err || source.result), button('删除', async () => { requireEnabled(); await run('sources', 'remove', source.url); await refresh(); }))), '尚未添加自定义来源');
}
async function loadSplash() {
  if (isVpnMode()) {
    element('splash-hits').textContent = '免 Root 版通过本地 VPN 拦截广告域名。Android 不允许访问其他应用的私有缓存，缓存锁定与自定义开屏路径需要 Root。';
    for (const control of element('splash').querySelectorAll('input,button,select')) control.disabled = true;
    return;
  }
  const [hits, rules] = await Promise.all([json(run('hits')), json(run('rules'))]);
  hitRules = hits.rules || []; userRules = rules.user || []; renderSplash();
  await describeApps([...hitRules, ...userRules]); renderSplash();
}
async function describeApps(rules) {
  const packages = [...new Set(rules.map(rule => rule.pkg))].filter(pkg => !appInfo.has(pkg));
  if (!window.XGuard) return;
  for (let offset = 0; offset < packages.length; offset += 256) {
    const batch = packages.slice(offset, offset + 256);
    try { const result = await json(exec(['apps', ...batch])); for (const pkg of batch) appInfo.set(pkg, {pkg}); for (const app of result.apps || []) appInfo.set(app.pkg, app); } catch {}
  }
}
function renderCandidates() {
  const filter = element('candidate-filter').value.toLowerCase().trim();
  const matching = candidates.filter(candidate => (candidate.pkg + ' ' + (appInfo.get(candidate.pkg)?.name || appNames[candidate.pkg] || '') + ' ' + candidate.path).toLowerCase().includes(filter));
  const groups = groupRules(matching);
  fill('candidates', groups.map(([pkg, items]) => {
    const group = document.createElement('details'); group.className = 'rule-group'; group.open = groups.length === 1;
    const heading = document.createElement('summary'); heading.append(appRow(pkg, items.length + ' 个候选缓存')); group.append(heading);
    let rendered = false;
    const populate = () => {
      if (rendered || !group.open) return; rendered = true;
      for (const candidate of items) group.append(row(candidate.path, number(candidate.kb) + ' KB', button('加入', async () => {
      await addRule(pkg, candidate.path);
      candidates = candidates.filter(item => item.pkg !== pkg || item.path !== candidate.path && !item.path.startsWith(candidate.path + '/'));
      renderCandidates();
    })));
    group.append(button('为此应用手动添加', () => { document.querySelector('#splash .editor-details').open = true; selectRuleApp(pkg); }));
    };
    group.addEventListener('toggle', populate); populate();
    return group;
  }), filter ? '没有匹配的缓存' : '没有待添加的候选缓存');
}
async function reloadSplashApp(pkg) {
  const [hits, rules] = await Promise.all([json(run('hits', pkg)), json(run('rules'))]);
  hitRules = hitRules.filter(rule => rule.pkg !== pkg).concat(hits.rules || []); userRules = rules.user || [];
  renderSplash(); await describeApps([{pkg}]); renderSplash();
}
function appRow(pkg, detail, action) {
  const result = row(appInfo.get(pkg)?.name || appNames[pkg] || pkg, detail, action);
  const text = result.firstChild; const packageLabel = document.createElement('small'); packageLabel.textContent = pkg; text.insertBefore(packageLabel, text.lastChild);
  const icon = document.createElement('img'); icon.className = 'app-icon'; icon.alt = ''; icon.width = 40; icon.height = 40; icon.loading = 'lazy'; icon.src = appInfo.get(pkg)?.icon || 'logo.svg'; result.prepend(icon); return result;
}
function groupRules(rules) { const groups = new Map(); for (const rule of rules) { if (!groups.has(rule.pkg)) groups.set(rule.pkg, []); groups.get(rule.pkg).push(rule); } return [...groups]; }
function selectRuleApp(pkg) { element('package').value = pkg; element('rule-path').focus(); }
function renderSplash() {
  renderHits();
  fill('user-rules', groupRules(userRules).map(([pkg, rules]) => {
    const group = document.createElement('details'); group.className = 'rule-group'; group.open = true;
    const heading = document.createElement('summary'); heading.append(appRow(pkg, rules.length + ' 条自定义路径')); group.append(heading);
    for (const rule of rules) group.append(row(rule.path, '自定义缓存路径', button('删除', async () => { requireEnabled(); if (await confirmAction('删除开屏规则', '删除后会解锁此自定义路径；内置同名规则会保留。')) { await run('rules', 'remove', pkg, rule.path); await reloadSplashApp(pkg); } })));
    group.append(button('为此应用添加规则', () => selectRuleApp(pkg))); return group;
  }), '没有自定义开屏规则，可从上方应用选择添加');
  const actual = new Set(hitRules.filter(rule => rule.state === 'locked').map(rule => rule.pkg)).size;
  element('locked-count').textContent = number(actual);
  element('splash-metric-detail').textContent = '已实际锁定应用';
  if (stats) { stats.splash_locked_apps = actual; stats.locked_count_cached = false; }
}
function renderHits() {
  const grouped = new Map(); const filter = element('filter-apps').value.toLowerCase();
  for (const rule of hitRules) { if (!(rule.pkg + ' ' + (appInfo.get(rule.pkg)?.name || appNames[rule.pkg] || '')).toLowerCase().includes(filter)) continue; if (!grouped.has(rule.pkg)) grouped.set(rule.pkg, []); grouped.get(rule.pkg).push(rule); }
  fill('splash-hits', Array.from(grouped, ([pkg, rules]) => {
    const skipped = rules.some(rule => rule.state === 'skipped'); const absent = rules.every(rule => rule.state === 'absent');
    const detail = absent ? '未安装' : skipped ? '已单独解锁' : '已锁定 ' + rules.filter(rule => rule.state === 'locked').length + ' / ' + rules.length + ' 条';
    const group = document.createElement('details'); group.className = 'rule-group';
    const heading = document.createElement('summary'); heading.append(appRow(pkg, detail + (rules.some(rule => rule.state === 'weak') ? ' · 存在弱占位' : ''))); group.append(heading);
    const labels = { locked:'已锁定', weak:'弱占位，应用可能重建', pending:'待锁定', skipped:'已解锁', absent:'未安装' };
    for (const rule of rules) group.append(row(rule.path, labels[rule.state] || rule.state));
    const actions = document.createElement('div'); actions.className = 'actions';
    actions.append(button('添加规则', () => { document.querySelector('#splash .editor-details').open = true; selectRuleApp(pkg); }));
    if (!absent) actions.append(button(skipped ? '恢复锁定' : '解锁', async () => { requireEnabled(); await run(skipped ? 'relock' : 'unlock', pkg); await reloadSplashApp(pkg); }));
    group.append(actions); return group;
  }), '没有匹配的开屏规则');
}
async function addRule(pkg, path) { requireEnabled(); if (isVpnMode()) throw new Error('缓存锁定需要 Root'); if (!/^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$/.test(pkg) || !path) throw new Error('请填写有效包名与路径'); toast('正在保存此应用的规则…'); await run('rules', 'add', pkg, path); await reloadSplashApp(pkg); const saved = hitRules.find(rule => rule.pkg === pkg && rule.path === path); toast(saved?.state === 'locked' ? '规则已保存，目录已锁定' : saved?.state === 'weak' ? '规则已保存，文件系统仅支持弱占位' : '规则已保存，应用未安装或目录暂不可锁定'); }

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
let intervalDraft = '24';
function syncUpdateInterval() {
  const option = element('interval').selectedOptions[0];
  element('interval-label').textContent = option?.textContent || '尚未读取';
  element('interval-hint').textContent = isVpnMode() ? '当前仅保存偏好，规则需手动更新' : element('interval').value === '0' ? '需要时手动同步规则' : '后台定期检查并同步规则';
}
function renderIntervalOptions() {
  element('interval-options').replaceChildren(...Array.from(element('interval').options, option => {
    const control = document.createElement('button'); control.className = 'interval-option';
    control.dataset.interval = option.value; control.setAttribute('aria-pressed', String(option.value === intervalDraft));
    const label = document.createElement('b'); label.textContent = option.textContent;
    const hint = document.createElement('small'); hint.textContent = ({0:'自行决定更新时间',6:'较频繁地同步',12:'每天检查两次',24:'日常使用推荐',48:'减少后台更新',168:'适合低频更新'})[option.value] || '保留当前自定义间隔';
    control.append(label, hint); control.onclick = () => { intervalDraft = option.value; renderIntervalOptions(); element('interval-options').querySelector('[data-interval="' + intervalDraft + '"]').focus(); };
    return control;
  }));
}
element('interval-open').onclick = () => {
  intervalDraft = element('interval').value; renderIntervalOptions(); element('interval-state').textContent = '';
  element('interval-note').textContent = isVpnMode() ? '免 Root 版暂未接入后台定时下载。选择仅保存偏好，更新规则仍需手动。' : '后台按所选间隔检查规则源，网络不可用时稍后重试。';
  element('interval-dialog').showModal();
};
element('interval-cancel').onclick = () => element('interval-dialog').close();
element('interval-save').onclick = () => task(async () => {
  const value = intervalDraft;
  element('interval-state').textContent = '正在保存…';
  try {
    await run('sources', 'interval', value); element('interval').value = value; syncUpdateInterval();
    element('interval-dialog').close(); toast(isVpnMode() ? '间隔偏好已保存，规则仍需手动更新' : '更新间隔已保存'); await loadSources();
  } catch (error) { element('interval-state').textContent = '保存失败：' + error.message; }
}, element('interval-save'));
element('add-source').onclick = () => task(async () => { requireEnabled(); const url = element('source-url').value.trim(); if (!/^https?:\/\/\S+$/.test(url)) throw new Error('地址需要以 http:// 或 https:// 开头'); await run('sources', 'add', url); element('source-url').value = ''; toast('已添加，更新规则后下载'); await refresh(); });
element('reset-sources').onclick = () => task(async () => { requireEnabled(); if (await confirmAction('恢复默认来源', '恢复默认内置来源并清空自定义来源。')) { await run('sources', 'reset'); await refresh(); } });
element('filter-apps').oninput = renderHits;
element('add-rule').onclick = () => task(async () => { await addRule(element('package').value.trim(), element('rule-path').value.trim()); element('rule-path').value = ''; }, element('add-rule'));
element('discover').onclick = () => task(async () => {
  const pkg = element('package').value.trim();
  if (pkg && !/^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$/.test(pkg)) throw new Error('包名格式无效');
  const depth = element('scan-depth').value;
  element('scan-state').textContent = '正在扫描 ' + (pkg || '已安装应用') + '，深度 ' + depth + ' 层…';
  try {
    const result = await json(run('discover', pkg, depth)); candidates = result.candidates || [];
    renderCandidates(); await describeApps(candidates); renderCandidates();
    element('scan-state').textContent = '扫描完成 · ' + groupRules(candidates).length + ' 个应用 · ' + candidates.length + ' 个候选 · 每个应用的每个存储区域最多 60 项';
  } catch (error) { element('scan-state').textContent = '扫描失败：' + error.message; throw error; }
}, element('discover'));
element('candidate-filter').oninput = renderCandidates;
element('guard').onchange = () => task(async () => { requireEnabled(); if (element('guard').checked && !await confirmAction('开启 HTTPDNS IP 拦截', '这可能影响支付、网盘或登录。遇到异常请关闭。')) { element('guard').checked = false; return; } await run('guard', element('guard').checked ? 'on' : 'off'); await refresh(); });
for (const [id, key] of [['proxy-yield', 'proxy_yield'], ['hide', 'hide']]) element(id).onchange = () => task(async () => { requireEnabled(); await run('set', key, element(id).checked ? '1' : '0'); toast(key === 'hide' ? '已保存，重启后完全生效' : '已保存'); await refresh(); });
element('mount-mode').onchange = () => task(async () => { requireEnabled(); await run('set', 'mount_mode', element('mount-mode').value); await refresh(); });
element('save-max').onclick = () => task(async () => { requireEnabled(); await run('set', 'hosts_max', element('max-rules').value); toast('规则上限已保存'); await refresh(); });
element('logs').onclick = () => task(async () => {
  const dialog = element('logs-dialog'), output = element('log-output');
  output.hidden = true; output.textContent = ''; element('logs-state').textContent = '正在读取日志…'; dialog.showModal();
  const sections = ['', '', ''];
  await Promise.all([['核心日志', () => exec(['log'])], ['防护日志', () => exec(['log', 'shield'])], ['运行状态', () => run('stats', 'quick')]].map(async ([title, read], index) => {
    try { const text = await read(); sections[index] = '【' + title + '】\n' + (text.trim() || '暂无日志'); }
    catch (error) { sections[index] = '【' + title + '】读取失败：' + error.message; }
    output.textContent = sections.filter(Boolean).join('\n\n'); output.hidden = false;
  }));
  element('logs-state').textContent = '读取完成，可关闭窗口返回设置。';
}, element('logs'));
element('safe-mode').onclick = () => task(async () => { const enabled = !status.safe_mode; if (await confirmAction(enabled ? '开启安全模式' : '关闭安全模式', '重启手机后生效。')) { await exec(['safe', enabled ? 'on' : 'off']); toast('已保存，请重启手机'); await refresh(); } });
element('activity-open').onclick = () => switchPage('activity');
element('activity-refresh').onclick = () => task(loadActivity, element('activity-refresh'));
element('activity-clear').onclick = () => task(async () => { if (await confirmAction('清空域名记录', '清空最近观察到的域名，防护规则会保留。')) { activityPayload = await json(run('activity', 'clear')); renderActivity(true); renderTrafficStats(); } }, element('activity-clear'));
element('monitor-toggle').onclick = () => task(async () => { activityPayload = await json(run('activity', activityPayload?.collector?.enabled === false ? 'enable' : 'disable')); renderActivity(true); renderTrafficStats(); }, element('monitor-toggle'));
element('activity-search').oninput = () => renderActivity(true);
document.querySelectorAll('[data-filter]').forEach(control => { control.onclick = () => { activityFilter = control.dataset.filter; document.querySelectorAll('[data-filter]').forEach(button => button.setAttribute('aria-selected', String(button === control))); renderActivity(true); }; });
document.addEventListener('visibilitychange', () => { if (!document.hidden && activeTab === 'activity' && !pending) loadActivity(); });
element('show-license').onclick = () => element('license-dialog').showModal();
element('show-donate').onclick = () => element('donate-dialog').showModal();
const depthOptions = {6:['快速扫描 · 6 层', '先查找常见位置，耗时较少'], 8:['标准扫描 · 8 层', '兼顾扫描耗时与目录覆盖'], 12:['深入扫描 · 12 层', '查找更深目录，可能需要更久']};
function syncScanDepth() {
  const depth = element('scan-depth').value, [label, hint] = depthOptions[depth] || depthOptions[8];
  element('scan-depth-label').textContent = label; element('scan-depth-hint').textContent = hint;
  document.querySelectorAll('[data-depth]').forEach(control => control.setAttribute('aria-pressed', String(control.dataset.depth === depth)));
}
element('scan-depth').onchange = syncScanDepth;
element('scan-depth-open').onclick = () => { syncScanDepth(); element('scan-depth-dialog').showModal(); };
document.querySelectorAll('[data-depth]').forEach(control => { control.onclick = () => { element('scan-depth').value = control.dataset.depth; syncScanDepth(); element('scan-depth-dialog').close(); }; });
element('display-theme').value = window.XGuardTheme?.preference || 'system';
element('display-theme').onchange = () => window.XGuardTheme?.set(element('display-theme').value);
if (noRoot) {
  for (const control of element('mount-mode').closest('article').children) control.hidden = !control.classList.contains('support-card');
  element('safe-mode').hidden = true;
  element('runtime').parentElement.querySelector('p:last-child').textContent = '使用 Android 本地 VPN 服务；缓存锁定需要 Root。';
  element('traffic-title').textContent = '拦截统计';
}
setInterval(() => { if (activeTab === 'home' && !document.hidden && !pending && status && rootReady) void loadActivity(); }, 5000);
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
else void refresh().catch(error => toast(error.message));
