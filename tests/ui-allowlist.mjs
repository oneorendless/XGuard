import assert from 'node:assert/strict';
import path from 'node:path';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

const require = createRequire(path.resolve(process.env.XGUARD_TEST_TOOLS || '../.xiezhi-tools', 'package.json'));
const { chromium } = require('playwright');
const browser = await chromium.launch({ headless: true, channel: 'msedge' });
try {
  for (const vpn of [false, true]) {
    const page = await browser.newPage({ viewport: {width: 320, height: 740} });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.addInitScript(vpnMode => {
      window.XGuard = {
        getMode: () => vpnMode ? 'vpn' : 'root',
        isVpnPrepared: () => false,
        isAccessibilityEnabled: () => false,
        execute(raw, callback) {
          const args = JSON.parse(raw);
          let data = { features: [{enabled: false, health: 'ok'}] }, code = 0, detail = '';
          if (args[1] === 'allowlist') {
            const apps = [{pkg: 'com.xiaomi.shop', name: '小米商城'}, {pkg: 'com.xiaomi.vipaccount', name: '小米社区'}];
            if (args.length === 2) data = { apps: apps.map(app => ({...app, selected: localStorage.getItem(app.pkg) === '1'})) };
            else if (window.failAllowlist) { code = 1; detail = '保存失败'; }
            else { localStorage.setItem(args[2], args[3]); data = {}; }
          } else if (args[0] === 'gkd') data = {list: []};
          setTimeout(() => window[callback]?.(code, code ? '' : JSON.stringify(data), detail), 5);
        }
      };
    }, vpn);
    await page.goto(pathToFileURL(path.resolve(vpn ? 'no-root/app/assets/index.html' : 'module/webroot/index.html')).href);
    const open = async () => {
      await page.locator('#root-later').click();
      await page.locator('.bottom-nav [data-tab=' + (vpn ? 'gkd' : 'splash') + ']').click();
      if (!vpn) await page.locator('#splash [data-page=gkd]').click();
      await page.getByText('应用白名单', {exact:true}).click();
      await page.locator('#gkd-app-list label').last().waitFor();
    };
    await open();
    await page.locator('#gkd-app-search').fill('com.xiaomi.shop');
    const toggle = page.locator('#gkd-app-list input');
    assert.equal(await toggle.count(), 1);
    await toggle.check();
    await page.waitForFunction(() => document.querySelector('#gkd-app-count').textContent.includes('1'));
    await page.reload();
    await open();
    const mall = page.getByLabel(/小米商城/);
    assert.equal(await mall.isChecked(), true);
    await page.evaluate(() => { window.failAllowlist = true; });
    await mall.uncheck();
    await page.waitForFunction(() => document.querySelector('#toast').textContent.includes('保存失败'));
    assert.equal(await mall.isChecked(), true);
    await page.evaluate(() => { window.failAllowlist = false; });
    await mall.uncheck();
    await page.waitForFunction(() => document.querySelector('#gkd-app-count').textContent.includes('0'));
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
    assert.deepEqual(errors, []);
    await page.close();
  }
  console.log('PASS: Root/VPN app selection, search, persistence, failure rollback, removal and 320px layout');
} finally { await browser.close(); }
