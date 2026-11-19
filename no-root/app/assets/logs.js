'use strict';
(() => {
  const get = id => document.getElementById(id);
  const components = {core:'系统', xguardd:'后台服务', shield:'防护', watchdog:'无障碍守护', conflict:'模块冲突', monitor:'域名采集'};
  const localTime = new Intl.DateTimeFormat('zh-CN', {month:'2-digit', day:'2-digit', hour:'2-digit', minute:'2-digit', second:'2-digit', hourCycle:'h23'});
  const number = new Intl.NumberFormat('zh-CN');
  const health = {no_rules:'缺少可用规则', not_mounted:'域名规则未生效', daemon_stopped:'后台服务未运行', collector_stopped:'域名采集未运行', vpn_stopped:'本地 VPN 未运行', permission_required:'需要授予 VPN 权限'};
  let request = 0;
  let events = [];

  function rootMessage(message) {
    const update = /^规则更新：(\w+)（(\d+)\/(\d+) 个源成功，hosts (\d+) 条）$/.exec(message);
    if (update) {
      const partial = Number(update[2]) < Number(update[3]);
      const title = update[1] === 'fail' ? '域名规则更新失败' : partial ? '部分域名规则来源更新失败' : update[1] === 'same' ? '域名规则已是最新' : '域名规则更新完成';
      return {title, detail:'成功更新 ' + update[2] + ' / ' + update[3] + ' 个来源，当前共有 ' + number.format(update[4]) + ' 条规则。', attention:partial || update[1] === 'fail'};
    }
    const translations = [
      [/^(?:hosts 已挂载|hosts 已用 overlay 挂载|hosts 已写入)/, '域名规则已应用', '如果应用仍使用旧的网络结果，可尝试重开该应用。'],
      [/^hosts 已撤下/, '域名规则已停用'],
      [/^hosts 挂载失败|^overlay 挂载失败/, '域名规则应用失败', '可在设置中运行「检查运行」，查看当前状态。', true],
      [/^bind 挂载失败.*尝试 overlay/, '正在尝试另一种域名规则挂载方式'],
      [/^规则源下载失败/, '域名规则来源下载失败', '可在「域名 → 规则订阅」查看来源状态。', true],
      [/^规则源内容无效/, '下载的域名规则内容不完整', '可在「域名 → 规则订阅」查看来源状态。', true],
      [/^自动更新开始/, '已开始自动更新域名规则'],
      [/^自动更新完成/, '域名规则自动更新完成'],
      [/^自动更新：.*没有网络/, '自动更新等待网络超时', '连网后可在「域名 → 规则订阅」手动更新。', true],
      [/^自动更新：重试/, '多次尝试后仍有规则来源未更新', '', true],
      [/^已启动 pid=/, '后台服务已启动'],
      [/^无障碍守护已请求重新绑定/, '已请求恢复 XGuard 无障碍服务'],
      [/^chattr \+i 不可用/, '部分开屏缓存只能临时占位', '目标应用可能重新生成这些文件。', true],
      [/^start @ /, '正在启动防护模块'],
      [/^放行名单 (?:add|del|remove) /, message.replace(/^放行名单 (add|del|remove) /, (_, op) => op === 'add' ? '已放行域名 ' : '已移出放行名单 ')],
      [/^规则源 \S+ → (?:enable|disable)/, message.replace(/^规则源 (\S+) → (enable|disable).*$/, (_, id, op) => (op === 'enable' ? '已启用规则来源 ' : '已停用规则来源 ') + id)]
    ];
    const translated = translations.find(([pattern]) => pattern.test(message));
    if (translated) return {title:translated[1], detail:translated[2] || '', attention:Boolean(translated[3])};
    if (/^[\x20-\x7e]+$/.test(message) || /^事件 /.test(message)) {
      return {title:'记录了一条运行信息', attention:false};
    }
    return {title:message, attention:/失败|异常|冲突|警告|未完成开机|安全模式|超时/.test(message)};
  }

  function parseRoot(parts) {
    const seen = new Set();
    const rows = [];
    for (const part of parts) {
      for (const line of part.trim().split(/\r?\n/).reverse()) {
        if (!line.trim() || seen.has(line)) continue;
        seen.add(line);
        const match = /^(?:(\d{4})-)?(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d) \[([^\]]+)\] (.*)$/.exec(line);
        if (!match) {
          rows.push({title:'记录了一条运行信息', component:'系统', time:'', timestamp:0});
          continue;
        }
        const [, year, month, day, hour, minute, second, source, message] = match;
        const now = new Date();
        const time = new Date(year ? Number(year) : now.getFullYear(), Number(month)-1, Number(day), Number(hour), Number(minute), Number(second));
        if (!year && time.getTime() > now.getTime() + 86400000) time.setFullYear(time.getFullYear()-1);
        rows.push({component:components[source] || '系统', time:month + '-' + day + ' ' + hour + ':' + minute + ':' + second, timestamp:time.getTime(), ...rootMessage(message)});
      }
    }
    return rows.sort((a,b) => b.timestamp-a.timestamp);
  }

  function parseVpn(items) {
    return items.slice().reverse().map(item => ({
      title:item.failed ? 'DNS 查询失败' : item.rule_blocked ? '已拦截域名请求' : '未拦截域名请求',
      detail:item.domain, component:'本地 VPN', attention:Boolean(item.failed),
      time:item.time > 0 ? localTime.format(item.time * 1000) : ''
    }));
  }

  function append(container, tag, text, className) {
    const node = document.createElement(tag);
    node.textContent = text;
    if (className) node.className = className;
    container.append(node);
    return node;
  }

  function renderEvents() {
    const list = get('log-events');
    const visible = get('log-filter').value === 'attention' ? events.filter(event => event.attention) : events;
    list.replaceChildren();
    if (events.length && !visible.length) append(list, 'li', '这些记录里没有需要留意的事件。');
    for (const event of visible.slice(0,40)) {
      const item = append(list, 'li', '');
      const meta = append(item, 'div', '', 'log-event-meta');
      if (event.time) append(meta, 'span', event.time);
      append(meta, 'span', event.component);
      if (event.attention) append(meta, 'span', '需要留意', 'log-attention');
      append(item, 'strong', event.title, 'log-event-title');
      if (event.detail) append(item, 'p', event.detail);
    }
    if (visible.length > 40) append(list, 'li', '仅列出最近 40 条，更多记录可展开下方原始记录。');
  }

  async function readPart(source, load) {
    try { return {source, value:await load()}; }
    catch (error) { return {source, error:error.message || String(error)}; }
  }

  async function open({vpn, exec, run, status}) {
    const dialog = get('logs-dialog');
    if (dialog.open) return;
    const current = ++request;
    const state = get('logs-state'), summary = get('log-summary'), details = get('log-details');
    events = [];
    summary.replaceChildren(); summary.hidden = true;
    details.hidden = true; details.open = false;
    get('log-output').textContent = '';
    get('log-filter-label').hidden = true;
    get('log-filter').value = 'all';
    get('log-filter').onchange = renderEvents;
    renderEvents();
    state.textContent = '正在读取运行记录…';
    dialog.showModal();
    const json = async result => JSON.parse(await result);
    const parts = await Promise.all([
      readPart('防护状态', () => json(exec(['status']))),
      readPart('最近检查', () => json(run('recovery', 'status'))),
      ...(vpn ? [readPart('DNS 记录', () => json(run('activity')))] : [
        readPart('系统日志', () => exec(['log'])), readPart('防护日志', () => exec(['log','shield']))
      ])
    ]);
    if (current !== request || !dialog.open) return;
    const feature = (parts[0].value || status)?.features?.[0];
    const recent = parts[1].value?.health || {};
    const warnings = health[recent.state];
    const currentState = parts[0].error ? '' : parts[0].value?.safe_mode ? '安全模式已开启' : feature?.enabled === false ? '防护已关闭' : Number(feature?.pause_until) > 0 ? '防护临时暂停' : feature?.enabled ? '防护开关已开启' : '';
    if (currentState) append(summary, 'strong', currentState);
    if (recent.checked_at > 0 && feature?.enabled && !(Number(feature.pause_until) > 0)) {
      const result = recent.state === 'ok' ? '运行正常' : warnings;
      if (result) append(summary, 'p', '最近检查 · ' + localTime.format(recent.checked_at * 1000) + ' · ' + result);
    }
    if (vpn) {
      const activity = parts[2].value;
      const totals = activity?.snapshot?.totals;
      events = parseVpn(activity?.snapshot?.items || []);
      if (activity?.collector) {
        append(summary, 'p', activity.collector.running ? '本地 VPN 运行中' : '本地 VPN 未运行');
        if (activity.collector.enabled === false) append(summary, 'p', '域名采集已暂停。');
      }
      if (totals) append(summary, 'p', '累计 ' + number.format(totals.queries || 0) + ' 次查询 · ' + number.format(totals.blocked || 0) + ' 次拦截 · ' + number.format(totals.failed || 0) + ' 次查询失败');
    } else {
      events = parseRoot(parts.slice(2).map(part => part.value || ''));
    }
    for (const part of parts.filter(part => part.error)) events.unshift({title:part.source + '暂时读取失败', component:'读取日志', detail:'可关闭此窗口后重试。', attention:true});
    summary.hidden = !summary.childElementCount;
    state.textContent = events.length ? (vpn ? '最近 DNS 查询记录' : '最近运行事件') : vpn ? '暂无 DNS 查询记录。开启域名采集后，这里会显示新记录。' : '暂无运行事件。';
    get('log-filter-label').hidden = events.length === 0;
    get('log-output').textContent = parts.map(part => '【' + part.source + '】\n' + (part.error || (typeof part.value === 'string' ? part.value.trim() : JSON.stringify(part.value, null, 2)) || '暂无记录')).join('\n\n');
    details.hidden = false;
    renderEvents();
  }

  window.XGuardLogs = {open};
})();
