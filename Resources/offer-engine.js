/*
 * Perk Keeper offer engine.
 *
 * Runs inside Perk Keeper's in-app browser, in its own isolated script world, on your bank's
 * offers pages. It reads the offer tiles on the page (merchant, reward, expiration and whether
 * each offer is available, added or used) and, only when the app asks, clicks ONE "add" control
 * at a time. It never reads, fills or submits form fields, and never sends anything off the
 * device: results go straight to the app through the "pk" message handler.
 *
 * The app sets window.__PK_CONFIG (one issuer's entry from adapters.json) before this file runs.
 */
(function () {
  'use strict';

  var VERSION = 4;
  if (window.__PK && window.__PK.version >= VERSION) return;

  // ---------------------------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------------------------

  var DEFAULT_ADD = [
    '^\\+$', '^add$', '^add to card$', '^add to my card$', '^add offer$', '^add deal$',
    '^activate$', '^activate (deal|offer)$', '^enroll$', '^enroll (now|in offer)$', '^save (offer|deal)$',
    '^add .{1,60} (offer )?to (your |my )?card$', '^add (offer|deal) (for|from|at) .{1,60}$',
    '^activate (offer|deal) (for|from|at) .{1,60}$', '^add .{1,40} (offer|deal)$', '^enroll in .{1,60} offer$'
  ];
  var DEFAULT_ADDED = [
    '^added$', '^added to (your |my )?card$', '^activated$', '^enrolled$', '^saved$', '^offer added$',
    '^deal (added|activated)$', '^you.?re enrolled$', '^✓$', '^added .{1,60} to (your |my )?card$',
    '^.{1,40} offer added$', '^remove( offer)?$', '^offer activated$'
  ];
  var DEFAULT_USED = [
    '^redeemed$', '^offer redeemed$', '^redeemed (on|\\d).{0,20}$', '^completed$', '^used$', '^offer used$',
    '^(credit|reward|cash ?back|statement credit) (earned|issued|posted)$', '^you.?(ve| have) earned.{0,30}$',
    '^earned$', '^\\$[\\d,.]+ (credit |cash back )?earned$'
  ];
  var DEFAULT_LOAD_MORE = [
    '^(load|show|see|view) more( offers| deals)?$', '^more (offers|deals)$', '^(see|view|show) all (offers|deals)$'
  ];
  var DEFAULT_ERRORS = ['unable to add', 'try again later', 'something went wrong'];

  // Never click anything whose label looks like this, whatever a selector says.
  var DENY = /(\bpay\b|payment|transfer|zelle|send money|sign ?out|log ?out|delete|\bremove\b|close account|\bcancel\b|dispute|redeem points|apply now|apply for|submit|add (an? )?(new )?account|add (an? )?(new )?card$|add payee|external account|lock card|replace card|report)/i;

  var REWARDISH = /(\bback\b|cash ?back|\bearn|\bget (a |an )?\$|\bsave\b|\d\s?%|\bpoints?\b|\bmiles\b|statement credit|\$[\d,.]+ credit|\boff\b)/i;
  var EXP_HINT = /\b(expires?|expiring|exp\.?|ends?|valid (through|thru|until)|use by|good (through|thru)|days? (left|remaining)|last day)\b/i;
  var BOILER = /^(terms apply|terms|terms & conditions|view details|details|see details|offer details|learn more|new|new offer|expiring soon|shop now|more|info|recommended|featured|limited time|online|in-store|in store|online (&|and) in-store|for you|\+|✓|added|add|activate|enroll|view offer|see offer|tap to add|popular)$/i;

  function rxList(list) {
    var out = [];
    (list || []).forEach(function (p) {
      try { out.push(new RegExp(p, 'i')); } catch (e) { /* skip bad pattern */ }
    });
    return out;
  }

  function buildAdapter(raw) {
    raw = raw || {};
    var a = {
      issuer: raw.issuer || 'other',
      name: raw.name || 'Bank',
      demo: !!raw.demo,
      domains: raw.domains || [],
      addSelectors: raw.addSelectors || [],
      iconAddSelectors: raw.iconAddSelectors || [],
      addedSelectors: raw.addedSelectors || [],
      usedSelectors: raw.usedSelectors || [],
      tileSelectors: raw.tileSelectors || [],
      merchantSelectors: raw.merchantSelectors || ['h2', 'h3', 'h4', '[class*="merchant" i]', '[data-testid*="merchant" i]'],
      loadMoreSelectors: raw.loadMoreSelectors || [],
      backSelectors: raw.backSelectors || [],
      iconAdd: raw.iconAdd || 'labeled',
      afterClick: raw.afterClick || 'stay',
      clickUnknownTiles: !!raw.clickUnknownTiles,
      cardHint: raw.cardHint !== false,
      pageStatus: raw.pageStatus || []
    };
    a.addRx = rxList((raw.addTexts || []).concat(DEFAULT_ADD));
    a.addedRx = rxList((raw.addedTexts || []).concat(DEFAULT_ADDED));
    a.usedRx = rxList((raw.usedTexts || []).concat(DEFAULT_USED));
    a.loadMoreRx = rxList((raw.loadMoreTexts || []).concat(DEFAULT_LOAD_MORE));
    a.errorRx = rxList((raw.errorPatterns || []).concat(DEFAULT_ERRORS));
    return a;
  }

  var A = buildAdapter(window.__PK_CONFIG);

  // ---------------------------------------------------------------------------------------------
  // Small helpers
  // ---------------------------------------------------------------------------------------------

  function norm(s) { return String(s == null ? '' : s).replace(/[\s ]+/g, ' ').trim(); }
  function low(s) { return norm(s).toLowerCase(); }
  function sleep(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }
  function anyMatch(list, s) { for (var i = 0; i < list.length; i++) if (list[i].test(s)) return true; return false; }

  function post(msg) {
    try { window.webkit.messageHandlers.pk.postMessage(msg); } catch (e) { /* not in the app */ }
  }

  function parentOf(el) {
    if (!el) return null;
    if (el.parentElement) return el.parentElement;
    var p = el.parentNode;
    if (p && p.host) return p.host; // leave a shadow root
    return null;
  }

  function contains(outer, inner) {
    var n = inner;
    while (n) { if (n === outer) return true; n = parentOf(n); }
    return false;
  }

  function visible(el) {
    if (!el || !el.getBoundingClientRect) return false;
    var r = el.getBoundingClientRect();
    if (r.width < 1 || r.height < 1) return false;
    var s = window.getComputedStyle(el);
    if (s.visibility === 'hidden' || s.display === 'none') return false;
    if (parseFloat(s.opacity || '1') < 0.05) return false;
    return true;
  }

  function onAdapterDomain() {
    if (A.demo || !A.domains.length) return true;
    var h = location.hostname || '';
    return A.domains.some(function (d) { return h === d || h.slice(-(d.length + 1)) === '.' + d; });
  }

  // Every element, including the inside of open shadow roots (custom elements on some bank sites).
  function allElements() {
    var out = [];
    var stack = document.documentElement ? [document.documentElement] : [];
    while (stack.length && out.length < 30000) {
      var n = stack.pop();
      out.push(n);
      // Push children in reverse so the first child is visited next (document order).
      var kids = n.children || [];
      for (var i = kids.length - 1; i >= 0; i--) stack.push(kids[i]);
      if (n.shadowRoot) {
        var sk = n.shadowRoot.children || [];
        for (var j = sk.length - 1; j >= 0; j--) stack.push(sk[j]);
      }
    }
    return out;
  }

  var SKIP_TAGS = { SCRIPT: 1, STYLE: 1, NOSCRIPT: 1, TEMPLATE: 1, HEAD: 1, META: 1, LINK: 1, TITLE: 1 };

  function makeContext() {
    var els = allElements().filter(function (e) { return !SKIP_TAGS[e.tagName]; });
    return { els: els };
  }

  function queryAll(ctx, sel) {
    if (!sel) return [];
    if (sel.indexOf('>>>') >= 0) {
      var parts = sel.split('>>>');
      var hosts = queryAll(ctx, parts[0].trim());
      var out = [];
      hosts.forEach(function (h) {
        if (h.shadowRoot) {
          try { out = out.concat(Array.prototype.slice.call(h.shadowRoot.querySelectorAll(parts[1].trim()))); } catch (e) { }
        }
      });
      return out;
    }
    var res = [];
    try {
      for (var i = 0; i < ctx.els.length; i++) if (ctx.els[i].matches(sel)) res.push(ctx.els[i]);
    } catch (e) { return []; }
    return res;
  }

  function queryAllList(ctx, list) {
    var seen = new Set();
    var out = [];
    (list || []).forEach(function (sel) {
      queryAll(ctx, sel).forEach(function (el) { if (!seen.has(el)) { seen.add(el); out.push(el); } });
    });
    return out;
  }

  function labelOf(el) {
    if (!el || !el.getAttribute) return '';
    var l = el.getAttribute('aria-label') || el.getAttribute('title');
    if (!l) {
      var by = el.getAttribute('aria-labelledby');
      if (by) {
        l = by.split(/\s+/).map(function (id) { var t = document.getElementById(id); return t ? t.textContent : ''; }).join(' ');
      }
    }
    if (!l) l = el.innerText || el.textContent || '';
    if (!l && el.value && el.tagName === 'INPUT' && /button|submit/i.test(el.type || '')) l = el.value;
    if (!l) {
      var t = el.querySelector && el.querySelector('svg title');
      if (t) l = t.textContent;
    }
    return low(l).slice(0, 160);
  }

  var CLICKABLE = 'button, a[href], a[role="button"], [role="button"], input[type="button"], input[type="submit"], [data-cy*="button"]';

  function isClickable(el) {
    try { return el.matches(CLICKABLE); } catch (e) { return false; }
  }

  function closestClickable(el, within) {
    var n = el;
    while (n && n !== within) {
      if (n.nodeType === 1 && isClickable(n)) return n;
      n = parentOf(n);
    }
    if (within && within.nodeType === 1 && isClickable(within)) return within;
    return null;
  }

  function denied(label) {
    var l = (label || '').replace(/terms apply/g, '');
    return DENY.test(l);
  }

  // ---------------------------------------------------------------------------------------------
  // Parsing: expiration dates and reward text
  // ---------------------------------------------------------------------------------------------

  var MONTHS = { jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6, jul: 7, aug: 8, sep: 9, sept: 9, oct: 10, nov: 11, dec: 12 };

  function pad(n) { return (n < 10 ? '0' : '') + n; }
  function isoOf(d) { return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()); }
  function addDays(now, n) { var d = new Date(now.getFullYear(), now.getMonth(), now.getDate()); d.setDate(d.getDate() + n); return d; }
  function validYMD(y, m, d) {
    if (m < 1 || m > 12 || d < 1 || d > 31 || y < 2000 || y > 2100) return null;
    var dt = new Date(y, m - 1, d);
    if (dt.getMonth() !== m - 1) return null;
    return dt;
  }
  function nextOccurrence(now, m, d) {
    var y = now.getFullYear();
    var dt = validYMD(y, m, d);
    if (!dt) return null;
    if (dt < addDays(now, -1)) dt = validYMD(y + 1, m, d);
    return dt;
  }

  // Returns "YYYY-MM-DD" or null.
  function parseExpiry(text, now) {
    now = now || new Date();
    var t = low(text);
    var m;
    if (/\b(expires?|ends?) today\b|\blast day\b|\bends tonight\b/.test(t)) return isoOf(addDays(now, 0));
    if (/\b(expires?|ends?) tomorrow\b/.test(t)) return isoOf(addDays(now, 1));
    if ((m = t.match(/\b(\d{1,3})\s*(?:more\s+)?days?\s*(?:left|remaining)\b/)) ||
        (m = t.match(/\b(?:expires?|ends?|expiring)\s+in\s+(\d{1,3})\s*days?\b/))) {
      return isoOf(addDays(now, parseInt(m[1], 10)));
    }
    if ((m = t.match(/\b(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2,4})\b/))) {
      var y = parseInt(m[3], 10); if (y < 100) y += 2000;
      var d1 = validYMD(y, parseInt(m[1], 10), parseInt(m[2], 10));
      return d1 ? isoOf(d1) : null;
    }
    if ((m = t.match(/\b(\d{4})-(\d{2})-(\d{2})\b/))) {
      var d2 = validYMD(parseInt(m[1], 10), parseInt(m[2], 10), parseInt(m[3], 10));
      return d2 ? isoOf(d2) : null;
    }
    if ((m = t.match(/\b(jan|feb|mar|apr|may|jun|jul|aug|sept|sep|oct|nov|dec)[a-z]*\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?\b/))) {
      var mo = MONTHS[m[1]], day = parseInt(m[2], 10);
      var d3 = m[3] ? validYMD(parseInt(m[3], 10), mo, day) : nextOccurrence(now, mo, day);
      return d3 ? isoOf(d3) : null;
    }
    if ((m = t.match(/\b(?:expires?|exp\.?|ends?|through|thru|until|by)\s+(?:on\s+)?(\d{1,2})\/(\d{1,2})\b/))) {
      var d4 = nextOccurrence(now, parseInt(m[1], 10), parseInt(m[2], 10));
      return d4 ? isoOf(d4) : null;
    }
    return null;
  }

  function money(s) { return parseFloat(String(s).replace(/,/g, '')); }

  function parseReward(text) {
    var t = norm(text);
    var out = { value: null, minSpend: null, percent: null, points: null };
    var m;
    if ((m = t.match(/(\d+(?:\.\d+)?)\s?%/))) out.percent = parseFloat(m[1]);
    if ((m = t.match(/up to (?:a total of |a max(?:imum)? of |a combined )?\$\s?([\d,]+(?:\.\d{1,2})?)/i)) ||
        (m = t.match(/\btotal of \$\s?([\d,]+(?:\.\d{1,2})?)/i))) out.value = money(m[1]);
    if (out.value == null && (m = t.match(/(?:earn|get|receive|enjoy)\s+(?:a\s+)?(?:one[- ]time\s+)?\$\s?([\d,]+(?:\.\d{1,2})?)/i))) out.value = money(m[1]);
    if (out.value == null && (m = t.match(/\$\s?([\d,]+(?:\.\d{1,2})?)\s+(?:back|cash ?back|statement credit|credit|off|reward)/i))) out.value = money(m[1]);
    if ((m = t.match(/spend\s+(?:at least\s+)?\$\s?([\d,]+(?:\.\d{1,2})?)/i)) ||
        (m = t.match(/(?:purchase|order|transaction)s?\s+of\s+(?:at least\s+)?\$\s?([\d,]+(?:\.\d{1,2})?)/i)) ||
        (m = t.match(/\$\s?([\d,]+(?:\.\d{1,2})?)\s?\+/))) out.minSpend = money(m[1]);
    if ((m = t.match(/([\d,]{2,})\s+(?:(?:membership rewards(?:®)?|bonus|thankyou|ultimate rewards)\s+)?(?:points|pts|miles)\b/i))) out.points = money(m[1]);
    return out;
  }

  // ---------------------------------------------------------------------------------------------
  // Finding offers
  // ---------------------------------------------------------------------------------------------

  function directText(el) {
    var s = '';
    for (var n = el.firstChild; n; n = n.nextSibling) if (n.nodeType === 3) s += n.nodeValue;
    return s;
  }

  // Keep only the deepest element of each nested chain (a <span> and the <button> around it both
  // reading "Added to Card" are one marker, not two).
  function deepest(list) {
    return list.filter(function (el) {
      for (var i = 0; i < list.length; i++) if (list[i] !== el && contains(el, list[i])) return false;
      return true;
    });
  }

  function outermost(list) {
    return list.filter(function (el) {
      for (var i = 0; i < list.length; i++) if (list[i] !== el && contains(list[i], el)) return false;
      return true;
    });
  }

  function findAddControls(ctx) {
    var set = new Set();
    queryAllList(ctx, A.addSelectors).forEach(function (el) { if (visible(el) && !denied(labelOf(el))) set.add(el); });
    queryAllList(ctx, A.iconAddSelectors).forEach(function (el) { if (visible(el)) set.add(el); });
    ctx.els.forEach(function (el) {
      if (!isClickable(el) || set.has(el)) return;
      var l = labelOf(el);
      if (!l || l.length > 90) return;
      if (anyMatch(A.addRx, l) && !anyMatch(A.addedRx, l) && !denied(l) && visible(el)) set.add(el);
    });
    return outermost(Array.from(set));
  }

  function findMarkers(ctx) {
    var added = [], used = [], exp = [];
    var addedSel = new Set(queryAllList(ctx, A.addedSelectors));
    var usedSel = new Set(queryAllList(ctx, A.usedSelectors));
    ctx.els.forEach(function (el) {
      if (addedSel.has(el)) { if (visible(el)) added.push(el); return; }
      if (usedSel.has(el)) { if (visible(el)) used.push(el); return; }
      var aria = el.getAttribute && el.getAttribute('aria-label');
      var tc = el.textContent;
      var text = '';
      if (tc && tc.length <= 120 && el.childElementCount <= 4) text = low(tc);
      else if (directText(el).trim()) text = low(directText(el));
      var candidates = [];
      if (text) candidates.push(text);
      if (aria && aria.length <= 120) candidates.push(low(aria));
      if (!candidates.length) return;
      var isAdded = false, isUsed = false, isExp = false;
      candidates.forEach(function (c) {
        if (c.length <= 70 && anyMatch(A.addedRx, c) && !anyMatch(A.addRx, c)) isAdded = true;
        if (c.length <= 70 && anyMatch(A.usedRx, c)) isUsed = true;
        if (c.length <= 110 && EXP_HINT.test(c) && parseExpiry(c)) isExp = true;
      });
      if ((isAdded || isUsed || isExp) && !visible(el)) return;
      if (isUsed) used.push(el); else if (isAdded) added.push(el);
      if (isExp) exp.push(el);
    });
    return { added: deepest(added), used: deepest(used), exp: deepest(exp) };
  }

  // Count, for every ancestor, how many markers of each kind it holds.
  function buildCounts(groups) {
    var counts = new Map();
    Object.keys(groups).forEach(function (kind) {
      groups[kind].forEach(function (m) {
        var p = parentOf(m), d = 0;
        while (p && d < 30) {
          var c = counts.get(p);
          if (!c) { c = { add: 0, added: 0, used: 0, exp: 0 }; counts.set(p, c); }
          c[kind]++;
          p = parentOf(p); d++;
        }
      });
    });
    return counts;
  }

  var STOP_TAGS = { BODY: 1, HTML: 1, MAIN: 1 };

  // Walk up from a marker to the biggest element that still holds just one offer.
  function climb(start, counts) {
    var best = start, node = start;
    for (var i = 0; i < 14; i++) {
      var p = parentOf(node);
      if (!p || STOP_TAGS[p.tagName]) break;
      var c = counts.get(p) || { add: 0, added: 0, used: 0, exp: 0 };
      if (c.add > 1 || c.added > 1 || c.used > 1 || c.exp > 1) break;
      var len = (p.textContent || '').length;
      if (len > 1400) break;
      best = p; node = p;
    }
    return best;
  }

  function closestMatching(el, selectors) {
    if (!selectors.length) return null;
    var n = el;
    while (n) {
      if (n.nodeType === 1) {
        for (var i = 0; i < selectors.length; i++) {
          try { if (n.matches(selectors[i])) return n; } catch (e) { }
        }
      }
      n = parentOf(n);
    }
    return null;
  }

  function pageStatus() {
    var path = (location.pathname || '') + (location.hash || '');
    for (var i = 0; i < A.pageStatus.length; i++) {
      if (path.indexOf(A.pageStatus[i].match) >= 0) return A.pageStatus[i].status;
    }
    return null;
  }

  function isIconOnly(el) {
    var t = norm(el.innerText || el.textContent || '');
    if (t && t !== '+') return false;
    return !!(el.querySelector && el.querySelector('svg, img, i, [class*="icon" i], mds-icon, [type^="ico" i]')) || t === '+';
  }

  function slug(s) { return low(s).replace(/[^a-z0-9]+/g, ''); }

  function cleanMerchant(s) {
    return norm(s).replace(/^(logo (of|for)\s+)/i, '').replace(/\s*(logo|image|offer)$/i, '').replace(/[®™]/g, '').trim();
  }

  function merchantOf(tile, lines, reward, expLine) {
    var i, c;
    var picks = queryAllList({ els: [tile].concat(Array.prototype.slice.call(tile.querySelectorAll('*'))) }, A.merchantSelectors);
    for (i = 0; i < picks.length; i++) {
      c = cleanMerchant(picks[i].innerText || picks[i].textContent);
      if (c && c.length <= 60 && !REWARDISH.test(c) && !EXP_HINT.test(c) && !BOILER.test(c)) return c;
    }
    var imgs = tile.querySelectorAll('img[alt]');
    for (i = 0; i < imgs.length; i++) {
      c = cleanMerchant(imgs[i].getAttribute('alt'));
      if (c && c.length >= 2 && c.length <= 60 && !/^(logo|image|offer|merchant)$/i.test(c)) return c;
    }
    for (i = 0; i < lines.length; i++) {
      var l = lines[i];
      if (l === reward || l === expLine) continue;
      if (l.length < 2 || l.length > 60) continue;
      if (REWARDISH.test(l) || EXP_HINT.test(l) || BOILER.test(l)) continue;
      if (/^[\d\s.,$%\/-]+$/.test(l)) continue;
      return cleanMerchant(l);
    }
    var aria = tile.getAttribute && tile.getAttribute('aria-label');
    if (aria) {
      var m = aria.match(/^(.{2,60}?)(?:[,.:]|\s+-\s+|\s+\d)/);
      if (m && !REWARDISH.test(m[1])) return cleanMerchant(m[1]);
    }
    return '';
  }

  function describe(tile) {
    var raw = tile.innerText || tile.textContent || '';
    var seen = {};
    var lines = raw.split(/\n+/).map(norm).filter(function (l) {
      if (!l || seen[l]) return false;
      seen[l] = 1;
      var ll = l.toLowerCase();
      if (BOILER.test(l)) return false;
      if (ll.length <= 70 && (anyMatch(A.addRx, ll) || anyMatch(A.addedRx, ll))) return false;
      return true;
    });
    if (lines.length < 2 && raw.indexOf('\n') < 0) {
      // innerText can be one line when the tile is off-screen; fall back to child text blocks.
      var blocks = [];
      tile.querySelectorAll('*').forEach(function (e) {
        var d = norm(directText(e));
        if (d && !seen[d] && !BOILER.test(d)) { seen[d] = 1; blocks.push(d); }
      });
      if (blocks.length) lines = blocks;
    }
    var expLine = null, expires = null;
    for (var i = 0; i < lines.length; i++) {
      if (EXP_HINT.test(lines[i])) { var e = parseExpiry(lines[i]); if (e) { expLine = lines[i]; expires = e; break; } }
    }
    var reward = '';
    for (i = 0; i < lines.length; i++) {
      if (lines[i] === expLine) continue;
      if (REWARDISH.test(lines[i]) && !(lines[i].length <= 70 && anyMatch(A.usedRx, lines[i].toLowerCase()))) {
        reward = lines[i];
        // "Spend $50 or more," + "earn $10 back" split over two lines
        if (reward.length < 28 && lines[i + 1] && lines[i + 1] !== expLine && REWARDISH.test(lines[i + 1]) && /[,\-]$|\bspend\b/i.test(reward)) {
          reward = reward + ' ' + lines[i + 1];
        }
        break;
      }
    }
    var merchant = merchantOf(tile, lines, reward, expLine);
    var details = lines.filter(function (l) {
      return l !== reward && l !== merchant && l !== expLine && reward.indexOf(l) < 0;
    }).slice(0, 4).join(' · ').slice(0, 300);
    var parsed = parseReward(reward + ' ' + details);
    var key = merchant ? slug(merchant) + '|' + slug(reward).slice(0, 80) : slug(reward).slice(0, 80) + '|' + (expires || '');
    return {
      key: key, merchant: merchant || (reward ? reward.slice(0, 40) : 'Offer'), reward: reward.slice(0, 200),
      details: details, expires: expires, value: parsed.value, minSpend: parsed.minSpend,
      percent: parsed.percent, points: parsed.points
    };
  }

  // The heart of it: every offer tile on the page with its status and the control that adds it.
  function collect() {
    var ctx = makeContext();
    var addCtls = findAddControls(ctx);
    var marks = findMarkers(ctx);
    var groups = { add: addCtls, added: marks.added, used: marks.used, exp: marks.exp };
    var counts = buildCounts(groups);

    var tileSet = new Set();
    var anchors = addCtls.concat(marks.added, marks.used, marks.exp);
    anchors.forEach(function (a) {
      var t = null;
      var sel = closestMatching(a, A.tileSelectors);
      if (sel) {
        var c = counts.get(sel) || { add: 0, added: 0, used: 0, exp: 0 };
        if (c.add <= 1 && c.added <= 1 && c.used <= 1 && c.exp <= 1) t = sel;
      }
      if (!t) t = climb(a, counts);
      if (t) tileSet.add(t);
    });
    // Tiles found by selector alone (status unknown until we look inside).
    if (A.tileSelectors.length) {
      queryAllList(ctx, A.tileSelectors).forEach(function (t) {
        var c = counts.get(t) || { add: 0, added: 0, used: 0, exp: 0 };
        if (c.add <= 1 && c.added <= 1 && c.used <= 1 && c.exp <= 1 && visible(t)) tileSet.add(t);
      });
    }
    var defaultStatus = pageStatus();
    var hasIn = function (t, list) { return list.some(function (m) { return contains(t, m); }); };
    var order = new Map();
    ctx.els.forEach(function (e, i) { order.set(e, i); });
    var tiles = outermost(Array.from(tileSet)).sort(function (a, b) {
      return (order.has(a) ? order.get(a) : 1e9) - (order.has(b) ? order.get(b) : 1e9);
    }).filter(function (t) {
      if (!REWARDISH.test(t.textContent || '')) return false;
      // A tile needs a status control/marker, or an expiration on a page we know lists offers.
      if (hasIn(t, addCtls) || hasIn(t, marks.added) || hasIn(t, marks.used)) return true;
      if (!hasIn(t, marks.exp)) return false;
      return !!defaultStatus || !!closestMatching(t, A.tileSelectors) || A.iconAdd === 'unlabeled' || A.clickUnknownTiles;
    });
    var out = [];
    var keys = {};
    tiles.forEach(function (t) {
      var ctl = null, i;
      for (i = 0; i < addCtls.length; i++) if (contains(t, addCtls[i])) { ctl = addCtls[i]; break; }
      var isAdded = marks.added.some(function (m) { return contains(t, m); });
      var isUsed = marks.used.some(function (m) { return contains(t, m); });
      if (!ctl && !isAdded && !isUsed && A.iconAdd === 'unlabeled') {
        var btns = Array.prototype.slice.call(t.querySelectorAll('button, [role="button"]')).filter(function (b) { return visible(b) && !denied(labelOf(b)); });
        if (btns.length === 1 && isIconOnly(btns[0])) ctl = btns[0];
      }
      var status = isUsed ? 'used' : isAdded ? 'added' : ctl ? 'available' : (defaultStatus || 'unknown');
      var click = ctl ? (closestClickable(ctl, t) || ctl) : null;
      if (!click && status === 'unknown' && A.clickUnknownTiles) {
        click = isClickable(t) ? t : closestClickable(t.querySelector(CLICKABLE) || t, t);
        if (click) status = 'available';
      }
      var d = describe(t);
      if (keys[d.key]) return;
      keys[d.key] = 1;
      d.status = status;
      d.el = t;
      d.click = status === 'available' ? click : null;
      out.push(d);
    });
    return { tiles: out, addCtls: addCtls, marks: marks, ctx: ctx };
  }

  function cardHints() {
    var text = ((document.body && document.body.innerText) || '').slice(0, 8000);
    var re = /(?:ending in|ending|card ending|acct\.? ending|account ending|•{2,}|\*{2,}|x{3,}|\(\s*-|\.{3})\s?(\d{4,5})\b/gi;
    var out = [], m;
    while ((m = re.exec(text)) && out.length < 6) if (out.indexOf(m[1]) < 0) out.push(m[1]);
    return out;
  }

  function loginShown(ctx) {
    var c = ctx || makeContext();
    return queryAll(c, 'input[type="password"], input[autocomplete="one-time-code"]').some(visible);
  }

  // ---------------------------------------------------------------------------------------------
  // Actions the app can call
  // ---------------------------------------------------------------------------------------------

  function summary(res) {
    var s = { tiles: 0, toAdd: 0, added: 0, used: 0 };
    res.tiles.forEach(function (t) {
      s.tiles++;
      if (t.status === 'available') s.toAdd++;
      else if (t.status === 'added') s.added++;
      else if (t.status === 'used') s.used++;
    });
    return s;
  }

  function state() {
    var ok = onAdapterDomain();
    var res = ok ? collect() : { tiles: [], ctx: makeContext() };
    var s = summary(res);
    return {
      type: 'state', engine: VERSION, url: String(location.href).slice(0, 400), host: location.hostname,
      main: window === window.top, login: loginShown(res.ctx), onDomain: ok,
      tiles: s.tiles, toAdd: s.toAdd, added: s.added, used: s.used,
      hints: ok && A.cardHint ? cardHints() : [], title: String(document.title || '').slice(0, 80)
    };
  }

  function findLoadMore(ctx) {
    var c = queryAllList(ctx, A.loadMoreSelectors).filter(visible)[0];
    if (c) return c;
    var list = ctx.els.filter(isClickable);
    for (var i = 0; i < list.length; i++) {
      var el = list[i];
      var l = labelOf(el);
      if (!l || l.length > 40 || !anyMatch(A.loadMoreRx, l) || denied(l) || !visible(el)) continue;
      if (el.tagName === 'A') {
        var href = el.getAttribute('href') || '';
        if (href && href.charAt(0) !== '#' && href.indexOf('javascript') !== 0) continue; // a link to another page
      }
      return el;
    }
    return null;
  }

  function signature() {
    var r = collect();
    return r.tiles.length + '|' + (document.documentElement.scrollHeight || 0);
  }

  async function expand(opts) {
    opts = opts || {};
    var rounds = opts.rounds || 20, stalls = 0, clicks = 0;
    for (var i = 0; i < rounds; i++) {
      var before = signature();
      var more = findLoadMore(makeContext());
      if (more) { try { more.click(); clicks++; } catch (e) { } }
      else window.scrollTo(0, document.documentElement.scrollHeight);
      await sleep(more ? (opts.loadMoreDelay || 1100) : (opts.scrollDelay || 700));
      if (signature() === before) { if (++stalls >= 2) break; } else stalls = 0;
    }
    window.scrollTo(0, 0);
    return { rounds: i, clicks: clicks };
  }

  function publicTile(t) {
    return {
      key: t.key, merchant: t.merchant, reward: t.reward, details: t.details, expires: t.expires,
      status: t.status, value: t.value, minSpend: t.minSpend, percent: t.percent, points: t.points
    };
  }

  async function scan(opts) {
    opts = opts || {};
    if (!onAdapterDomain()) return JSON.stringify({ ok: false, reason: 'domain', url: location.href, tiles: [] });
    var expanded = null;
    if (opts.expand) expanded = await expand(opts);
    var r = collect();
    return JSON.stringify({
      ok: true, url: String(location.href).slice(0, 400), complete: !!expanded,
      login: loginShown(r.ctx), hints: A.cardHint ? cardHints() : [],
      tiles: r.tiles.map(publicTile)
    });
  }

  async function addNext(opts) {
    opts = opts || {};
    var tried = new Set(opts.tried || []);
    var skip = (opts.skip || []).map(function (s) { return low(s); }).filter(Boolean);
    var r = collect();
    var skipped = 0, remaining = 0, pick = null;
    r.tiles.forEach(function (t) {
      if (t.status !== 'available' || !t.click || tried.has(t.key)) return;
      var hay = low(t.merchant + ' ' + t.reward);
      if (skip.some(function (w) { return hay.indexOf(w) >= 0; })) { skipped++; return; }
      if (denied(labelOf(t.click))) return;
      remaining++;
      if (!pick) pick = t;
    });
    if (!pick) return JSON.stringify({ clicked: false, skipped: skipped, remaining: 0 });
    try { pick.click.scrollIntoView({ block: 'center' }); } catch (e) { }
    await sleep(opts.preClickMs == null ? 250 : opts.preClickMs);
    if (!opts.dryRun) pick.click.click();
    return JSON.stringify({
      clicked: true, key: pick.key, merchant: pick.merchant, reward: pick.reward,
      skipped: skipped, remaining: remaining - 1, url: String(location.href).slice(0, 400)
    });
  }

  function statusOf(key) {
    var r = collect();
    for (var i = 0; i < r.tiles.length; i++) if (r.tiles[i].key === key) return r.tiles[i].status;
    return 'gone';
  }

  function errorText() {
    var ctx = makeContext();
    var cands = queryAll(ctx, '[role="alert"], [role="alertdialog"], [role="dialog"], [aria-live="assertive"], [class*="error" i], [class*="toast" i], [class*="snackbar" i], [class*="alert" i]');
    for (var i = 0; i < cands.length; i++) {
      var el = cands[i];
      if (!visible(el)) continue;
      var t = low(el.textContent).slice(0, 400);
      if (t && anyMatch(A.errorRx, t)) return norm(el.textContent).slice(0, 160);
    }
    return null;
  }

  async function goBack() {
    var ctx = makeContext();
    for (var i = 0; i < A.backSelectors.length; i++) {
      var el = queryAll(ctx, A.backSelectors[i]).filter(visible)[0];
      if (el) { try { el.click(); return 'button'; } catch (e) { } }
    }
    history.back();
    return 'history';
  }

  // A privacy-safe outline of the page structure, for fixing selectors when a bank changes its site.
  function outline() {
    var r = collect();
    function mask(s) {
      return norm(s).replace(/[\w.+-]+@[\w-]+\.[\w.]+/g, '[email]').replace(/(^|[^$\d,.])(\d[\d -]{3,}\d)/g, function (m0, pre) { return pre + '####'; });
    }
    function desc(el, depth) {
      if (!el || el.nodeType !== 1) return null;
      var o = { tag: el.tagName.toLowerCase() };
      ['data-testid', 'data-test-id', 'data-cy', 'role', 'type', 'variant', 'tabindex', 'aria-label', 'title'].forEach(function (a) {
        var v = el.getAttribute(a);
        if (v != null) o[a] = mask(v).slice(0, 60);
      });
      var cls = (el.getAttribute('class') || '').split(/\s+/).filter(Boolean).slice(0, 3).join(' ');
      if (cls) o.cls = cls;
      var dt = mask(directText(el)).slice(0, 60);
      if (dt) o.text = dt;
      if (el.shadowRoot) o.shadow = true;
      if (depth < 4 && el.children.length) {
        o.kids = Array.prototype.slice.call(el.children, 0, 8).map(function (k) { return desc(k, depth + 1); });
      }
      return o;
    }
    var path = (location.pathname || '') + String(location.hash || '').split('?')[0];
    return JSON.stringify({
      engine: VERSION, issuer: A.issuer, host: location.hostname, path: path, login: loginShown(r.ctx),
      counts: summary(r), markers: { add: r.addCtls.length, added: r.marks.added.length, used: r.marks.used.length, expiry: r.marks.exp.length },
      tiles: r.tiles.slice(0, 4).map(function (t) {
        return { status: t.status, merchant: mask(t.merchant), reward: mask(t.reward), expires: t.expires, html: desc(t.el, 0) };
      }),
      addControls: r.addCtls.slice(0, 8).map(function (el) { return desc(el, 2); }),
      buttons: r.ctx.els.filter(isClickable).filter(visible).slice(0, 50).map(function (el) { return mask(labelOf(el)).slice(0, 50); })
    }, null, 1);
  }

  // ---------------------------------------------------------------------------------------------
  // Tell the app what this page holds, again whenever it changes
  // ---------------------------------------------------------------------------------------------

  var lastSent = '';
  var timer = null;
  function report() {
    timer = null;
    if (document.hidden) return;
    var s;
    try { s = state(); } catch (e) { return; }
    if (!s.main && !s.tiles && !s.login) return;
    var j = JSON.stringify(s);
    if (j !== lastSent) { lastSent = j; post(s); }
  }
  function schedule(ms) {
    if (timer) clearTimeout(timer);
    timer = setTimeout(report, ms == null ? 1200 : ms);
  }

  window.__PK = {
    version: VERSION, adapter: A.issuer,
    state: state, scan: scan, addNext: addNext, statusOf: statusOf, errorText: errorText,
    goBack: goBack, expand: expand, outline: outline, report: function () { lastSent = ''; report(); return true; },
    parseExpiry: parseExpiry, parseReward: parseReward,
    configure: function (raw) { A = buildAdapter(raw); lastSent = ''; schedule(50); return true; }
  };

  try {
    new MutationObserver(function () { schedule(); }).observe(document.documentElement, { childList: true, subtree: true });
  } catch (e) { }
  var lastHref = location.href;
  setInterval(function () { if (location.href !== lastHref) { lastHref = location.href; schedule(600); } }, 1000);
  schedule(300);
})();
