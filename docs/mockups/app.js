/* ═══════════════════════════════════════════════════════════════════════════
   LISTNR · shared app model, player engine and Phone driver.

   Every phone on every page is one Phone instance with its own copy of the
   library and its own playback interval. The two locked screens — Library B
   and Player A — live in this file, so every tab bar in the set leads to the
   same real screen; the pages only host them.

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
    tabScan: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M4 8.5v-3A1.5 1.5 0 0 1 5.5 4h3M15.5 4h3A1.5 1.5 0 0 1 20 5.5v3M20 15.5v3a1.5 1.5 0 0 1-1.5 1.5h-3M8.5 20h-3A1.5 1.5 0 0 1 4 18.5v-3"/><path d="M7.6 12h8.8"/></svg>',
    pencil: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M4.6 19.4v-3.2L15.7 5.1a2.26 2.26 0 0 1 3.2 3.2L7.8 19.4z"/><path d="m14.4 6.4 3.2 3.2"/></svg>',
    plus: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="M12 5.2v13.6M5.2 12h13.6"/></svg>',
    shoot: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M4 8.6v-3A1.6 1.6 0 0 1 5.6 4h3M15.4 4h3A1.6 1.6 0 0 1 20 5.6v3M20 15.4v3a1.6 1.6 0 0 1-1.6 1.6h-3M8.6 20h-3A1.6 1.6 0 0 1 4 18.4v-3"/><path d="M8 10.4h8M8 13.6h5.4"/></svg>'
  };

  /* ── the library ────────────────────────────────────────────────────────── */
  var BOOKS = [
    { id: 'phm', tone: 1, seed: 'hailmary', title: 'Project Hail Mary',
      author: 'Andy Weir', narrator: 'Ray Porter', formats: ['audio'],
      dur: 36960, pos: 15153, speed: 1, chapters: 29, word: 'Chapter',
      names: { 1: 'Waking Up', 6: 'Astrophage', 12: 'Rocky', 21: 'Taumoeba' },
      notes: [
        { t: 12480, text: 'Rocky answers in chords, not words — the whole friendship is built on that.' },
        { t: 7305, text: 'Astrophage doubles every eight days. That number is the book\u2019s clock.' },
        { t: 2110, text: 'The amnesia framing lets the physics arrive at the reader\u2019s pace.' }
      ] },

    { id: 'dsw', tone: 2, seed: 'schwarm', title: 'Der Schwarm',
      author: 'Frank Schätzing', narrator: 'Frank Glaubrecht', formats: ['audio'],
      dur: 90000, pos: 5892, speed: 1.2, chapters: 46, word: 'Kapitel',
      names: { 1: 'Prolog', 3: 'Vancouver Island', 4: 'Norwegische See' } },

    /* `prep` is how much of the audio has been transcribed: 1 means a scanned
       page has something to match against, anything less means it has not. */
    { id: 'kan', tone: 4, seed: 'kaengururebellion', title: 'Die Känguru-Rebellion',
      author: 'Marc-Uwe Kling', narrator: 'Marc-Uwe Kling', formats: ['audio'],
      dur: 13980, pos: 4260, speed: 1, chapters: 66, word: 'Kapitel', prep: 1,
      names: { 1: 'Prolog', 8: 'Der Anschlag', 31: 'Sein und Haben', 66: 'Epilog' } },

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

  /* what a file pick would hand back. Two rows, two files, read metadata. */
  var IMPORTS = {
    audio: {
      label: 'Audiobook', kinds: 'M4B, MP3', file: 'Thinking, Fast and Slow.m4b',
      lines: ['Daniel Kahneman · Patrick Egan', '20h 02m · 38 chapters · M4B'],
      title: 'Thinking, Fast and Slow',
      book: { id: 'tfs', tone: 2, seed: 'kahneman', title: 'Thinking, Fast and Slow',
        author: 'Daniel Kahneman', narrator: 'Patrick Egan', formats: ['audio'],
        dur: 72120, pos: 0, speed: 1, chapters: 38, word: 'Chapter',
        names: { 1: 'The Characters of the Story', 11: 'Anchors', 26: 'Prospect Theory' } }
    },
    ebook: {
      label: 'Ebook', kinds: 'EPUB', file: 'Sea of Tranquility.epub',
      lines: ['Emily St. John Mandel', '272 pages · EPUB'],
      title: 'Sea of Tranquility'
    }
  };

  /* what one scan of a printed page hands back: the text the OCR read, and the
     second in the audio the fuzzy match put it at. The chapter is not stored —
     it is derived from the second, the same way the player derives its own. */
  var SCAN = {
    text: '„Das Känguru schiebt sich die letzte Schnitte in den Mund und erklärt mit ' +
      'vollem Beutel, dass Eigentum Diebstahl sei, meine Schnitte also streng genommen nie ' +
      'mir gehört habe.“',
    at: 6480,
    read: 1400,       /* how long the OCR pass is made to take */
    step: 0.07        /* transcription gained per background tick */
  };

  var SPEEDS = [1, 1.2, 1.5, 1.75, 2];
  var SLEEPS = [15, 30, 60];
  var FILTERS = [
    { k: 'all', l: 'All' },
    { k: 'audio', l: 'Audiobooks' },
    { k: 'ebook', l: 'Ebooks' },
    { k: 'paired', l: 'Paired' },
    { k: 'progress', l: 'In progress' }
  ];

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
  function metaLine(b) {
    var f = formatWord(b), s = state(b);
    if (!hasAudio(b)) {
      if (s === 'new') return f + ' · ' + b.pages + ' pages';
      if (s === 'done') return f + ' · finished';
      return f + ' · page ' + b.page + ' of ' + b.pages;
    }
    if (s === 'new') return f + ' · ' + span(b.dur);
    if (s === 'done') return f + ' · finished';
    return f + ' · ' + span(b.dur - b.pos) + ' left';
  }

  /* ── chapters ───────────────────────────────────────────────────────────── */
  function chapLen(b) { return b.dur / b.chapters; }
  function chapIndex(b) { return Math.max(0, Math.min(b.chapters - 1, Math.floor(b.pos / chapLen(b)))); }
  function chapName(b, i) {
    var n = i + 1;
    return b.word + ' ' + n + (b.names[n] ? ' — ' + b.names[n] : '');
  }

  /* ── notes: kept on the book itself, newest first ───────────────────────── */
  function notes(b) { return b.notes || (b.notes = []); }

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
      book: this.def.book || 'phm',   /* last listened  */
      reading: 'sot',         /* last read      */
      filter: 'all',
      q: '',
      menu: false,
      sleep: null,
      sleepLeft: 0,
      chaps: false,
      playing: false,
      note: false,            /* the capture sheet is up      */
      noteText: '',
      noteResume: false,      /* it was playing when it opened */
      imp: null,              /* the import sheet: null, or { kind, phase } */
      impTimer: null,
      scan: this.def.scan || 'idle',  /* idle · reading · match · nomatch · preparing */
      scanTimer: null
    };
    this.timer = null;
    /* a variant can hand a phone a book that was never transcribed */
    if (this.def.prep != null) this.book(this.st.book).prep = this.def.prep;
    var self = this;
    host.addEventListener('click', function (e) { self.onClick(e); });
    host.addEventListener('input', function (e) { self.onInput(e); });
    host.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && self.st.note) { e.preventDefault(); return self.closeNote(); }
      if (e.key === 'Escape' && self.st.imp) { e.preventDefault(); self.closeImport(); }
    });
    panels.push(this);
    this.paint();
  }

  Phone.prototype.book = function (id) {
    id = id || this.st.book;
    for (var i = 0; i < this.books.length; i++) if (this.books[i].id === id) return this.books[i];
    return this.books[0];
  };

  /* ---- filtering, shared by the library screen --------------------------- */
  Phone.prototype.list = function () {
    var st = this.st, q = st.q.trim().toLowerCase();
    return this.books.filter(function (b) {
      if (q && (b.title + ' ' + b.author).toLowerCase().indexOf(q) < 0) return false;
      if (st.filter === 'audio') return hasAudio(b);
      if (st.filter === 'ebook') return b.formats.indexOf('ebook') > -1;
      if (st.filter === 'paired') return isPaired(b);
      if (st.filter === 'progress') return state(b) === 'on';
      return true;
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
  /* LOCKED rule: capture pauses the book, and gives the playback back on the
     way out — save, cancel and jumping to an older note all take that path. */
  Phone.prototype.openNote = function () {
    var st = this.st;
    if (!hasAudio(this.book())) return;
    st.noteResume = st.playing;
    if (st.playing) this.pause();
    st.note = true;
    st.noteText = '';
    st.chaps = false;
    st.sleepOpen = false;
    this.focusNote = true;
    this.paint();
  };
  Phone.prototype.closeNote = function () {
    var st = this.st;
    st.note = false;
    st.noteText = '';
    if (st.noteResume) { st.noteResume = false; return this.play(); }
    this.paint();
  };
  Phone.prototype.saveNote = function () {
    var t = String(this.st.noteText || '').trim();
    if (!t) return;
    var b = this.book();
    notes(b).unshift({ t: b.pos, text: t });
    this.closeNote();
  };

  /* ---- import: pick a file, read what is in it, then decide -------------
     The sheet is the note sheet's shell and motion. A pick is simulated: the
     hairline fills for the time a read would take, then the metadata stands
     there as plain text, or the title is already here and it says so.      */
  Phone.prototype.openImport = function () {
    this.st.imp = { kind: null, phase: 'menu' };
    this.st.menu = false;
    this.paint();
  };
  Phone.prototype.closeImport = function () {
    if (this.st.impTimer) { clearTimeout(this.st.impTimer); this.st.impTimer = null; }
    this.st.imp = null;
    this.paint();
  };
  Phone.prototype.have = function (title) {
    for (var i = 0; i < this.books.length; i++) if (this.books[i].title === title) return true;
    return false;
  };
  Phone.prototype.pickFile = function (kind) {
    var src = IMPORTS[kind];
    if (!src) return;
    this.st.imp = { kind: kind, phase: 'read' };
    this.paint();
    var self = this, quick = false;
    try { quick = window.matchMedia('(prefers-reduced-motion: reduce)').matches; } catch (e) {}
    this.st.impTimer = setTimeout(function () {
      self.st.impTimer = null;
      self.st.imp = { kind: kind, phase: self.have(src.title) ? 'dupe' : 'meta' };
      self.paint();
    }, quick ? 0 : 1200);
  };
  Phone.prototype.addImport = function () {
    var st = this.st, src = st.imp && IMPORTS[st.imp.kind];
    if (!src || !src.book || this.have(src.title)) return this.closeImport();
    this.books.push(JSON.parse(JSON.stringify(src.book)));
    this.closeImport();
  };

  /* ---- scan: point at a page, read it, propose one second ----------------
     The read has no honest fraction, so it shows none and simply takes the
     time it takes. Transcription does have one — it knows how far through the
     audio it is — so that, and only that, counts out loud.                  */
  Phone.prototype.scanClear = function () {
    if (this.st.scanTimer) { clearTimeout(this.st.scanTimer); clearInterval(this.st.scanTimer); }
    this.st.scanTimer = null;
  };
  Phone.prototype.scanTo = function (phase) {
    this.scanClear();
    this.st.scan = phase;
    this.paint();
  };
  /* both outcomes have to be walkable, so the shots alternate: the first one
     matches, the next one finds nothing. In the app the text decides. */
  Phone.prototype.shoot = function () {
    this.scanTo('reading');
    this.st.shots = (this.st.shots || 0) + 1;
    var out = this.st.shots % 2 ? 'match' : 'nomatch';
    var self = this, quick = false;
    try { quick = window.matchMedia('(prefers-reduced-motion: reduce)').matches; } catch (e) {}
    this.st.scanTimer = setTimeout(function () {
      self.st.scanTimer = null;
      self.scanTo(out);
    }, quick ? 0 : SCAN.read);
  };
  Phone.prototype.jump = function () {
    this.scanClear();
    this.st.scan = 'idle';
    this.st.tab = 'audiobook';
    this.seek(SCAN.at);
  };
  /* transcription runs behind the app, so it keeps counting while you listen */
  Phone.prototype.prepare = function () {
    var b = this.book();
    this.scanClear();
    this.st.scan = 'preparing';
    b.prep = b.prep || 0;
    var self = this;
    this.st.scanTimer = setInterval(function () {
      var bk = self.book();
      bk.prep = Math.min(1, (bk.prep || 0) + SCAN.step);
      if (bk.prep >= 1) { bk.prep = 1; return self.scanTo('idle'); }
      self.paint();
    }, 900);
    this.paint();
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

    if (a === 'tab') { st.tab = arg; return this.paint(); }
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
    if (a === 'note') return this.openNote();
    if (a === 'note-cancel') return this.closeNote();
    if (a === 'note-save') return this.saveNote();
    if (a === 'note-seek') {
      var n = notes(b)[+arg];
      if (n) b.pos = Math.max(0, Math.min(b.dur, n.t));
      return this.closeNote();
    }
    if (a === 'chaps') { st.chaps = !st.chaps; st.sleepOpen = false; return this.paint(); }
    if (a === 'chapter') { st.chaps = false; return this.seek(+arg * chapLen(b)); }
    if (a === 'filter') { st.filter = arg; st.menu = false; return this.paint(); }
    if (a === 'menu') { st.menu = !st.menu; return this.paint(); }
    if (a === 'import') return this.openImport();
    if (a === 'imp-pick') return this.pickFile(arg);
    if (a === 'imp-close') return this.closeImport();
    if (a === 'imp-add') return this.addImport();
    if (a === 'sc-shoot') return this.shoot();
    if (a === 'sc-jump') return this.jump();
    if (a === 'sc-no') return this.scanTo('idle');
    if (a === 'sc-again') return this.scanTo('idle');
    if (a === 'sc-prep') return this.prepare();
  };
  /* search filters without a repaint, so the caret never jumps */
  Phone.prototype.onInput = function (e) {
    if (e.target.matches('textarea[data-note]')) {
      this.st.noteText = e.target.value;
      var save = this.host.querySelector('[data-act="note-save"]');
      if (save) save.disabled = !this.st.noteText.trim();
      return;
    }
    if (!e.target.matches('input[data-search]')) return;
    this.st.q = e.target.value;
    var keep = {};
    this.list().forEach(function (b) { keep[b.id] = 1; });
    var rows = this.host.querySelectorAll('[data-row]');
    Array.prototype.forEach.call(rows, function (r) {
      r.hidden = !keep[r.getAttribute('data-row')];
    });
  };

  /* ---- paint ------------------------------------------------------------- */
  Phone.prototype.paint = function () {
    var st = this.st;
    var scrolls = {};
    Array.prototype.forEach.call(this.host.querySelectorAll('[data-keep]'), function (n) {
      scrolls[n.getAttribute('data-keep')] = n.scrollTop;
    });
    var focused = document.activeElement;
    var refocus = focused && this.host.contains(focused) && focused.matches('input[data-search]');
    var ta = this.host.querySelector('textarea[data-note]');
    var noteSel = null;
    if (ta) {
      this.st.noteText = ta.value;
      if (focused === ta) noteSel = [ta.selectionStart, ta.selectionEnd];
    }

    var body;
    if (st.tab === 'library') body = libraryScreen(this, st);
    else if (st.tab === 'audiobook') body = playerScreen(this, st);
    else if (st.tab === 'reader') body = underConstruction('The reader is not built yet — it arrives with the paired EPUB.');
    else body = scanScreen(this, st);

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
    var area = this.host.querySelector('textarea[data-note]');
    if (area) {
      area.value = st.noteText;
      if (noteSel || this.focusNote) {
        try { area.focus({ preventScroll: true }); } catch (e) { area.focus(); }
        var c = noteSel || [st.noteText.length, st.noteText.length];
        area.setSelectionRange(c[0], c[1]);
      }
    }
    this.focusNote = false;
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

  /* ═══ THE LOCKED SCREENS ════════════════════════════════════════════════
     Library B and Player A are the design. They live here, once, so every tab
     bar in the set leads to the same real screen.                            */

  function searchField() {
    return '<div class="search">' + IC.search +
      '<input type="text" data-search placeholder="Search your books" aria-label="Search your books"></div>';
  }

  /* one row, one progress attribution: a band inside the cover's bottom edge */
  function bookRow(b) {
    var p = pct(b).toFixed(1);
    var on = state(b) !== 'new';
    var cover = '<span class="cover c' + b.tone + '" aria-hidden="true">' + coverHTML(b, 300) +
      (on ? '<span class="inline-p"><i style="width:' + p + '%"></i></span>' : '') + '</span>';
    return '<button type="button" class="book" data-act="book" data-arg="' + b.id +
      '" data-row="' + b.id + '" data-state="' + state(b) + '">' + cover +
      '<span class="book-x">' +
        '<span class="book-t">' + esc(b.title) + '</span>' +
        '<span class="book-a">' + esc(b.author) + '</span>' +
        '<span class="book-f">' + esc(metaLine(b)) + '</span>' +
      '</span></button>';
  }

  function resumeRow(b, label, act) {
    var p = pct(b).toFixed(1), on = state(b) !== 'new';
    var right = hasAudio(b) ? span(b.dur - b.pos) + ' left' : 'page ' + b.page + ' of ' + b.pages;
    var left = hasAudio(b) ? chapName(b, chapIndex(b)) : formatWord(b);
    var cover = '<span class="cover c' + b.tone + '" aria-hidden="true">' + coverHTML(b, 300) +
      (on ? '<span class="inline-p"><i style="width:' + p + '%"></i></span>' : '') + '</span>';
    return '<div class="sect">' + esc(label) + '</div>' +
      '<button type="button" class="now" data-act="' + act + '">' + cover +
      '<span class="now-x"><span class="now-t">' + esc(b.title) + '</span>' +
      '<span class="now-a">' + esc(b.author) + '</span>' +
      '<span class="now-m"><span>' + esc(left) + '</span><span>' + esc(right) + '</span></span></span>' +
      '</button>';
  }

  /* ---- player pieces ----------------------------------------------------- */

  /* the identity group: title, author, chapter. The chapter line is the one
     place the chapter list opens from — there is no second control for it. */
  function identity(b, st) {
    return '<div class="pl-id">' +
      '<div class="pl-t">' + esc(b.title) + '</div>' +
      '<div class="pl-a">' + esc(b.author + (b.narrator ? ' · ' + b.narrator : '')) + '</div>' +
      '<button type="button" class="pl-ch" data-act="chaps" aria-expanded="' +
        (st.chaps ? 'true' : 'false') + '">' + esc(chapName(b, chapIndex(b))) + '</button>' +
      '</div>';
  }

  /* two times, one line: elapsed on the left rail, remaining on the right */
  function scrubber(b) {
    var p = pct(b).toFixed(2);
    return '<div class="timeline" role="slider" tabindex="0" aria-label="Playback position"' +
      ' aria-valuemin="0" aria-valuemax="100" aria-valuenow="' + Math.round(p) + '">' +
      '<span class="tl-track"></span><span class="tl-fill" style="width:' + p + '%"></span>' +
      '<span class="tl-knob" style="left:' + p + '%"></span></div>' +
      '<div class="times"><span>' + hms(b.pos) + '</span>' +
      '<span>−' + hms(b.dur - b.pos) + '</span></div>';
  }

  function transport(st) {
    return '<div class="transport">' +
      '<button type="button" class="skip" data-act="prevch" aria-label="Previous chapter">' + IC.prev + '</button>' +
      '<button type="button" data-act="back15" aria-label="Back 15 seconds">' + IC.back15 + '</button>' +
      '<button type="button" class="play" data-act="play" aria-label="' + (st.playing ? 'Pause' : 'Play') + '">' +
      (st.playing ? IC.pause : IC.play) + '</button>' +
      '<button type="button" data-act="fwd30" aria-label="Forward 30 seconds">' + IC.fwd30 + '</button>' +
      '<button type="button" class="skip" data-act="nextch" aria-label="Next chapter">' + IC.next + '</button>' +
      '</div>';
  }

  /* speed reads as its own value on the left rail; the note key sits on the
     right one, where the thumb already is, with its count as quiet text. */
  function utilRow(b, st) {
    var n = notes(b).length;
    return '<div class="util">' +
      '<button type="button" data-act="speed" aria-label="Playback speed, now ' + b.speed.toFixed(1) + ' times">' +
        '<span class="u-v">' + b.speed.toFixed(1) + '×</span></button>' +
      '<button type="button" class="u-note" data-act="note" aria-label="' +
        (n ? 'Add a note. ' + n + ' saved' : 'Add a note') + '">' +
        (n ? '<span class="n">' + n + '</span>' : '') + IC.pencil + '</button>' +
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

  /* ---- the note sheet ----------------------------------------------------
     Capture without leaving the player: it rises over a dimmed player, takes
     the position it opened at, and hands the playback back on the way out.  */
  function noteSheet(b, st) {
    if (!st.note) return '';
    var list = notes(b);
    var rows = list.map(function (n, i) {
      return '<button type="button" class="note-row" data-act="note-seek" data-arg="' + i + '">' +
        '<span class="note-t">' + hms(n.t) + '</span>' +
        '<span class="note-x">' + esc(n.text) + '</span></button>';
    }).join('');

    return '<div class="sheet-scrim" data-act="note-cancel" aria-hidden="true"></div>' +
      '<div class="sheet" role="dialog" aria-modal="true" aria-label="Note at ' + hms(b.pos) + '">' +
        '<i class="sheet-grab" aria-hidden="true"></i>' +
        '<div class="note-head">' +
          '<span class="note-at">' + IC.pause + hms(b.pos) + '</span>' +
          '<span class="note-ch">' + esc(chapName(b, chapIndex(b))) + '</span>' +
        '</div>' +
        '<textarea class="note-in" data-note rows="3" aria-label="Note text" ' +
          'spellcheck="false" autocapitalize="sentences"></textarea>' +
        '<div class="note-acts">' +
          '<button type="button" class="note-cancel" data-act="note-cancel">Cancel</button>' +
          '<button type="button" class="note-save" data-act="note-save"' +
            (String(st.noteText).trim() ? '' : ' disabled') + '>Save</button>' +
        '</div>' +
        (rows ? '<div class="note-list" data-keep="notes">' + rows + '</div>' : '') +
      '</div>';
  }

  /* ---- the import sheet ---------------------------------------------------
     Same shell, same rise as the note sheet. Four states in one surface: the
     two sources, the read, what the file says, and the title already here.  */
  function importSheet(st) {
    if (!st.imp) return '';
    var im = st.imp, src = IMPORTS[im.kind], body;

    if (im.phase === 'menu') {
      body = '<div class="imp-list">' + ['audio', 'ebook'].map(function (k) {
        var f = IMPORTS[k];
        return '<button type="button" class="imp-row" data-act="imp-pick" data-arg="' + k + '">' +
          '<span class="imp-l">' + esc(f.label) + '</span>' +
          '<span class="imp-k">' + esc(f.kinds) + '</span></button>';
      }).join('') + '</div>';
    } else if (im.phase === 'read') {
      body = '<div class="imp-read"><span class="imp-file">' + esc(src.file) + '</span>' +
        '<span class="imp-bar"><i></i></span></div>';
    } else if (im.phase === 'dupe') {
      body = '<div class="imp-meta"><p class="imp-note">Already in your library</p></div>' +
        '<div class="imp-acts"><span></span>' +
        '<button type="button" class="imp-add" data-act="imp-close">Close</button></div>';
    } else {
      body = '<div class="imp-meta"><p class="imp-t">' + esc(src.title) + '</p>' +
        src.lines.map(function (l) { return '<p class="imp-m">' + esc(l) + '</p>'; }).join('') +
        '</div>' +
        '<div class="imp-acts">' +
        '<button type="button" class="imp-cancel" data-act="imp-close">Cancel</button>' +
        '<button type="button" class="imp-add" data-act="imp-add">Add to library</button></div>';
    }

    /* the sheet rises once, on the way in; the phases after that change the
       contents of a surface that is already standing there */
    var rest = im.phase === 'menu' ? '' : ' sheet--rest';
    return '<div class="sheet-scrim' + rest + '" data-act="imp-close" aria-hidden="true"></div>' +
      '<div class="sheet' + rest + '" role="dialog" aria-modal="true" aria-label="Import">' +
        '<i class="sheet-grab" aria-hidden="true"></i>' +
        body +
      '</div>';
  }

  /* the chapter wheel: the iOS time-picker drum, in the cover's exact box.
     Settling on a row seeks it, so artwork and chapters share one slot. */
  function wheelBox(b) {
    var cur = chapIndex(b), h = '<div class="wheelbox"><div class="wheel" data-keep="wheel" role="listbox" aria-label="Chapters">';
    for (var i = 0; i < b.chapters; i++) {
      h += '<button type="button" role="option" data-act="chapter" data-arg="' + i +
        '" aria-current="' + (i === cur ? 'true' : 'false') + '">' + esc(chapName(b, i)) + '</button>';
    }
    return h + '</div><i class="wheel-sel" aria-hidden="true"></i></div>';
  }

  /* ---- LIBRARY (locked: B) ----------------------------------------------
     The filter is a value beside the title, so the list starts as high as it
     can; progress is a band inside the cover's own bottom edge.             */
  function filterLabel(st) {
    for (var i = 0; i < FILTERS.length; i++) if (FILTERS[i].k === st.filter) return FILTERS[i].l;
    return 'All';
  }
  function libraryScreen(p, st) {
    st.rails = [64];
    var list = p.list();
    return '<div class="screen">' +
      '<div class="titlerow"><span class="h1">Library</span>' +
        '<span class="titlerow__acts">' +
        '<button type="button" class="drop" data-act="menu" aria-expanded="' + (st.menu ? 'true' : 'false') + '">' +
        esc(filterLabel(st)) + IC.caret + '</button>' +
        '<button type="button" class="add" data-act="import" aria-expanded="' + (st.imp ? 'true' : 'false') +
        '" aria-label="Import a book">' + IC.plus + '</button>' +
        '</span></div>' +
      (st.menu
        ? '<div class="menu">' + FILTERS.map(function (f) {
            return '<button type="button" data-act="filter" data-arg="' + f.k + '" aria-pressed="' +
              (st.filter === f.k ? 'true' : 'false') + '">' + f.l +
              (st.filter === f.k ? IC.check : '') + '</button>';
          }).join('') + '</div>'
        : '') +
      searchField() +
      '<div class="scroll" data-keep="list">' +
        resumeRow(p.book(st.book), 'Listening', 'resume') +
        resumeRow(p.book(st.reading), 'Reading', 'resume-read') +
        '<div class="sect">All books</div>' +
        (list.length
          ? list.map(function (b) { return bookRow(b); }).join('')
          : '<p class="empty">Nothing matches this filter.</p>') +
      '</div></div>' + importSheet(st);
  }

  /* ---- PLAYER (locked: A) ------------------------------------------------
     Five groups, top to bottom, separated by the spacing scale:
     top · artwork · identity · scrubber · transport · utilities.            */
  function playerScreen(p, st) {
    st.rails = [];
    var b = p.book();
    var left = st.sleep ? Math.max(1, Math.ceil(st.sleepLeft / 60)) + 'm' : null;
    return '<div class="screen screen--player">' +
      '<div class="pl-top">' +
        '<button type="button" class="pl-back" data-act="back" aria-label="Back to library">' + IC.down + '</button>' +
        '<span class="pl-top__c">' + esc(formatWord(b)) + '</span>' +
        '<button type="button" class="pl-sleep" data-act="sleep" aria-expanded="' +
          (st.sleepOpen ? 'true' : 'false') + '" aria-label="' +
          (left ? 'Sleep timer, ' + left + ' left' : 'Sleep timer') + '">' +
          (left ? '<span class="n">' + left + '</span>' : '') + IC.moon + '</button>' +
      '</div>' +
      sleepPicker(st) +
      (st.chaps
        ? wheelBox(b)
        : '<span class="cover pl-cover c' + b.tone + '" aria-hidden="true">' +
          coverHTML(b, 600) + '<span class="scrim"></span></span>') +
      identity(b, st) +
      '<i class="gap"></i>' +
      scrubber(b) + transport(st) + utilRow(b, st) +
      '</div>' + noteSheet(b, st);
  }

  /* ---- SCAN ---------------------------------------------------------------
     One screen, five phases. The viewfinder holds its box while you point and
     while it reads; only a result takes room from it, and then the frame gives
     way before the text does — the order the player's cover already follows.

       sc-of      what this scan is being matched against
       sc-view    the camera, inset rail to inset rail
       gap        the flexible air
       sc-body    what the phase has to say, or the shutter when it has nothing
       sc-acts    the confirmation, on the rails                             */
  function scanFrame(live) {
    return '<div class="sc-view" data-live="' + (live ? 'true' : 'false') + '" aria-hidden="true">' +
      '<i class="sc-corner tl"></i><i class="sc-corner tr"></i>' +
      '<i class="sc-corner bl"></i><i class="sc-corner br"></i></div>';
  }
  function scanScreen(p, st) {
    st.rails = [];
    var b = p.book(), ph = st.scan, body, acts = '';

    /* a book nobody has transcribed cannot be scanned into, and says so */
    if (ph === 'preparing') {
      var done = Math.round((b.prep || 0) * 100);
      body = '<p class="sc-line">Preparing the transcript</p>' +
        '<span class="sc-bar"><i style="width:' + done + '%"></i></span>' +
        '<p class="sc-prog">' + done + '% · ' + span(b.dur * (b.prep || 0)) + ' of ' + span(b.dur) + '</p>' +
        '<p class="sc-sub">This keeps running while you listen.</p>';
    } else if (b.prep !== 1) {
      body = '<p class="sc-line">A page can only be matched against a transcript, and this book ' +
        'has none yet — Listnr has to listen through the audio once first.</p>';
      acts = '<div class="sc-acts"><span></span>' +
        '<button type="button" class="sc-go" data-act="sc-prep">Prepare this book</button></div>';
    } else if (ph === 'reading') {
      body = '<p class="sc-line">Reading the page…</p>';
    } else if (ph === 'match') {
      var i = Math.max(0, Math.min(b.chapters - 1, Math.floor(SCAN.at / chapLen(b))));
      body = '<p class="sc-quote">' + esc(SCAN.text) + '</p>' +
        '<p class="sc-at">' + hms(SCAN.at) + '</p>' +
        '<p class="sc-ch">' + esc(chapName(b, i)) + '</p>';
      acts = '<div class="sc-acts">' +
        '<button type="button" class="sc-no" data-act="sc-no">Not this one</button>' +
        '<button type="button" class="sc-go" data-act="sc-jump">Jump here</button></div>';
    } else if (ph === 'nomatch') {
      body = '<p class="sc-line">No match in this book</p>' +
        '<p class="sc-sub">Catch a few more lines, or try the facing page.</p>';
      acts = '<div class="sc-acts"><span></span>' +
        '<button type="button" class="sc-go" data-act="sc-again">Try again</button></div>';
    } else {
      body = '<div class="sc-shoot"><button type="button" data-act="sc-shoot" ' +
        'aria-label="Read the page in front of the camera">' + IC.shoot + '</button></div>' +
        '<p class="sc-hint">Point at a page</p>';
    }

    /* the line only claims a match while there is something to match against */
    return '<div class="screen screen--scan">' +
      '<div class="sc-of">' + esc(b.prep === 1 ? 'Matching against ' + b.title : b.title) + '</div>' +
      scanFrame(ph === 'idle' && b.prep === 1) +
      '<i class="gap"></i>' +
      '<div class="sc-body">' + body + '</div>' + acts +
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

  function mountOne(hostId, def) {
    return new Phone(document.getElementById(hostId), def);
  }

  var AB = {
    IC: IC, BOOKS: BOOKS, SPEEDS: SPEEDS, SLEEPS: SLEEPS, FILTERS: FILTERS,
    Phone: Phone, chrome: chrome, mountOne: mountOne,
    esc: esc, hms: hms, span: span, coverHTML: coverHTML, pct: pct, frac: frac, state: state,
    hasAudio: hasAudio, isPaired: isPaired, formatWord: formatWord, metaLine: metaLine,
    chapLen: chapLen, chapIndex: chapIndex, chapName: chapName, wheelBox: wheelBox,
    searchField: searchField, bookRow: bookRow, resumeRow: resumeRow,
    scrubber: scrubber, transport: transport, identity: identity, utilRow: utilRow,
    sleepPicker: sleepPicker, noteSheet: noteSheet, importSheet: importSheet, notes: notes,
    IMPORTS: IMPORTS, SCAN: SCAN, scanFrame: scanFrame,
    underConstruction: underConstruction,
    libraryScreen: libraryScreen, playerScreen: playerScreen, scanScreen: scanScreen
  };
  global.AB = AB;
})(window);
