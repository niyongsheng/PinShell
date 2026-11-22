/*
 * PinShell template i18n helper.
 *
 * Preferred contract (one JSON block per template):
 *
 *   <script type="application/json" id="pinshell:i18n">
 *   {
 *     "default": "zh-Hans",
 *     "fallback": "en",
 *     "languages": {
 *       "zh-Hans": { "meta": { "name": "…", "description": "…" } },
 *       "en": {
 *         "meta": { "name": "…", "description": "…" },
 *         "ui": { "title": "…", "lines": ["…"] }
 *       }
 *     }
 *   }
 *   </script>
 *
 * The default language's UI copy stays inline in the HTML; non-default
 * languages provide `ui`. Missing keys fall back to `fallback` (default en),
 * then to the inline default copy.
 *
 * Static text:      <span data-i18n="add">添加</span>
 * Static attributes: data-i18n-placeholder / -title / -aria-label / -data-text
 * Dynamic text:     PS.t('add', '添加'), PS.t('left', '还剩 {n} 项', { n: 3 })
 * Arrays/data:      PS.list('lines', ['…']), PS.get('seed', [{ … }])
 * Locale:           PS.locale (BCP-47), PS.lang (legacy short form)
 *
 * Language order: ?lang= → window.pinshell.templateLanguage →
 *                 window.pinshell.languages → navigator.languages.
 */
(function () {
  'use strict';

  function normalize(value) {
    return String(value || '').toLowerCase().replace(/_/g, '-');
  }

  function parts(tag) {
    var normalized = normalize(tag);
    if (!normalized) { return null; }
    var pieces = normalized.split('-');
    var language = pieces[0];
    if (!language) { return null; }
    var script = null;
    var region = null;
    for (var i = 1; i < pieces.length; i++) {
      var piece = pieces[i];
      if (!script && piece.length === 4 && /^[a-z]+$/.test(piece)) {
        script = piece;
      } else if (!region
          && ((piece.length === 2 && /^[a-z]+$/.test(piece))
              || (piece.length === 3 && /^[0-9]+$/.test(piece)))) {
        region = piece;
      }
    }
    return { language: language, script: script, region: region, normalized: normalized };
  }

  function impliedScript(tag) {
    if (tag.language === 'zh' && !tag.script) {
      if (tag.region === 'tw' || tag.region === 'hk' || tag.region === 'mo') { return 'hant'; }
      if (tag.region === 'cn' || tag.region === 'sg') { return 'hans'; }
    }
    return tag.script;
  }

  function compatible(candidate, target) {
    if (candidate.language !== target.language) { return false; }
    var a = impliedScript(candidate);
    var b = impliedScript(target);
    return !(a && b && a !== b);
  }

  function score(candidate, target) {
    if (!compatible(candidate, target)) { return -1; }
    if (candidate.normalized === target.normalized) { return 1000; }
    var value = 10;
    var a = impliedScript(candidate);
    var b = impliedScript(target);
    if (a && b && a === b) { value += 20; }
    if (candidate.region && target.region && candidate.region === target.region) { value += 5; }
    return value;
  }

  function pickOne(requested, available) {
    var target = parts(requested);
    if (!target) { return null; }
    var best = null;
    var bestScore = -1;
    for (var i = 0; i < available.length; i++) {
      var candidate = parts(available[i]);
      if (!candidate) { continue; }
      var current = score(candidate, target);
      if (current > bestScore) {
        bestScore = current;
        best = available[i];
      }
    }
    return best;
  }

  function pickFromList(preferred, available) {
    if (!Array.isArray(preferred)) { preferred = [preferred]; }
    for (var i = 0; i < preferred.length; i++) {
      var match = pickOne(preferred[i], available);
      if (match) { return match; }
    }
    return null;
  }

  var override = '';
  try {
    override = new URLSearchParams(window.location.search).get('lang') || '';
  } catch (error) {}

  var block = document.getElementById('pinshell:i18n');
  var data = null;
  if (block) {
    try { data = JSON.parse(block.textContent); } catch (error) {}
  }

  var languages = (data && data.languages) || window.PINSHELL_STRINGS || {};
  var available = Object.keys(languages);
  var defaultLanguage = (data && data.default) || 'zh-Hans';
  var fallbackLanguage = (data && data.fallback)
    || (languages.en ? 'en' : defaultLanguage);

  // 默认语言的正文是 HTML 内联文案，字典里可以没有它。
  if (!available.some(function (tag) {
    return normalize(tag) === normalize(defaultLanguage);
  })) {
    available.push(defaultLanguage);
  }

  var preferred = [];
  if (override) {
    preferred.push(override);
  } else if (window.pinshell) {
    if (window.pinshell.templateLanguage) { preferred.push(window.pinshell.templateLanguage); }
    if (Array.isArray(window.pinshell.languages)) {
      preferred = preferred.concat(window.pinshell.languages);
    } else if (window.pinshell.language) {
      preferred.push(window.pinshell.language);
    }
  }
  if (!preferred.length) {
    preferred = (navigator.languages && navigator.languages.slice())
      || [navigator.language || 'en'];
  }

  var chosen = pickFromList(preferred, available)
    || pickFromList([fallbackLanguage, defaultLanguage], available)
    || available[0]
    || null;
  var chosenTag = chosen || defaultLanguage;
  var chosenParts = parts(chosenTag);
  var defaultParts = parts(defaultLanguage);
  var isDefault = !!(chosenParts && defaultParts && compatible(chosenParts, defaultParts));

  // JSON block entries keep copy under `ui`; legacy PINSHELL_STRINGS
  // dictionaries are flat and have no `meta`/`ui` wrapper.
  function entryDictionary(entry) {
    if (!entry) { return {}; }
    if (entry.ui) { return entry.ui; }
    return data ? {} : entry;
  }

  var dictionary = {};
  if (!isDefault) {
    var fallbackKey = pickFromList([fallbackLanguage], available) || fallbackLanguage;
    Object.assign(dictionary, entryDictionary(languages[fallbackKey]));
  }
  Object.assign(dictionary, entryDictionary(languages[chosen]));

  function get(key, fallbackValue) {
    var value = dictionary[key];
    if (value === undefined || value === null) { return fallbackValue; }
    return value;
  }

  function t(key, fallbackValue, params) {
    var value = dictionary[key];
    if (typeof value !== 'string') { value = fallbackValue; }
    if (typeof value !== 'string') { value = key; }
    if (params) {
      value = value.replace(/\{(\w+)\}/g, function (_, name) {
        return params[name] == null ? '' : String(params[name]);
      });
    }
    return value;
  }

  function list(key, fallbackValue) {
    var value = get(key, fallbackValue);
    return Array.isArray(value) ? value : (fallbackValue || []);
  }

  function apply(root) {
    root = root || document;
    // 一次遍历同时处理文本与属性，避免每个元素扫两遍。
    root.querySelectorAll('*').forEach(function (element) {
      var key = element.getAttribute('data-i18n');
      if (key != null) {
        var text = dictionary[key];
        if (typeof text === 'string') { element.textContent = text; }
      }
      // data-i18n-placeholder / -title / -aria-label / -data-text … → 设置对应属性
      Array.prototype.forEach.call(element.attributes, function (attribute) {
        if (attribute.name.indexOf('data-i18n-') !== 0) { return; }
        var target = attribute.name.slice('data-i18n-'.length);
        if (!target) { return; }
        var value = dictionary[attribute.value];
        if (typeof value === 'string') { element.setAttribute(target, value); }
      });
    });
  }

  var normalizedLocale = normalize(chosenTag);
  var primary = normalizedLocale.split('-')[0] || 'en';
  var rtl = /^(ar|he|fa|ur)(-|$)/.test(normalizedLocale);

  document.documentElement.lang = chosenTag;
  document.documentElement.dir = rtl ? 'rtl' : 'ltr';

  window.PS = {
    lang: primary === 'zh' ? 'zh-Hans' : primary,
    locale: chosenTag,
    languages: available,
    get: get,
    t: t,
    list: list,
    apply: apply
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () { apply(document); });
  } else {
    apply(document);
  }
})();
