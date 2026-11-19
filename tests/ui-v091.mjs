import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';

const require = createRequire(path.resolve(process.env.XGUARD_TEST_TOOLS || '../.xiezhi-tools', 'package.json'));
const {chromium} = require('playwright');
const browser = await chromium.launch({headless:true, executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'});
fs.mkdirSync('dist/device-check', {recursive:true});
try {
  for (const vpn of [false, true]) {
    const page = await browser.newPage({viewport:{width:390,height:844}});
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.addInitScript(vpnMode => {
      window.calls = [];
      window.a11y = false;
      window.vpnReady = localStorage.getItem('test.vpn') === '1';
      let guard = false;
      let hideFromRecents = false;
      const list = [
        {id:'xguard-local', name:'本地补充', desc:'本地规则', enabled:true, count:3, skipped:0, result:'内置'},
        {id:'lin-arm', name:'网络订阅', desc:'在线来源', url:'https://example.com/preset.json5', enabled:false, count:0, skipped:0, result:'未下载'}
      ];
      window.XGuard = {
        getMode:() => vpnMode ? 'vpn' : 'root',
        isVpnPrepared:() => window.vpnReady,
        isAccessibilityEnabled:() => window.a11y,
        openAccessibilitySettings() { window.calls.push(['accessibility-settings']); },
        getHideFromRecents() { return hideFromRecents; },
        setHideFromRecents(value) { hideFromRecents = Boolean(value); window.calls.push(['hide-from-recents', String(value)]); },
        requestRoot(callback) { setTimeout(() => window[callback](0, '0'), 5); },
        requestVpn(callback) { window.vpnReady = true; localStorage.setItem('test.vpn', '1'); setTimeout(() => window[callback](0, ''), 5); },
        haptic() {},
        execute(raw, callback) {
          const args = JSON.parse(raw); window.calls.push(args);
          let result = {};
          if (args[0] === 'gkd') {
            if (args[1] === 'toggle') list.find(source => source.id === args[2]).enabled = args[3] === '1';
            if (args[1] === 'guard') guard = args[2] === '1';
            if (args[1] === 'add') list.push({id:'custom-test', name:'自定义订阅', desc:'下载完成', url:args[2], custom:true, enabled:true, count:4, skipped:12, result:'已缓存'});
            if (args[1] === 'remove') list.splice(list.findIndex(source => source.id === args[2]), 1);
            result = args[1] === 'license' ? 'GNU GENERAL PUBLIC LICENSE\nVersion 3, 29 June 2007' : {list, accessibility_guard:guard};
          } else if (args[0] === 'status') result = {version:'0.9.2', root:'test', daemon:'running', features:[{enabled:true, health:'ok'}]};
          else if (args[2] === 'stats') result = {hosts_rules:100, mode:vpnMode?'dns-vpn':'hosts', sources:1};
          else if (args[2] === 'activity') result = {collector:{enabled:true,running:true}, snapshot:{items:[], observed:0, matched:0}};
          else if (args[2] === 'sources') result = {list:[], interval_h:24};
          else if (args[2] === 'recovery') result = {pause_until:0, health:{}};
          const output = typeof result === 'string' ? result : JSON.stringify(result);
          setTimeout(() => window[callback]?.(0, output, ''), 5);
        }
      };
    }, vpn);
    await page.goto(pathToFileURL(path.resolve(vpn ? 'no-root/app/assets/index.html' : 'module/webroot/index.html')).href);
    assert(await page.locator('#root-dialog').evaluate(dialog => dialog.open));
    assert.deepEqual(await page.locator('.bottom-nav button span').allTextContents(), ['概览','域名','开屏','设置']);
    await page.locator('#root-authorize').click();
    await page.waitForFunction(() => !document.getElementById('root-authorize').disabled);
    assert(await page.locator('#root-dialog').evaluate(dialog => dialog.open));
    assert.match(await page.locator('#root-status').textContent(), /已授权，请开启无障碍/);
    await page.locator('#root-open-accessibility').click();
    assert(await page.evaluate(() => window.calls.some(args => args[0] === 'accessibility-settings')));
    await page.evaluate(() => { window.a11y = true; window.xguardPermissionsChanged(); });
    assert.equal(await page.locator('#root-later').textContent(), '完成');
    await page.locator('#root-authorize').click();
    await page.waitForFunction(() => !document.getElementById('root-dialog').open);
    assert.equal(await page.evaluate(() => localStorage.getItem('xguard.permissions.v091')), '1');
    await page.locator('.bottom-nav [data-tab=' + (vpn ? 'gkd' : 'splash') + ']').click();
    if (!vpn) await page.locator('#splash [data-page=gkd]').click();
    await page.locator('#gkd-source-list input').first().waitFor();
    assert.equal(await page.locator('#gkd-hide-recents').isChecked(), false);
    await page.locator('#gkd-hide-recents').check();
    assert.equal(await page.locator('#gkd-hide-recents').isChecked(), true);
    assert(await page.evaluate(() => window.calls.some(args => args.join('|') === 'hide-from-recents|true')));
    assert(await page.locator('#gkd').isVisible());
    assert.equal(await page.locator('.bottom-nav button[aria-selected=true] span').textContent(), '开屏');
    const duration = await page.locator('.nav-lens').evaluate(lens => getComputedStyle(lens).transitionDuration);
    assert.equal(duration, '0.55s');
    assert(await page.locator('#gkd-source-list input').first().isChecked());
    await page.locator('#gkd-source-list input').first().uncheck();
    await page.waitForFunction(() => document.getElementById('gkd').getAttribute('aria-busy') === 'false');
    assert.equal(await page.locator('#gkd-source-list input:checked').count(), 0);
    if (vpn) assert(await page.locator('#gkd-accessibility-guard').isDisabled());
    else {
      await page.locator('#gkd-accessibility-guard').check();
      await page.waitForFunction(() => document.getElementById('gkd').getAttribute('aria-busy') === 'false');
      assert(await page.evaluate(() => window.calls.some(args => args.join('|') === 'gkd|guard|1')));
      assert(await page.locator('#gkd-accessibility-guard').isChecked());
    }
    await page.locator('#gkd-source-url').fill('https://example.com/custom.json5');
    await page.locator('#gkd-source-add').click();
    await page.locator('#gkd-source-list').getByText('自定义订阅', {exact:true}).waitFor();
    assert(await page.evaluate(() => window.calls.some(args => args.join('|') === 'gkd|add|https://example.com/custom.json5')));
    assert.equal(await page.locator('#gkd-source-list input:checked').count(), 1);
    await page.locator('#gkd-source-list').getByRole('button', {name:'删除', exact:true}).click();
    await page.locator('#confirm-yes').click();
    await page.waitForFunction(() => !document.querySelector('#gkd-source-list input:checked'));
    await page.setViewportSize({width:320,height:740});
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
    await page.screenshot({path:'dist/device-check/091-' + (vpn?'vpn':'root') + '-gkd.png', fullPage:true});
    await page.locator('[data-tab=settings]').click();
    await page.locator('.credits summary').click();
    assert.equal(await page.locator('a[href="https://github.com/topics/gkd-subscription"]').count(), 1);
    await page.locator('#show-gpl-license').click();
    await page.locator('dialog[open] pre').getByText(/GNU GENERAL PUBLIC LICENSE/).waitFor();
    await page.keyboard.press('Escape');
    assert.deepEqual(errors, []);
    await page.close();
  }
  console.log('PASS: first-open Root/VPN and accessibility guide, four tabs, slow lens animation, independent/all-off subscriptions, native download/delete commands, guard switch and GPL entry, 320px layout');
} finally { await browser.close(); }
