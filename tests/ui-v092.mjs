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
      localStorage.setItem('xguard.permissions.v091', '1');
      window.recentsCalls = [];
      window.XGuard = {
        getMode:() => vpnMode ? 'vpn' : 'root',
        isVpnPrepared:() => false,
        isAccessibilityEnabled:() => false,
        getHideFromRecents:() => localStorage.getItem('test.recents') === '1',
        setHideFromRecents(value) {
          if (window.failRecents) throw new Error('保存失败');
          window.recentsCalls.push(value);
          localStorage.setItem('test.recents', value ? '1' : '0');
        },
        haptic() {},
        execute(raw, callback) {
          const args = JSON.parse(raw);
          const result = args[0] === 'gkd' ? {list:[]} : {features:[{enabled:false,health:'ok'}],version:'0.9.2'};
          setTimeout(() => window[callback]?.(0, JSON.stringify(result), ''), 5);
        }
      };
    }, vpn);
    await page.goto(pathToFileURL(path.resolve(vpn ? 'no-root/app/assets/index.html' : 'module/webroot/index.html')).href);
    await page.locator('#root-later').click();
    await page.locator('[data-tab=gkd]').click();
    const toggle = page.locator('#gkd-hide-recents');
    assert.equal(await toggle.isChecked(), false);
    assert.equal(await toggle.isEnabled(), true);
    assert(await toggle.evaluate(control => {
      const card = control.closest('article');
      return card === document.querySelector('#gkd article') && card.getBoundingClientRect().bottom < innerHeight - 100;
    }));
    await toggle.check();
    assert.deepEqual(await page.evaluate(() => window.recentsCalls), [true]);
    assert.match(await page.locator('#gkd-recents-state').textContent(), /已隐藏/);
    await page.reload();
    await page.locator('#root-later').click();
    await page.locator('[data-tab=gkd]').click();
    assert.equal(await toggle.isChecked(), true);
    await page.evaluate(() => { window.failRecents = true; });
    await toggle.click();
    assert.equal(await toggle.isChecked(), true);
    assert.match(await page.locator('#toast').textContent(), /保存失败/);
    await page.evaluate(() => { window.failRecents = false; });
    await toggle.uncheck();
    assert.equal(await toggle.isChecked(), false);
    await page.reload();
    await page.locator('#root-later').click();
    await page.locator('[data-tab=gkd]').click();
    assert.equal(await toggle.isChecked(), false);
    for (const theme of ['light', 'dark']) {
      await page.evaluate(value => window.XGuardTheme?.set(value), theme);
      await page.setViewportSize({width:320,height:740});
      assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
      await page.screenshot({path:`dist/device-check/092-${vpn?'vpn':'root'}-${theme}-gkd.png`, fullPage:true});
    }
    await page.evaluate(() => { delete window.XGuard.getHideFromRecents; delete window.XGuard.setHideFromRecents; window.xguardPermissionsChanged(); });
    assert.equal(await toggle.isDisabled(), true);
    assert.match(await page.locator('#gkd-recents-state').textContent(), /不支持/);
    assert.deepEqual(errors, []);
    await page.close();
  }
  console.log('PASS: Root/VPN prominent recent-task switch, no permission dependency, on/off persistence, failure recovery, unsupported bridge, light/dark 320px layout');
} finally { await browser.close(); }
