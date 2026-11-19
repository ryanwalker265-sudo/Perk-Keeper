// Offer engine tests: loads mock bank pages in a real browser, runs the engine the way the app
// does (scan, then add one offer at a time, going back when the bank opens a details page) and
// checks what it found and clicked. Run: node Tests/engine/run.mjs [chromium|webkit|all]
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const { chromium, webkit } = require('playwright');

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const engine = fs.readFileSync(path.join(root, 'Resources/offer-engine.js'), 'utf8');
const adapters = JSON.parse(fs.readFileSync(path.join(root, 'Resources/adapters.json'), 'utf8')).adapters;
const fixture = (n) => fs.readFileSync(path.join(root, 'Tests/engine/fixtures', n), 'utf8');
const adapter = (issuer) => adapters.find((a) => a.issuer === issuer);

const ROUTES = {
  'https://global.americanexpress.com/offers/eligible': 'amex-eligible.html',
  'https://global.americanexpress.com/offers/enrolled': 'amex-enrolled.html',
  'https://secure.chase.com/web/auth/dashboard': 'chase-hub.html',
  'https://onlinebanking.usbank.com/deals': 'generic-deals.html',
  'https://login.example-bank.com/': 'login.html',
};

const pad = (n) => String(n).padStart(2, '0');
const isoIn = (days) => { const d = new Date(); d.setHours(0, 0, 0, 0); d.setDate(d.getDate() + days); return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`; };

let failures = 0;
async function test(name, fn) {
  try { await fn(); console.log(`  ok   ${name}`); }
  catch (e) { failures++; console.log(`  FAIL ${name}\n       ${e.message.split('\n').join('\n       ')}`); }
}

async function open(browser, url, issuer) {
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1 });
  await ctx.route('**/*', (route) => {
    const u = new URL(route.request().url());
    const f = ROUTES[u.origin + u.pathname];
    if (f) route.fulfill({ contentType: 'text/html; charset=utf-8', body: fixture(f) });
    else route.fulfill({ status: 404, contentType: 'text/plain', body: '' });
  });
  await ctx.addInitScript({
    content: `window.__msgs=[];window.webkit={messageHandlers:{pk:{postMessage:function(m){window.__msgs.push(m)}}}};window.__PK_CONFIG=${JSON.stringify(adapter(issuer))};`,
  });
  await ctx.addInitScript({ content: engine });
  const page = await ctx.newPage();
  await page.goto(url);
  await page.waitForFunction(() => !!window.__PK, null, { timeout: 5000 });
  return { ctx, page };
}

const scan = async (page, expand = false) =>
  JSON.parse(await page.evaluate((e) => window.__PK.scan({ expand: e, loadMoreDelay: 450, scrollDelay: 250 }), expand));

const waitTiles = (page, n = 1) =>
  page.waitForFunction((min) => window.__PK && window.__PK.state().tiles >= min, n, { timeout: 6000 });

// Mirrors SyncController.addAll() in the app.
async function addAll(page, { afterClick = 'stay', skip = [] } = {}) {
  const tried = [];
  const clicked = [];
  for (let i = 0; i < 60; i++) {
    await waitTiles(page);
    const before = page.url();
    const r = JSON.parse(await page.evaluate((o) => window.__PK.addNext(o), { tried, skip, preClickMs: 30 }));
    if (!r.clicked) break;
    tried.push(r.key);
    clicked.push(r.merchant);
    await page.waitForTimeout(450);
    const err = await page.evaluate(() => window.__PK.errorText());
    if (err) throw new Error(`error banner: ${err}`);
    if (afterClick === 'back' && page.url() !== before) {
      await page.evaluate(() => window.__PK.goBack());
      await page.waitForTimeout(500);
    }
  }
  return clicked;
}

async function run(browserType) {
  console.log(`\n${browserType.name()}`);
  const browser = await browserType.launch();

  await test('parses expiration dates', async () => {
    const { ctx, page } = await open(browser, 'https://login.example-bank.com/', 'other');
    const r = await page.evaluate(() => {
      const now = new Date(2026, 10, 19);
      const p = (s) => window.__PK.parseExpiry(s, now);
      return [p('Expires 12/31/2026'), p('Exp 2/1/27'), p('Expires Dec 20, 2026'), p('12 days left'), p('Expires in 3 days'),
        p('Valid through 01/10/2027'), p('Ends 1/5'), p('Expires December 3'), p('Expires today'), p('Offer ends Jan 2'), p('Expiring soon')];
    });
    assert.deepEqual(r, ['2026-12-31', '2027-02-01', '2026-12-20', '2026-12-01', '2026-11-22', '2027-01-10', '2027-01-05', '2026-12-03', '2026-11-19', '2027-01-02', null]);
    await ctx.close();
  });

  await test('parses reward text', async () => {
    const { ctx, page } = await open(browser, 'https://login.example-bank.com/', 'other');
    const r = await page.evaluate(() => [
      'Spend $250 or more, earn $50 back. Up to 2 times (total of $100).',
      'Earn 10% back on purchases, up to a total of $40',
      'Get $5 back on a single purchase of $25+',
      'Earn +2 Membership Rewards® points per dollar, up to 1,000 pts',
      '$3 cash back on $15+',
      'Spend $10.99 or more, earn $10.99 back',
    ].map((s) => window.__PK.parseReward(s)));
    assert.deepEqual(r.map((x) => x.value), [100, 40, 5, null, 3, 10.99]);
    assert.deepEqual(r.map((x) => x.minSpend), [250, null, 25, null, 15, 10.99]);
    assert.equal(r[1].percent, 10);
    assert.equal(r[3].points, 1000);
    await ctx.close();
  });

  await test('Amex: finds every available offer after Load more', async () => {
    const { ctx, page } = await open(browser, 'https://global.americanexpress.com/offers/eligible', 'amex');
    await waitTiles(page, 4);
    const s = await scan(page, true);
    const names = s.tiles.map((t) => t.merchant);
    assert.deepEqual(names, ['Hilton', 'Dell Technologies', 'Uber Eats', 'Lowe’s', 'Starbucks', 'Disney+', 'Walgreens', 'FedEx', 'Instacart']);
    assert.ok(s.tiles.every((t) => t.status === 'available'), JSON.stringify(s.tiles.map((t) => t.status)));
    const hilton = s.tiles[0];
    assert.equal(hilton.expires, '2026-12-31');
    assert.equal(hilton.value, 100);
    assert.equal(hilton.minSpend, 250);
    assert.match(hilton.reward, /Spend \$250 or more, earn \$50 back/);
    assert.equal(s.tiles[2].expires, isoIn(3));
    assert.ok(s.hints.includes('41009'), `hints ${s.hints}`);
    const msgs = await page.evaluate(() => window.__msgs);
    assert.ok(msgs.some((m) => m.type === 'state' && m.tiles >= 4), 'posted a state message');
    await ctx.close();
  });

  await test('Amex: adds all offers, never touches other buttons, honors skip words', async () => {
    const { ctx, page } = await open(browser, 'https://global.americanexpress.com/offers/eligible', 'amex');
    await waitTiles(page, 4);
    await scan(page, true);
    const clicked = await addAll(page, { skip: ['uber'] });
    assert.equal(clicked.length, 8, `clicked ${clicked}`);
    assert.ok(!clicked.includes('Uber Eats'));
    assert.equal(await page.evaluate(() => window.__forbidden), 0);
    await page.waitForTimeout(300);
    const s = await scan(page);
    const status = Object.fromEntries(s.tiles.map((t) => [t.merchant, t.status]));
    assert.equal(status['Uber Eats'], 'available');
    assert.equal(Object.values(status).filter((x) => x === 'added').length, 8, JSON.stringify(status));
    await ctx.close();
  });

  await test('Amex: added-to-card page reads added and redeemed offers', async () => {
    const { ctx, page } = await open(browser, 'https://global.americanexpress.com/offers/enrolled', 'amex');
    await waitTiles(page, 3);
    const s = await scan(page);
    const status = Object.fromEntries(s.tiles.map((t) => [t.merchant, t.status]));
    assert.deepEqual(status, { Hilton: 'added', 'Best Buy': 'used', Hulu: 'added' });
    await ctx.close();
  });

  await test('Chase: adds through the details page and comes back', async () => {
    const { ctx, page } = await open(browser, 'https://secure.chase.com/web/auth/dashboard', 'chase');
    await waitTiles(page, 5);
    let s = await scan(page);
    assert.equal(s.tiles.length, 5, JSON.stringify(s.tiles.map((t) => t.merchant)));
    assert.deepEqual(s.tiles.filter((t) => t.status === 'added').map((t) => t.merchant).sort(), ['Lyft', 'Peloton']);
    assert.equal(s.tiles.find((t) => t.merchant === 'Starbucks').expires, isoIn(12));
    const clicked = await addAll(page, { afterClick: 'back' });
    assert.deepEqual(clicked.sort(), ['Home Depot', 'Starbucks', 'Wayfair']);
    assert.equal(await page.evaluate(() => window.__forbidden), 0);
    await waitTiles(page, 5);
    s = await scan(page);
    assert.ok(s.tiles.every((t) => t.status === 'added'), JSON.stringify(s.tiles.map((t) => [t.merchant, t.status])));
    assert.match(page.url(), /offer-hub/);
    await ctx.close();
  });

  await test('Generic bank: Activate buttons, ignores promos and payment buttons', async () => {
    const { ctx, page } = await open(browser, 'https://onlinebanking.usbank.com/deals', 'usBank');
    await waitTiles(page, 3);
    const s = await scan(page);
    const status = Object.fromEntries(s.tiles.map((t) => [t.merchant, t.status]));
    assert.deepEqual(status, { Shell: 'available', Chipotle: 'available', Spotify: 'added' });
    assert.equal(s.tiles.find((t) => t.merchant === 'Shell').expires, isoIn(5));
    const clicked = await addAll(page);
    assert.deepEqual(clicked, ['Shell', 'Chipotle']);
    assert.equal(await page.evaluate(() => window.__forbidden), 0);
    assert.ok(s.hints.includes('7731'));
    await ctx.close();
  });

  await test('Login page: reports login, finds no offers', async () => {
    const { ctx, page } = await open(browser, 'https://login.example-bank.com/', 'other');
    await page.waitForTimeout(400);
    const st = await page.evaluate(() => window.__PK.state());
    assert.equal(st.login, true);
    assert.equal(st.tiles, 0);
    await ctx.close();
  });

  await test('Diagnostics outline hides account numbers', async () => {
    const { ctx, page } = await open(browser, 'https://global.americanexpress.com/offers/eligible', 'amex');
    await waitTiles(page, 4);
    const o = await page.evaluate(() => window.__PK.outline());
    assert.ok(!o.includes('41009'), 'account digits leaked');
    const j = JSON.parse(o);
    assert.equal(j.counts.tiles, 4);
    await ctx.close();
  });

  await browser.close();
}

const which = process.argv[2] || 'chromium';
const types = which === 'all' ? [chromium, webkit] : which === 'webkit' ? [webkit] : [chromium];
for (const t of types) await run(t);
console.log(failures ? `\n${failures} failing` : '\nall engine tests passed');
process.exit(failures ? 1 : 0);
