import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
const require = createRequire(path.resolve(process.env.XGUARD_TEST_TOOLS || '../.xiezhi-tools', 'package.json'));
const {chromium} = require('playwright');
const output = path.resolve('dist/device-check'); fs.mkdirSync(output, {recursive:true});
const browser = await chromium.launch({headless:true, executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'});
for (const vpn of [false, true]) {
  const page = await browser.newPage({viewport:{width:390,height:844}, colorScheme:'dark'});
  const errors = []; page.on('pageerror', error => errors.push(error.message));
  await page.addInitScript(vpn => {
    window.localStorage.setItem('xguard.rootConfirmed.v1','1');
    window.calls = []; window.cspErrors = [];
    document.addEventListener('securitypolicyviolation', event => window.cspErrors.push(event.violatedDirective));
    const rules = [{pkg:'com.xunlei.downloadprovider', path:'cache/afs/splash', state:'locked'}, {pkg:'com.xunlei.downloadprovider', path:'cache/weak', state:'weak'}];
    const users = [{pkg:'com.xunlei.downloadprovider',path:'cache/weak'}];
    window.XGuard = {getMode:() => vpn?'vpn':'root', isVpnPrepared:()=>true, haptic(){}, execute(raw, callback) {
      const args = JSON.parse(raw); window.calls.push(args);
      let result = {}; const action = args[2], op = args[3];
      if (args[0] === 'status') result = {version:'0.8.5',root:'ksu',daemon:'running',safe_mode:false,features:[{enabled:true,health:'ok',summary:'防护已开启'}]};
      if (args[0] === 'apps') result = {apps:[{pkg:'com.xunlei.downloadprovider',name:'迅雷',icon:'logo.svg'}]};
      if (action === 'stats') result = {splash_locked_apps:1, hosts_rules:10000,sources:5};
      if (action === 'activity') result = {collector:{running:true,enabled:true},snapshot:{observed:100,matched:25,updated:Date.now()/1000,items:[],totals:{queries:100,blocked:25,failed:2,started:Date.now()/1000}}};
      if (action === 'hits') result = {rules:op?rules.filter(rule=>rule.pkg===op):rules};
      if (action === 'discover') result = {depth:Number(args[4]), candidates:[{pkg:'com.xunlei.downloadprovider',path:'cache/a/b/c/d/e/f/g/splash',kb:24},{pkg:'com.xunlei.downloadprovider',path:'cache/other_adcache',kb:8},{pkg:'tv.danmaku.bili',path:'files/new_splash',kb:4}]};
      if (action === 'rules') {
        if (op === 'add') { rules.push({pkg:args[4],path:args[5],state:'locked'}); users.push({pkg:args[4],path:args[5]}); }
        if (op === 'remove') { const i=users.findIndex(rule=>rule.pkg===args[4] && rule.path===args[5]); if (i>=0) users.splice(i,1); }
        result = {user:users};
      }
      setTimeout(()=>window[callback]?.(0,JSON.stringify(result),''), op==='add'?250:20);
    }};
  }, vpn);
  await page.goto(pathToFileURL(path.resolve(vpn?'no-root/app/assets/index.html':'module/webroot/index.html')).href);
  await page.waitForFunction(()=>document.getElementById('traffic-total').textContent==='100');
  assert.equal(await page.locator('#traffic-blocked').textContent(), '25');
  assert.equal(await page.locator('#traffic-ratio').textContent(), '25.0%');
  assert.equal(await page.locator('#locked-count').textContent(), vpn?'需 Root':'1');
  await page.screenshot({path:path.join(output,vpn?'vpn-home-dark.png':'root-home-dark.png'),fullPage:true});
  await page.locator('[data-tab=splash]').click();
  if (vpn) {
    await page.locator('#splash-hits').getByText(/Android 不允许/).waitFor();
    assert(await page.locator('#add-rule').isDisabled());
  } else {
    await page.locator('#splash-hits b').getByText('迅雷',{exact:true}).waitFor();
    assert.equal(await page.locator('#splash-hits .app-icon').count(),1);
    await page.locator('#filter-apps').fill('迅雷');
    assert.equal(await page.locator('#splash-hits .rule-group').count(),1);
    await page.locator('#splash > .editor-details > summary').click();
    assert.equal(await page.locator('#user-rules .rule-group').count(),1);
    await page.locator('#user-rules').getByRole('button',{name:'为此应用添加规则'}).click();
    assert.equal(await page.locator('#package').inputValue(),'com.xunlei.downloadprovider');
    await page.locator('#rule-path').fill('cache/new_splash');
    const before = await page.evaluate(()=>window.calls.filter(args=>args[0]==='status').length);
    await page.locator('#add-rule').click();
    assert(await page.locator('#add-rule').isDisabled());
    await page.locator('#user-rules').getByText('cache/new_splash',{exact:true}).waitFor();
    assert.equal(await page.evaluate(()=>window.calls.filter(args=>args[0]==='status').length),before);
    await page.locator('#scan-depth').selectOption('12');
    await page.locator('#discover').click();
    await page.locator('#scan-state').getByText(/扫描完成/).waitFor();
    assert.equal(await page.locator('#candidates .rule-group').count(),2);
    assert.equal(await page.locator('#candidates .app-icon').count(),2);
    assert(await page.evaluate(()=>window.calls.some(args=>args[2]==='discover' && args[4]==='12')));
    await page.locator('#candidate-filter').fill('迅雷');
    assert.equal(await page.locator('#candidates .rule-group').count(),1);
    await page.locator('#candidates .row').filter({hasText:'cache/other_adcache'}).getByRole('button',{name:'加入',exact:true}).click();
    await page.locator('#candidates .row').filter({hasText:'cache/other_adcache'}).waitFor({state:'hidden'});
    await page.screenshot({path:path.join(output,'root-groups-dark.png'),fullPage:true});
  }
  await page.locator('[data-tab=settings]').click();
  await page.locator('#display-theme').selectOption('light');
  assert.equal(await page.locator('body').evaluate(el=>getComputedStyle(el).backgroundColor),'rgb(245, 245, 245)');
  await page.reload(); await page.locator('[data-tab=settings]').click();
  assert.equal(await page.locator('#display-theme').inputValue(),'light');
  await page.locator('#display-theme').selectOption('dark');
  assert.equal(await page.locator('body').evaluate(el=>getComputedStyle(el).backgroundColor),'rgb(0, 0, 0)');
  await page.locator('#display-theme').selectOption('system');
  await page.emulateMedia({colorScheme:'light'});
  await page.waitForFunction(()=>document.documentElement.dataset.theme==='light');
  await page.emulateMedia({colorScheme:'dark'});
  await page.waitForFunction(()=>document.documentElement.dataset.theme==='dark');
  assert.equal(await page.locator('.project-link').getAttribute('href'),'https://github.com/oneorendless/XGuard');
  assert(await page.locator('.support-card').evaluate(card => card.parentElement === document.querySelector('label[for=hide]').parentElement && Boolean(card.compareDocumentPosition(document.querySelector('label[for=hide]')) & Node.DOCUMENT_POSITION_FOLLOWING)));
  await page.locator('#show-donate').click();
  await page.locator('#donate-dialog').getByText('你可以在此捐助以支持(⌒o⌒)',{exact:true}).waitFor();
  assert(await page.locator('#donate-dialog img').evaluate(image=>image.complete && image.naturalWidth>0));
  await page.screenshot({path:path.join(output,vpn?'vpn-donate-dark.png':'root-donate-dark.png')});
  await page.evaluate(()=>window.xguardBack());
  await page.setViewportSize({width:320,height:740}); await page.emulateMedia({colorScheme:'light'});
  await page.locator('[data-tab=home]').click();
  assert(await page.evaluate(()=>document.documentElement.scrollWidth <= innerWidth));
  await page.screenshot({path:path.join(output,vpn?'vpn-home-small.png':'root-home-small.png'),fullPage:true});
  assert.deepEqual(errors,[]); assert.deepEqual(await page.evaluate(()=>window.cspErrors),[]);
  await page.close();
}
await browser.close(); console.log('PASS: Root/VPN statistics, Chinese app groups/icons, incremental save, unsupported controls, donation, small-screen layout, CSP');
