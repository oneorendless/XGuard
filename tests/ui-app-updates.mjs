import assert from 'node:assert/strict';
import path from 'node:path';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

const require = createRequire(path.resolve(process.env.XGUARD_TEST_TOOLS || '../.xiezhi-tools', 'package.json'));
const { chromium } = require('playwright');
const browser = await chromium.launch({headless: true, channel: 'msedge'});
try {
  for (const vpn of [false, true]) {
    const page = await browser.newPage({viewport: {width: 320, height: 740}});
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.addInitScript(vpnMode => {
      window.checks = 0;
      window.downloads = 0;
      window.updateState = 'available';
      window.XGuard = {
        getMode: () => vpnMode ? 'vpn' : 'root',
        isVpnPrepared: () => false,
        isAccessibilityEnabled: () => false,
        openAppUpdate: () => { window.downloads++; },
        execute(raw, callback) {
          const [command] = JSON.parse(raw);
          if (command === 'app-update') {
            window.checks++;
            if (window.updateState === 'offline') { window[callback](1, 'offline', ''); return; }
            window[callback](0, JSON.stringify({current: '0.9.5', latest: '0.9.10', state: window.updateState}), '');
          } else {
            window[callback](0, JSON.stringify({version: 'v0.9.5', features: [], list: []}), '');
          }
        }
      };
    }, vpn);
    const url = pathToFileURL(path.resolve(vpn ? 'no-root/app/assets/index.html' : 'module/webroot/index.html')).href;
    await page.goto(url);
    await page.waitForFunction(() => window.checks === 1 && document.getElementById('app-update-status').textContent.includes('0.9.10'));
    const dialog = page.locator('#app-update-dialog');
    assert.equal(await dialog.isVisible(), false);
    await page.locator('#root-later').click();
    await dialog.waitFor();
    assert.match(await dialog.textContent(), /当前版本 0\.9\.5 → 新版本 0\.9\.10/);
    assert.match(await dialog.textContent(), vpn ? /Android 提示覆盖安装/ : /Root 管理器.*重启/);
    await dialog.getByRole('button', {name: '稍后'}).click();
    await dialog.waitFor({state: 'hidden'});
    assert.equal(await page.evaluate(() => window.downloads), 0);

    await page.locator('.bottom-nav [data-tab=settings]').click();
    const check = page.getByRole('button', {name: '检查更新'});
    await check.click();
    await dialog.getByRole('button', {name: vpn ? '下载 APK' : '下载模块 ZIP'}).click();
    assert.equal(await page.evaluate(() => window.downloads), 1);
    for (const [state, message] of [['offline', '检查失败'], ['missing', '暂无适用于当前版本的安装包'], ['current', '已是最新版本']]) {
      await page.evaluate(value => { window.updateState = value; }, state);
      await check.click();
      await page.waitForFunction(text => document.getElementById('app-update-status').textContent.includes(text), message);
      assert.equal(await dialog.isVisible(), false);
    }
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
    assert.deepEqual(errors, []);
    await page.close();

    const unsupported = await browser.newPage();
    await unsupported.goto(url);
    assert.equal(await unsupported.locator('#app-update-card').isVisible(), false);
    await unsupported.close();
  }
  console.log('PASS: both editions defer the update prompt, allow dismissal and manual retry, and choose the right install action');
} finally { await browser.close(); }
