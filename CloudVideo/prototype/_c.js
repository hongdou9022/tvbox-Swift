const { chromium } = require('playwright-core');
const EXE = 'C:/Users/jian.zhang03/AppData/Local/ms-playwright/chromium-1228/chrome-win64/chrome.exe';
(async () => {
  const b = await chromium.launch({ executablePath: EXE });
  const p = await b.newPage({ viewport: { width: 1280, height: 900 }, deviceScaleFactor: 2 });
  const errs = [];
  p.on('pageerror', e => errs.push('PAGEERROR: ' + e.message));
  p.on('console', m => { if (m.type() === 'error') errs.push('CONSOLE: ' + m.text()); });
  await p.goto('file:///' + process.cwd().replace(/\\/g,'/') + '/cloudvideo-preview.html');
  await p.waitForTimeout(500);
  console.log('errors:', errs.length ? errs : 'none');
  await p.screenshot({ path: 'c1-login.png' });
  await p.click('.connect'); await p.waitForTimeout(300);
  await p.click('#s-home .searchbox'); await p.waitForTimeout(400);
  await p.screenshot({ path: 'c2-search.png' });
  await b.close();
})();
