import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
const require=createRequire(path.resolve(process.env.XGUARD_TEST_TOOLS || '../.xiezhi-tools','package.json'));
const {chromium}=require('playwright');
const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'});
fs.mkdirSync('dist/device-check',{recursive:true});
try {
for(const vpn of [false,true]) {
  const page=await browser.newPage({viewport:{width:390,height:844},colorScheme:'dark'});
  const errors=[]; page.on('pageerror',e=>errors.push(e.message));
  await page.addInitScript(vpn=>{
    localStorage.setItem('xguard.rootConfirmed.v1','1');
    let until=0,undo=true,backup=1700000000; window.calls=[];
    window.XGuard={getMode:()=>vpn?'vpn':'root',isVpnPrepared:()=>true,haptic(){},execute(raw,callback){
      const a=JSON.parse(raw); window.calls.push(a); let result={}; const op=a[3];
      if(a[0]==='status') result={version:'0.8.7',root:'test',daemon:'running',features:[{enabled:true,health:'ok',pause_until:until,summary:'test'}]};
      if(a[2]==='stats') result={hosts_rules:100,mode:'hosts',sources:1,hosts_max:200000};
      if(a[2]==='activity') result={collector:{running:true,enabled:true},snapshot:{items:[],observed:0,matched:0}};
      if(a[2]==='sources') result={list:[],interval_h:24};
      if(a[2]==='allow') result={allow:[]}; if(a[2]==='block') result={block:[]};
      if(a[2]==='recovery') {
        if(op==='pause') until=Math.floor(Date.now()/1000)+300;
        if(op==='resume') until=0;
        if(op==='undo') undo=false;
        result={pause_until:until,undo_available:undo,backup_time:backup,update_time:1700000200,update_added:10,update_removed:3,health:{}};
        if(op==='check'||op==='repair') result={state:op==='repair'?'ok':'collector_stopped',checked_at:1700000300,hosts_mounted:true,daemon_running:true,collector_running:op==='repair',collector_enabled:true,vpn_authorized:true};
      }
      const failed=window.failRollback&&a[2]==='recovery'&&op==='rollback';
      setTimeout(()=>window[callback](failed?1:0,failed?'来源选择已改变':JSON.stringify(result),''),a[2]==='recovery'&&op==='status'?80:10);
    }};
  },vpn);
  await page.goto(pathToFileURL(path.resolve(vpn?'no-root/app/assets/index.html':'module/webroot/index.html')).href);
  await page.locator('#pause-protection').getByText('暂停 5 分钟',{exact:true}).waitFor();
  await page.locator('#pause-protection').click(); await page.locator('#confirm-no').click();
  assert(!(await page.evaluate(()=>window.calls.some(a=>a[3]==='pause'))));
  await page.locator('#pause-protection').click(); await page.locator('#confirm-yes').click();
  await page.locator('#connection').getByText('XGuard 防护临时暂停',{exact:true}).waitFor();
  assert.match(await page.locator('#pause-countdown').textContent(),/后恢复/);
  await page.screenshot({path:`dist/device-check/087-${vpn?'vpn':'root'}-pause.png`,fullPage:true});
  await page.locator('#pause-protection').click();
  await page.locator('#connection').getByText('XGuard 防护已开启',{exact:true}).waitFor();
  await page.locator('#undo-domain').click(); await page.locator('#confirm-yes').click();
  await page.waitForFunction(()=>!document.querySelector('.app-shell').matches('[aria-busy=true]'));
  assert(await page.locator('#undo-domain').isDisabled());
  await page.locator('.bottom-nav [data-tab=activity]').click();
  await page.locator('#activity [data-page=sources]').click();
  assert.match(await page.locator('#rule-diff').textContent(),/新增 10.*移除 3/);
  await page.evaluate(()=>window.failRollback=true);
  await page.locator('#rollback-rules').click(); await page.locator('#confirm-yes').click();
  await page.locator('#toast').getByText('来源选择已改变',{exact:true}).waitFor();
  await page.evaluate(()=>window.failRollback=false);
  await page.locator('#rollback-rules').click(); await page.locator('#confirm-yes').click();
  await page.locator('#toast').getByText('已恢复更新前规则',{exact:true}).waitFor();
  await page.locator('[data-tab=settings]').click();
  await page.locator('#health-check').click(); await page.locator('#health-result').getByText('采集器未运行',{exact:true}).waitFor();
  await page.locator('#health-dialog [aria-label="关闭运行检查"]').click();
  assert(!(await page.locator('#health-dialog').evaluate(d=>d.open)));
  await page.waitForFunction(()=>!document.querySelector('.app-shell').matches('[aria-busy=true]'));
  await page.locator('#health-repair').click(); await page.locator('#health-result').getByText('运行正常',{exact:true}).waitFor();
  await page.screenshot({path:`dist/device-check/087-${vpn?'vpn':'root'}-health.png`});
  await page.keyboard.press('Escape');
  await page.setViewportSize({width:320,height:740}); await page.emulateMedia({colorScheme:'light'});
  await page.locator('[data-tab=home]').click();
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  assert.deepEqual(errors,[]); await page.close();
}
console.log('PASS: Root/VPN pause confirmation and resume, undo refresh, rollback failure/success, dismissible health check/repair, narrow layout');
} finally { await browser.close(); }
