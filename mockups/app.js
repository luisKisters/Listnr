/* ═══════════════════════════════════════════════════════════════════════════
   LISTNR · shared app model, player engine and Phone driver.

   Every variant on every page is one Phone instance. A Phone owns its own copy
   of the library, so playing in variant A never moves variant B, and its own
   playback interval. A variant definition only supplies screens; the tab bar,
   the routing, the engine, the guides and the persistence live here.

   Time model: one real second is 30 seconds of book time, multiplied by speed.
   ═══════════════════════════════════════════════════════════════════════════ */
(function (global) {
  'use strict';

  /* ── schemes + guides persistence ───────────────────────────────────────── */
  var SCHEMES = { '1': { name: 'Black · Purple' }, '2': { name: 'Black · Neon' } };
  var KEY_SCHEME = 'listnr-scheme';
  var KEY_GUIDES = 'listnr-guides';
  var root = document.documentElement;
  var panels = [];

  function store(k, v) { try { localStorage.setItem(k, v); } catch (e) {} }
  function read(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }

  /* ── icons: one stroke family, drawn, never a glyph ─────────────────────── */
  var IC = {
    search: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><circle cx="11" cy="11" r="6.4"/><path d="M15.8 15.8 20.5 20.5"/></svg>',
    caret: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m5.5 9 6.5 6 6.5-6"/></svg>',
    check: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 12.5 9.2 17.7 20 7"/></svg>',
    back: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="m14.5 5.5-6 6.5 6 6.5"/></svg>',
    down: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="m5.5 9.5 6.5 6 6.5-6"/></svg>',
    list: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><path d="M9 6.5h11M9 12h11M9 17.5h11"/><path d="M4.4 6.5h.9M4.4 12h.9M4.4 17.5h.9"/></svg>',
    moon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M20.2 14.6A8.6 8.6 0 0 1 9.4 3.8a8.6 8.6 0 1 0 10.8 10.8z"/></svg>',
    play: '<svg viewBox="0 0 24 24" fill="currentColor" stroke="none"><path d="M8.4 5.6a.8.8 0 0 1 1.22-.68l9.1 6.4a.8.8 0 0 1 0 1.36l-9.1 6.4A.8.8 0 0 1 8.4 18.4z"/></svg>',
    pause: '<svg viewBox="0 0 24 24" fill="currentColor" stroke="none"><rect x="6.6" y="4.6" width="4.2" height="14.8" rx="1.4"/><rect x="13.2" y="4.6" width="4.2" height="14.8" rx="1.4"/></svg>',
    prev: '<svg viewBox="0 0 24 24" fill="currentColor" stroke="none"><rect x="5" y="5" width="2.4" height="14" rx="1.2"/><path d="M19 6.4a.9.9 0 0 0-1.38-.76l-8 5.6a.9.9 0 0 0 0 1.52l8 5.6A.9.9 0 0 0 19 17.6z"/></svg>',
    next: '<svg viewBox="0 0 24 24" fill="currentColor" stroke="none"><rect x="16.6" y="5" width="2.4" height="14" rx="1.2"/><path d="M5 6.4a.9.9 0 0 1 1.38-.76l8 5.6a.9.9 0 0 1 0 1.52l-8 5.6A.9.9 0 0 1 5 17.6z"/></svg>',
    back15: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M4.5 8.5A8 8 0 1 1 4 12"/><path d="M4.2 4.6v4h4"/><text x="12" y="15.4" font-size="7.6" fill="currentColor" stroke="none" text-anchor="middle" font-family="-apple-system,sans-serif" font-weight="600">15</text></svg>',
    fwd30: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M19.5 8.5A8 8 0 1 0 20 12"/><path d="M19.8 4.6v4h-4"/><text x="12" y="15.4" font-size="7.6" fill="currentColor" stroke="none" text-anchor="middle" font-family="-apple-system,sans-serif" font-weight="600">30</text></svg>',
    tabLib: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M4 5.5A1.5 1.5 0 0 1 5.5 4H9v16H5.5A1.5 1.5 0 0 1 4 18.5z"/><path d="M9 4h4.5A1.5 1.5 0 0 1 15 5.5v13A1.5 1.5 0 0 1 13.5 20H9z"/><path d="m17.2 5.4 2.1 13.1"/></svg>',
    tabAud: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="8.4"/><path d="M10.4 9.2 15 12l-4.6 2.8z" fill="currentColor" stroke="none"/></svg>',
    tabRead: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 6.6C10.4 5.2 8.2 4.6 4.5 4.8v13c3.7-.2 5.9.4 7.5 1.8 1.6-1.4 3.8-2 7.5-1.8v-13c-3.7-.2-5.9.4-7.5 1.8z"/><path d="M12 6.6v13.1"/></svg>',
    target: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><circle cx="12" cy="12" r="6.2"/><path d="M12 2.6v3.4M12 18v3.4M2.6 12h3.4M18 12h3.4"/><circle cx="12" cy="12" r="1.4" fill="currentColor" stroke="none"/></svg>',
    tabScan: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M4 8.5v-3A1.5 1.5 0 0 1 5.5 4h3M15.5 4h3A1.5 1.5 0 0 1 20 5.5v3M20 15.5v3a1.5 1.5 0 0 1-1.5 1.5h-3M8.5 20h-3A1.5 1.5 0 0 1 4 18.5v-3"/><path d="M7.6 12h8.8"/></svg>'
  };

  /* ── the library ────────────────────────────────────────────────────────── */
  var BOOKS = [
    { id: 'phm', tone: 1, seed: 'hailmary', title: 'Project Hail Mary',
      author: 'Andy Weir', narrator: 'Ray Porter', formats: ['audio'],
      dur: 36960, pos: 15153, speed: 1, chapters: 29, word: 'Chapter',
      names: { 1: 'Waking Up', 6: 'Astrophage', 12: 'Rocky', 21: 'Taumoeba' } },

    { id: 'dsw', tone: 2, seed: 'schwarm', title: 'Der Schwarm',
      author: 'Frank Schätzing', narrator: 'Frank Glaubrecht', formats: ['audio'],
      dur: 90000, pos: 5892, speed: 1.2, chapters: 46, word: 'Kapitel',
      names: { 1: 'Prolog', 3: 'Vancouver Island', 4: 'Norwegische See' } },

    { id: 'tde', tone: 3, seed: 'dawnofall', title: 'The Dawn of Everything',
      author: 'Graeber & Wengrow', narrator: 'Mark Williams', formats: ['audio'],
      dur: 63000, pos: 0, speed: 1, chapters: 12, word: 'Chapter',
      names: { 1: 'Farewell to Humanity’s Childhood', 3: 'Unfreezing the Ice Age' } },

    { id: 'pir', tone: 4, seed: 'piranesihalls', title: 'Piranesi',
      author: 'Susanna Clarke', narrator: 'Chiwetel Ejiofor', formats: ['ebook', 'audio'],
      dur: 24680, pos: 11106, speed: 1.5, chapters: 24, word: 'Chapter', pages: 272,
      names: { 1: 'The House', 12: 'The Drowned Halls', 24: 'The Halls' } },

    { id: 'sot', tone: 5, seed: 'tranquility', title: 'Sea of Tranquility',
      author: 'Emily St. John Mandel', formats: ['ebook'], pages: 272, page: 148 }
  ];

  var SPEEDS = [1, 1.2, 1.5, 1.75, 2];
  var SLEEPS = [15, 30, 60];
  /* `l` is the full word; `s` is the one a fixed-width segment can afford.
     Only the segmented variant spends the short form. */
  var FILTERS = [
    { k: 'all', l: 'All', s: 'All' },
    { k: 'audio', l: 'Audiobooks', s: 'Audio' },
    { k: 'ebook', l: 'Ebooks', s: 'Ebooks' },
    { k: 'paired', l: 'Paired', s: 'Paired' },
    { k: 'progress', l: 'In progress', s: 'Active' }
  ];
  var SORTS = [{ k: 'recent', l: 'Recent' }, { k: 'title', l: 'Title' }, { k: 'length', l: 'Length' }];

  /* ── formatting ─────────────────────────────────────────────────────────── */
  function esc(t) {
    return String(t).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  function hms(s) {
    s = Math.max(0, Math.round(s));
    var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), x = s % 60;
    return h + ':' + (m < 10 ? '0' : '') + m + ':' + (x < 10 ? '0' : '') + x;
  }
  function span(s) {
    s = Math.max(0, Math.round(s));
    var h = Math.floor(s / 3600), m = Math.round((s % 3600) / 60);
    if (m === 60) { h += 1; m = 0; }
    return h ? h + 'h ' + (m < 10 ? '0' : '') + m + 'm' : m + 'm';
  }
  function chapLeftText(s) {
    s = Math.max(0, Math.round(s));
    var m = Math.floor(s / 60), x = s % 60;
    return (m ? m + 'm ' + (x < 10 ? '0' : '') : '') + x + 's left';
  }
  function coverHTML(b, px) {
    return '<img src="https://picsum.photos/seed/' + encodeURIComponent(b.seed) + '/' + px + '/' + px +
      '" alt="" loading="lazy" decoding="async" width="' + px + '" height="' + px + '">';
  }

  function hasAudio(b) { return b.formats.indexOf('audio') > -1; }
  function isPaired(b) { return b.formats.length > 1; }
  function frac(b) { return hasAudio(b) ? b.pos / b.dur : b.page / b.pages; }
  function pct(b) { return Math.max(0, Math.min(100, frac(b) * 100)); }
  function state(b) {
    var f = frac(b);
    if (f <= 0) return 'new';
    if (f >= 0.999) return 'done';
    return 'on';
  }
  function formatWord(b) {
    if (isPaired(b)) return 'Ebook and audiobook';
    return hasAudio(b) ? 'Audiobook' : 'Ebook';
  }
  /* the one quiet metadata line. Format first, then whatever is true of it. */
  function metaLine(b, withPct) {
    var f = formatWord(b), s = state(b);
    var p = Math.round(pct(b)) + '%';
    if (!hasAudio(b)) {
      if (s === 'new') return f + ' · ' + b.pages + ' pages';
      if (s === 'done') return f + ' · finished';
      return f + ' · ' + (withPct ? p + ' · ' : '') + 'page ' + b.page + ' of ' + b.pages;
    }
    if (s === 'new') return f + ' · ' + span(b.dur);
    if (s === 'done') return f + ' · finished';
    return f + ' · ' + (withPct ? p + ' · ' : '') + span(b.dur - b.pos) + ' left';
  }

  /* ── chapters ───────────────────────────────────────────────────────────── */
  function chapLen(b) { return b.dur / b.chapters; }
  function chapIndex(b) { return Math.max(0, Math.min(b.chapters - 1, Math.floor(b.pos / chapLen(b)))); }
  function chapName(b, i) {
    var n = i + 1;
    return b.word + ' ' + n + (b.names[n] ? ' — ' + b.names[n] : '');
  }

  /* ── the tab bar, present on every screen of every variant ──────────────── */
  var TABS = [
    ['library', 'Library', IC.tabLib],
    ['audiobook', 'Audiobook', IC.tabAud],
    ['reader', 'Reader', IC.tabRead],
    ['scan', 'Scan', IC.tabScan]
  ];
  function tabbar(st) {
    return '<nav class="tabbar" aria-label="App tabs">' + TABS.map(function (t) {
      return '<button type="button" data-act="tab" data-arg="' + t[0] + '" aria-label="' + t[1] +
        '" aria-current="' + (st.tab === t[0] ? 'true' : 'false') + '">' + t[2] + '</button>';
    }).join('') + '</nav>';
  }

  function underConstruction(line) {
    return '<div class="screen"><div class="uc"><p>' + esc(line) + '</p></div></div>';
  }

  /* ═══ THE PHONE ═════════════════════════════════════════════════════════ */
  function Phone(host, def) {
    this.host = host;
    this.def = def || {};
    this.books = JSON.parse(JSON.stringify(BOOKS));
    this.st = {
      tab: this.def.tab || 'library',
      book: 'phm',            /* last listened  */
      reading: 'sot',         /* last read      */
      filter: 'all',
      sort: 'recent',
      q: '',
      menu: false,
      sleep: null,
      sleepLeft: 0,
      chaps: false,
      playing: false
    };
    this.timer = null;
    var self = this;
    host.addEventListener('click', function (e) { self.onClick(e); });
    host.addEventListener('input', function (e) { self.onInput(e); });
    panels.push(this);
    this.paint();
  }

  Phone.prototype.book = function (id) {
    id = id || this.st.book;
    for (var i = 0; i < this.books.length; i++) if (this.books[i].id === id) return this.books[i];
    return this.books[0];
  };
  Phone.prototype.all = function () { return this.books; };

  /* ---- filtering + sorting, shared by all four library variants ---------- */
  Phone.prototype.list = function () {
    var st = this.st, q = st.q.trim().toLowerCase();
    return this.books.filter(function (b) {
      if (q && (b.title + ' ' + b.author).toLowerCase().indexOf(q) < 0) return false;
      if (st.filter === 'audio') return hasAudio(b);
      if (st.filter === 'ebook') return b.formats.indexOf('ebook') > -1;
      if (st.filter === 'paired') return isPaired(b);
      if (st.filter === 'progress') return state(b) === 'on';
      return true;
    }).slice().sort(function (a, b) {
      if (st.sort === 'title') return a.title.localeCompare(b.title);
      if (st.sort === 'length') return (b.dur || 0) - (a.dur || 0);
      return 0;
    });
  };

  /* ---- engine ------------------------------------------------------------ */
  Phone.prototype.play = function () {
    if (this.st.playing) return;
    var b = this.book();
    if (!hasAudio(b)) return;
    this.st.playing = true;
    var self = this;
    this.timer = setInterval(function () { self.tick(); }, 1000);
    this.paint();
  };
  Phone.prototype.pause = function () {
    this.st.playing = false;
    if (this.timer) { clearInterval(this.timer); this.timer = null; }
    this.paint();
  };
  Phone.prototype.tick = function () {
    var b = this.book(), step = 30 * b.speed;
    b.pos += step;
    if (this.st.sleep) {
      this.st.sleepLeft -= step;
      if (this.st.sleepLeft <= 0) { this.st.sleep = null; this.st.sleepLeft = 0; return this.pause(); }
    }
    if (b.pos >= b.dur) { b.pos = b.dur; return this.pause(); }
    this.paint();
  };
  Phone.prototype.seek = function (s) {
    var b = this.book();
    if (!hasAudio(b)) return;
    b.pos = Math.max(0, Math.min(b.dur, s));
    this.paint();
  };
  Phone.prototype.prevChapter = function () {
    var b = this.book(), len = chapLen(b), i = chapIndex(b);
    this.seek(b.pos - i * len > 4 ? i * len : Math.max(0, (i - 1) * len));
  };
  Phone.prototype.nextChapter = function () {
    var b = this.book(), len = chapLen(b), i = chapIndex(b);
    this.seek(Math.min(b.dur - 1, (i + 1) * len));
  };
  Phone.prototype.openBook = function (id) {
    var b = this.book(id);
    if (!hasAudio(b)) { this.st.reading = id; this.st.tab = 'reader'; return this.paint(); }
    if (id !== this.st.book) {
      if (this.st.playing) this.pause();
      this.st.book = id;
      this.st.chaps = false; this.st.sleepOpen = false;
    }
    this.st.tab = 'audiobook';
    this.paint();
  };

  /* ---- click routing ----------------------------------------------------- */
  Phone.prototype.onClick = function (e) {
    var el = e.target.closest ? e.target.closest('[data-act]') : null;
    if (!el || !this.host.contains(el)) return;
    var a = el.getAttribute('data-act'), arg = el.getAttribute('data-arg');
    var st = this.st, b = this.book();

    if (a === 'tab') { st.tab = arg; if (arg === 'audiobook') st.chaps = st.chaps; return this.paint(); }
    if (a === 'book') return this.openBook(arg);
    if (a === 'resume') return this.openBook(st.book);
    if (a === 'resume-read') { st.tab = 'reader'; return this.paint(); }
    if (a === 'back') { st.tab = 'library'; return this.paint(); }
    if (a === 'play') { return st.playing ? this.pause() : this.play(); }
    if (a === 'back15') return this.seek(b.pos - 15);
    if (a === 'fwd30') return this.seek(b.pos + 30);
    if (a === 'prevch') return this.prevChapter();
    if (a === 'nextch') return this.nextChapter();
    if (a === 'speed') {
      b.speed = SPEEDS[(SPEEDS.indexOf(b.speed) + 1) % SPEEDS.length];
      return this.paint();
    }
    if (a === 'sleep') { st.sleepOpen = !st.sleepOpen; st.chaps = false; return this.paint(); }
    if (a === 'sleepset') {
      if (arg === 'off') { st.sleep = null; st.sleepLeft = 0; }
      else { st.sleep = +arg; st.sleepLeft = +arg * 60; }
      st.sleepOpen = false;
      return this.paint();
    }
    if (a === 'chaps') { st.chaps = !st.chaps; st.sleepOpen = false; return this.paint(); }
    if (a === 'chapter') { st.chaps = false; return this.seek(+arg * chapLen(b)); }
    if (a === 'filter') { st.filter = arg; st.menu = false; return this.paint(); }
    if (a === 'menu') { st.menu = !st.menu; return this.paint(); }
    if (a === 'sort') {
      st.sort = SORTS[(indexOfKey(SORTS, st.sort) + 1) % SORTS.length].k;
      return this.paint();
    }
  };
  function indexOfKey(arr, k) {
    for (var i = 0; i < arr.length; i++) if (arr[i].k === k) return i;
    return 0;
  }

  /* search filters without a repaint, so the caret never jumps */
  Phone.prototype.onInput = function (e) {
    if (!e.target.matches('input[data-search]')) return;
    this.st.q = e.target.value;
    var keep = {};
    this.list().forEach(function (b) { keep[b.id] = 1; });
    var rows = this.host.querySelectorAll('[data-row]');
    Array.prototype.forEach.call(rows, function (r) {
      r.hidden = !keep[r.getAttribute('data-row')];
    });
    var groups = this.host.querySelectorAll('[data-group]');
    Array.prototype.forEach.call(groups, function (g) {
      g.hidden = !g.querySelector('[data-row]:not([hidden])');
    });
  };

  /* ---- paint ------------------------------------------------------------- */
  Phone.prototype.paint = function () {
    var st = this.st, def = this.def;
    var scrolls = {};
    Array.prototype.forEach.call(this.host.querySelectorAll('[data-keep]'), function (n) {
      scrolls[n.getAttribute('data-keep')] = n.scrollTop;
    });
    var focused = document.activeElement;
    var refocus = focused && this.host.contains(focused) && focused.matches('input[data-search]');

    var body;
    if (st.tab === 'library') body = (def.library || AB.libraryDefault).call(def, this, st);
    else if (st.tab === 'audiobook') body = (def.player || AB.playerDefault).call(def, this, st);
    else if (st.tab === 'reader') body = underConstruction('The reader is not built yet — it arrives with the paired EPUB.');
    else body = underConstruction('Scan-to-sync is not built yet — it arrives after notes.');

    this.host.innerHTML =
      '<div class="notch" aria-hidden="true"></div>' +
      '<div class="stat" aria-hidden="true"><b>9:41</b><span>' +
        '<svg viewBox="0 0 24 24" fill="currentColor" stroke="none"><rect x="2" y="14" width="3.4" height="6" rx="1"/><rect x="7.4" y="10.5" width="3.4" height="9.5" rx="1"/><rect x="12.8" y="7" width="3.4" height="13" rx="1"/><rect x="18.2" y="3.5" width="3.4" height="16.5" rx="1"/></svg>' +
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="M2.6 8.7a13.6 13.6 0 0 1 18.8 0"/><path d="M6.1 12.4a8.7 8.7 0 0 1 11.8 0"/><path d="M9.5 16a4.2 4.2 0 0 1 5 0"/><path d="M12 19.3h.01"/></svg>' +
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="1.8" y="7.6" width="17" height="8.8" rx="2.6"/><path d="M21.4 11v2" stroke-linecap="round"/><rect x="3.8" y="9.6" width="10.4" height="4.8" rx="1.2" fill="currentColor" stroke="none"/></svg>' +
      '</span></div>' +
      body + tabbar(st) +
      '<div class="homebar" aria-hidden="true"><i></i></div>' +
      this.guides();

    var self = this;
    Object.keys(scrolls).forEach(function (k) {
      var n = self.host.querySelector('[data-keep="' + k + '"]');
      if (n) n.scrollTop = scrolls[k];
    });
    var input = this.host.querySelector('input[data-search]');
    if (input) {
      input.value = st.q;
      if (refocus) { input.focus(); input.setSelectionRange(st.q.length, st.q.length); }
    }
    this.bindScrubber();
    this.bindWheel();
  };

  /* ---- the guides overlay: rails only, repainted with every state ------- */
  Phone.prototype.guides = function () {
    var rails = this.st.rails || [];          /* extra vertical rails, px from left */
    var h = '<div class="guides" aria-hidden="true">' +
      '<i class="v" style="left:var(--ins)"></i>' +
      '<i class="v" style="right:var(--ins)"></i>' +
      '<i class="v c" style="left:50%"></i>';
    rails.forEach(function (x) {
      h += (x === 'edge')
        ? '<i class="v" style="left:0"></i><i class="v" style="right:0"></i>'
        : '<i class="v" style="left:calc(var(--ins) + ' + x + 'px)"></i>';
    });
    return h + '<i class="h" style="bottom:calc(var(--tab-h) + var(--home-h))"></i></div>';
  };

  /* ---- chapter wheel: settle on a row and playback follows ---------------- */
  Phone.prototype.bindWheel = function () {
    var wl = this.host.querySelector('.wheel');
    if (!wl) return;
    var self = this, t = null;
    function highlight(i) {
      Array.prototype.forEach.call(wl.querySelectorAll('button'), function (btn, j) {
        btn.setAttribute('aria-current', j === i ? 'true' : 'false');
      });
    }
    function settle() {
      var b = self.book();
      var i = Math.max(0, Math.min(b.chapters - 1, Math.round(wl.scrollTop / 36)));
      if (i !== chapIndex(b)) { self.seek(i * chapLen(b)); return; }
      highlight(i);
      try { wl.scrollTo({ top: i * 36 }); } catch (e) { wl.scrollTop = i * 36; }
    }
    wl.addEventListener('scroll', function () {
      if (t) clearTimeout(t);
      t = setTimeout(settle, 90);
    }, { passive: true });
    /* land exactly on the snap point of the playing chapter so CSS snap,
       the restored scroll offset and the engine state can never disagree */
    var b0 = this.book();
    try { wl.scrollTo({ top: chapIndex(b0) * 36 }); } catch (e) { wl.scrollTop = chapIndex(b0) * 36; }
  };

  /* ---- scrubber: tap and drag ------------------------------------------- */
  Phone.prototype.bindScrubber = function () {
    var tl = this.host.querySelector('.timeline');
    if (!tl) return;
    var self = this, dragging = false;
    function at(e) {
      var r = tl.getBoundingClientRect();
      self.seek(self.book().dur * Math.max(0, Math.min(1, (e.clientX - r.left) / r.width)));
    }
    tl.addEventListener('pointerdown', function (e) {
      dragging = true;
      try { tl.setPointerCapture(e.pointerId); } catch (err) {}
      at(e); e.preventDefault();
    });
    tl.addEventListener('pointermove', function (e) { if (dragging) at(e); });
    tl.addEventListener('pointerup', function () { dragging = false; });
    tl.addEventListener('pointercancel', function () { dragging = false; });
    tl.addEventListener('keydown', function (e) {
      var step = self.book().dur / 100;
      if (e.key === 'ArrowRight') { self.seek(self.book().pos + step); e.preventDefault(); }
      if (e.key === 'ArrowLeft') { self.seek(self.book().pos - step); e.preventDefault(); }
    });
  };

  /* ═══ SHARED SCREEN PIECES ══════════════════════════════════════════════ */

  function searchField() {
    return '<div class="search">' + IC.search +
      '<input type="text" data-search placeholder="Search your books" aria-label="Search your books"></div>';
  }

  /* one row renderer, four progress attributions */
  function bookRow(b, mode) {
    var p = pct(b).toFixed(1);
    var on = state(b) !== 'new';
    var line = '<span class="line"><i style="width:' + p + '%"></i></span>';
    var cover = '<span class="cover c' + b.tone + '" aria-hidden="true">' + coverHTML(b, 300) +
      (mode === 'b' && on ? '<span class="inline-p"><i style="width:' + p + '%"></i></span>' : '') + '</span>';
    var meta = '<span class="book-f">' + esc(metaLine(b, mode === 'd')) + '</span>';
    var inner =
      '<span class="book-t">' + esc(b.title) + '</span>' +
      '<span class="book-a">' + esc(b.author) + '</span>' +
      (mode === 'c' && on ? '<span class="book-p">' + line + '</span>' : '') +
      meta;
    return '<button type="button" class="book book--' + mode + '" data-act="book" data-arg="' + b.id +
      '" data-row="' + b.id + '" data-state="' + state(b) + '">' + cover +
      '<span class="book-x">' + inner + '</span>' +
      (mode === 'a' && on ? '<span class="book-p">' + line + '</span>' : '') +
      '</button>';
  }

  function resumeRow(b, label, act, mode) {
    mode = mode || 'a';
    var p = pct(b).toFixed(1), on = state(b) !== 'new';
    var line = '<span class="line"><i style="width:' + p + '%"></i></span>';
    var right = hasAudio(b) ? span(b.dur - b.pos) + ' left' : 'page ' + b.page + ' of ' + b.pages;
    if (mode === 'd') right = Math.round(pct(b)) + '% · ' + right;
    var left = hasAudio(b) ? chapName(b, chapIndex(b)) : formatWord(b);
    var cover = '<span class="cover c' + b.tone + '" aria-hidden="true">' + coverHTML(b, 300) +
      (mode === 'b' && on ? '<span class="inline-p"><i style="width:' + p + '%"></i></span>' : '') + '</span>';
    return '<div class="sect">' + esc(label) + '</div>' +
      '<button type="button" class="now now--' + mode + '" data-act="' + act + '">' + cover +
      '<span class="now-x"><span class="now-t">' + esc(b.title) + '</span>' +
      '<span class="now-a">' + esc(b.author) + '</span>' +
      (mode === 'c' && on ? '<span class="now-mid">' + line + '</span>' : '') +
      '<span class="now-m"><span>' + esc(left) + '</span><span>' + esc(right) + '</span></span></span>' +
      (mode === 'a' && on ? '<span class="now-p">' + line + '</span>' : '') +
      '</button>';
  }

  /* ---- player pieces ----------------------------------------------------- */
  function scrubber(b) {
    var p = pct(b).toFixed(2), i = chapIndex(b);
    return '<div class="timeline" role="slider" tabindex="0" aria-label="Playback position"' +
      ' aria-valuemin="0" aria-valuemax="100" aria-valuenow="' + Math.round(p) + '">' +
      '<span class="tl-track"></span><span class="tl-fill" style="width:' + p + '%"></span>' +
      '<span class="tl-knob" style="left:' + p + '%"></span></div>' +
      '<div class="times"><span>' + hms(b.pos) + '</span><span>' +
      chapLeftText((i + 1) * chapLen(b) - b.pos) + '</span><span>−' + hms(b.dur - b.pos) + '</span></div>';
  }
  function transport(st, small) {
    return '<div class="transport' + (small ? ' transport--sm' : '') + '">' +
      '<button type="button" class="skip" data-act="prevch" aria-label="Previous chapter">' + IC.prev + '</button>' +
      '<button type="button" data-act="back15" aria-label="Back 15 seconds">' + IC.back15 + '</button>' +
      '<button type="button" class="play" data-act="play" aria-label="' + (st.playing ? 'Pause' : 'Play') + '">' +
      (st.playing ? IC.pause : IC.play) + '</button>' +
      '<button type="button" data-act="fwd30" aria-label="Forward 30 seconds">' + IC.fwd30 + '</button>' +
      '<button type="button" class="skip" data-act="nextch" aria-label="Next chapter">' + IC.next + '</button>' +
      '</div>';
  }
  function chapterRow(b, center) {
    return '<button type="button" class="pl-chap' + (center ? ' pl-chap--center' : '') + '" data-act="chaps">' +
      IC.list + '<span>' + esc(chapName(b, chapIndex(b))) + '</span></button>';
  }
  function utilRow(b, st) {
    var sleepVal = st.sleep ? Math.max(1, Math.ceil(st.sleepLeft / 60)) + 'm' : null;
    return '<div class="util">' +
      '<button type="button" data-act="speed" aria-label="Playback speed">' +
        '<span class="u-v">' + b.speed.toFixed(1) + '×</span><span class="u-n">Speed</span></button>' +
      '<button type="button" data-act="sleep" aria-expanded="' + (st.sleepOpen ? 'true' : 'false') + '" aria-label="Sleep timer">' +
        (sleepVal ? '<span class="u-v">' + sleepVal + '</span>' : IC.moon) + '<span class="u-n">Sleep</span></button>' +
      '<button type="button" data-act="chaps" aria-expanded="' + (st.chaps ? 'true' : 'false') + '" aria-label="Chapters">' +
        IC.list + '<span class="u-n">Chapters</span></button>' +
      '</div>';
  }
  function sleepPicker(st) {
    if (!st.sleepOpen) return '';
    var h = '<div class="inline"><div class="inline__opts">';
    SLEEPS.forEach(function (m) {
      h += '<button type="button" data-act="sleepset" data-arg="' + m + '" aria-pressed="' +
        (st.sleep === m ? 'true' : 'false') + '">' + m + ' min</button>';
    });
    h += '<button type="button" data-act="sleepset" data-arg="off" aria-pressed="' +
      (st.sleep ? 'false' : 'true') + '">Off</button>';
    return h + '</div></div>';
  }
  function chapterList(b, st, max) {
    if (!st.chaps) return '';
    return '<div class="inline"><div class="chaps" data-keep="chaps"' +
      (max ? ' style="max-height:' + max + '"' : '') + '>' + chapterListRows(b) + '</div></div>';
  }

  /* the chapter wheel: the iOS time-picker drum. The cover's place is taken by a
     wheel whose rows shrink and fade toward the edges; settling on a row seeks it. */
  function wheelBox(b) {
    var cur = chapIndex(b), h = '<div class="wheelbox"><div class="wheel" data-keep="wheel" role="listbox" aria-label="Chapters">';
    for (var i = 0; i < b.chapters; i++) {
      h += '<button type="button" role="option" data-act="chapter" data-arg="' + i +
        '" aria-current="' + (i === cur ? 'true' : 'false') + '">' + esc(chapName(b, i)) + '</button>';
    }
    return h + '</div><i class="wheel-sel" aria-hidden="true"></i></div>';
  }
  function chapterListRows(b) {
    var cur = chapIndex(b), len = chapLen(b), h = '';
    for (var i = 0; i < b.chapters; i++) {
      h += '<button type="button" data-act="chapter" data-arg="' + i + '" aria-current="' +
        (i === cur ? 'true' : 'false') + '"><b>' + esc(chapName(b, i)) + '</b><i>' + span(len) + '</i></button>';
    }
    return h;
  }

  /* ═══ DEFAULT SCREENS ═══════════════════════════════════════════════════
     Library pages override the library screen; the player page overrides the
     player. Whichever is not the subject of a page uses the default below, so
     the tab bar always leads somewhere real.                                */

  function libraryDefault(p, st) {
    st.rails = [64];
    var rows = p.list().map(function (b) { return bookRow(b, 'a'); }).join('');
    return '<div class="screen">' +
      '<div class="h1">Library</div>' + searchField() +
      '<div class="filters">' + FILTERS.map(function (f) {
        return '<button type="button" data-act="filter" data-arg="' + f.k + '" aria-pressed="' +
          (st.filter === f.k ? 'true' : 'false') + '">' + f.l + '</button>';
      }).join('') + '</div>' +
      '<div class="scroll" data-keep="list">' + resumeRow(p.book(st.book), 'Listening', 'resume') +
      '<div class="sect">All books</div>' + rows + '</div></div>';
  }

  function playerDefault(p, st) {
    st.rails = [];
    var b = p.book();
    return '<div class="screen">' +
      '<div class="pl-top"><button type="button" data-act="back" aria-label="Back to library">' + IC.down + '</button>' +
      '<span class="pl-top__c">' + esc(formatWord(b)) + '</span><span style="width:36px"></span></div>' +
      '<i class="gap gap--sm"></i>' +
      (st.chaps
        ? '<div class="inline inline--flex">' + wheelBox(b) + '</div>'
        : '<span class="cover pl-cover c' + b.tone + '" aria-hidden="true">' +
          coverHTML(b, 600) + '<span class="scrim"></span></span>') +
      '<i class="gap"></i>' +
      '<div class="pl-id"><div class="pl-t">' + esc(b.title) + '</div>' +
      '<div class="pl-a">' + esc(b.author + (b.narrator ? ' · ' + b.narrator : '')) + '</div></div>' +
      chapterRow(b) +
      '<i class="gap gap--sm"></i>' +
      scrubber(b) + transport(st) + utilRow(b, st) + sleepPicker(st) +
      '</div>';
  }

  /* ═══ PAGE CHROME: nav + scheme bar ═════════════════════════════════════ */
  var PAGES = [
    ['index.html', 'Direction'], ['library.html', 'Library'],
    ['audiobook.html', 'Audiobook'], ['reader.html', 'Reader'], ['scan.html', 'Scan']
  ];
  function chrome(current, note) {
    var head = document.querySelector('.pg-head');
    if (head) {
      head.innerHTML =
        '<span class="pg-head__brand">listnr</span>' +
        '<span class="pg-head__note">' + esc(note || '') + '</span>' +
        '<nav class="pg-head__nav" aria-label="Mockups">' + PAGES.map(function (pg) {
          return '<a href="' + pg[0] + '"' + (pg[0] === current ? ' aria-current="page"' : '') + '>' + pg[1] + '</a>';
        }).join('') + '</nav>';
    }

    var bar = document.createElement('nav');
    bar.className = 'schemebar';
    bar.setAttribute('aria-label', 'Colour scheme and alignment guides');
    bar.innerHTML = '<div class="inner"><div class="nums">' +
      Object.keys(SCHEMES).map(function (n) {
        return '<button type="button" data-scheme="' + n + '" aria-label="Scheme ' + n + ' — ' +
          SCHEMES[n].name + '">' + n + '</button>';
      }).join('') + '</div>' +
      '<button class="guidebtn" type="button" id="ab-guides" aria-pressed="false" aria-label="Alignment guides">' + IC.target + '</button>' +
      '<span class="name" id="ab-schemename" aria-live="polite"></span></div>';
    document.body.appendChild(bar);

    var nameEl = bar.querySelector('#ab-schemename');
    var btns = bar.querySelectorAll('[data-scheme]');
    function applyScheme(n, save) {
      if (!SCHEMES[n]) n = '1';
      root.setAttribute('data-scheme', n);
      nameEl.textContent = SCHEMES[n].name;
      Array.prototype.forEach.call(btns, function (b) {
        b.setAttribute('aria-pressed', b.getAttribute('data-scheme') === n ? 'true' : 'false');
      });
      var meta = document.querySelector('meta[name="theme-color"]');
      if (meta) meta.setAttribute('content', '#050505');
      if (save) store(KEY_SCHEME, n + '|' + SCHEMES[n].name);
    }
    Array.prototype.forEach.call(btns, function (b) {
      b.addEventListener('click', function () { applyScheme(b.getAttribute('data-scheme'), true); });
    });
    var stored = read(KEY_SCHEME), pick = '1';
    if (stored) {
      var parts = String(stored).split('|');
      if (SCHEMES[parts[0]] && parts[1] === SCHEMES[parts[0]].name) pick = parts[0];
      else store(KEY_SCHEME, '');
    }
    applyScheme(pick, false);

    var gbtn = bar.querySelector('#ab-guides');
    function applyGuides(on, save) {
      root.setAttribute('data-guides', on ? '1' : '0');
      gbtn.setAttribute('aria-pressed', on ? 'true' : 'false');
      if (save) store(KEY_GUIDES, on ? '1' : '0');
      panels.forEach(function (p) { p.paint(); });
    }
    gbtn.addEventListener('click', function () {
      applyGuides(root.getAttribute('data-guides') !== '1', true);
    });
    applyGuides(read(KEY_GUIDES) === '1', false);
  }

  /* ---- build the A–D row from a variant map ------------------------------ */
  function mount(hostId, defs, order) {
    var host = document.getElementById(hostId);
    host.innerHTML = order.map(function (k, i) {
      return '<div class="pg-var">' +
        '<div class="pg-var__head"><span class="pg-var__key">' + 'ABCD'[i] + '</span>' +
        '<span class="pg-var__name">' + esc(defs[k].name) + '</span></div>' +
        '<div class="phone"><div class="ios" id="ph-' + k + '"></div></div>' +
        '<p class="pg-var__why">' + defs[k].why + '</p></div>';
    }).join('');
    return order.map(function (k) { return new Phone(document.getElementById('ph-' + k), defs[k]); });
  }
  function mountOne(hostId, def) {
    return new Phone(document.getElementById(hostId), def);
  }

  var AB = {
    IC: IC, BOOKS: BOOKS, SPEEDS: SPEEDS, SLEEPS: SLEEPS, FILTERS: FILTERS, SORTS: SORTS,
    Phone: Phone, chrome: chrome, mount: mount, mountOne: mountOne,
    esc: esc, hms: hms, span: span, coverHTML: coverHTML, pct: pct, frac: frac, state: state,
    hasAudio: hasAudio, isPaired: isPaired, formatWord: formatWord, metaLine: metaLine,
    chapLen: chapLen, chapIndex: chapIndex, chapName: chapName, chapterListRows: chapterListRows,
    wheelBox: wheelBox,
    searchField: searchField, bookRow: bookRow, resumeRow: resumeRow,
    scrubber: scrubber, transport: transport, chapterRow: chapterRow, utilRow: utilRow,
    sleepPicker: sleepPicker, chapterList: chapterList, underConstruction: underConstruction,
    libraryDefault: libraryDefault, playerDefault: playerDefault
  };
  global.AB = AB;
})(window);
