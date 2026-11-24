(() => {
  'use strict';

  const root = document.documentElement;
  root.classList.add('js');

  // Theme: follow the system until the visitor makes an explicit choice.
  const themeKey = 'pinshell-site-theme';
  const themeMeta = document.querySelector('meta[name="theme-color"]');
  const themeButtons = Array.from(document.querySelectorAll('[data-theme-toggle]'));
  const systemDark = window.matchMedia('(prefers-color-scheme: dark)');

  const storedTheme = () => {
    try {
      const value = localStorage.getItem(themeKey);
      return value === 'light' || value === 'dark' ? value : null;
    } catch (error) {
      return null;
    }
  };

  const applyTheme = (theme) => {
    const isDark = theme === 'dark';
    root.setAttribute('data-theme', theme);
    root.style.colorScheme = theme;
    if (themeMeta) themeMeta.setAttribute('content', isDark ? '#000000' : '#f5f5f7');
    themeButtons.forEach((button) => {
      button.setAttribute('aria-pressed', String(isDark));
      const label = isDark ? button.dataset.labelLight : button.dataset.labelDark;
      if (label) {
        button.setAttribute('aria-label', label);
        button.setAttribute('title', label);
      }
    });
  };

  const currentTheme = root.getAttribute('data-theme');
  applyTheme(currentTheme === 'dark' || currentTheme === 'light'
    ? currentTheme
    : (systemDark.matches ? 'dark' : 'light'));

  themeButtons.forEach((button) => {
    button.addEventListener('click', () => {
      const next = root.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
      applyTheme(next);
      try {
        localStorage.setItem(themeKey, next);
      } catch (error) {}
    });
  });

  const onSystemThemeChange = (event) => {
    if (!storedTheme()) applyTheme(event.matches ? 'dark' : 'light');
  };
  if (typeof systemDark.addEventListener === 'function') {
    systemDark.addEventListener('change', onSystemThemeChange);
  } else if (typeof systemDark.addListener === 'function') {
    systemDark.addListener(onSystemThemeChange);
  }

  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const connection = navigator.connection || navigator.mozConnection || navigator.webkitConnection;
  const saveData = Boolean(connection && connection.saveData);
  const noLivePreview = reduceMotion || saveData;

  // Sticky navigation state
  const nav = document.querySelector('[data-site-nav]');
  const updateNav = () => {
    if (nav) nav.classList.toggle('is-scrolled', window.scrollY > 8);
  };
  updateNav();
  window.addEventListener('scroll', updateNav, { passive: true });

  // Quiet reveal motion
  const reveals = Array.from(document.querySelectorAll('[data-reveal]'));
  if (!reduceMotion && 'IntersectionObserver' in window) {
    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible');
          observer.unobserve(entry.target);
        }
      });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.12 });
    reveals.forEach((element) => observer.observe(element));
  } else {
    reveals.forEach((element) => element.classList.add('is-visible'));
  }
  // Safety net: never leave content invisible if the observer never fires.
  window.setTimeout(() => {
    reveals.forEach((element) => element.classList.add('is-visible'));
  }, 2600);

  // Live template previews
  const stages = Array.from(document.querySelectorAll('.preview-stage[data-src]'));

  const fit = (stage) => {
    const iframe = stage.querySelector('iframe');
    if (!iframe) return;
    const width = Number(stage.dataset.w) || 320;
    const height = Number(stage.dataset.h) || 200;
    // 预览与舞台边缘留出内边距，避免网页窗口贴边
    const pad = parseFloat(getComputedStyle(stage).getPropertyValue('--preview-pad')) || 0;
    const boxWidth = Math.max(0, stage.clientWidth - pad * 2);
    const boxHeight = Math.max(0, stage.clientHeight - pad * 2);
    if (!boxWidth || !boxHeight) return;
    const scale = Math.min(boxWidth / width, boxHeight / height, 1.6);
    iframe.style.width = `${width}px`;
    iframe.style.height = `${height}px`;
    iframe.style.transform = `translate(-50%, -50%) scale(${scale})`;
  };

  // 模板的圆角和投影画在窗口内部（面板铺满视口）。预览 iframe 的视口是直角
  // 矩形，铺满面板的外投影会被裁成方形，在四角留下「双圆角」痕迹。
  // 把生成器已解析的模板窗口圆角套到 iframe 上，让裁切边界和面板圆角重合。
  const applyWindowShape = (stage) => {
    const iframe = stage.querySelector('iframe');
    if (!iframe) return;
    const radius = Number(stage.dataset.radius) || 0;
    if (!(radius > 0)) {
      iframe.style.borderRadius = '';
      iframe.classList.remove('is-rounded');
      return;
    }
    iframe.style.borderRadius = `${radius}px`;
    iframe.classList.add('is-rounded');
  };

  const previewTitle = (stage) => {
    const card = stage.closest('.template-card');
    const detail = stage.closest('.detail');
    const name = card?.querySelector('h3')?.textContent
      || detail?.querySelector('h1')?.textContent
      || stage.dataset.title
      || 'PinShell template preview';
    return `${name} — PinShell preview`;
  };

  const loadPreview = (stage) => {
    if (noLivePreview) {
      stage.classList.add('is-poster-only');
      return;
    }
    if (stage.querySelector('iframe')) return;
    const iframe = document.createElement('iframe');
    iframe.src = stage.dataset.src;
    iframe.title = previewTitle(stage);
    iframe.loading = 'lazy';
    iframe.setAttribute('scrolling', 'no');
    iframe.setAttribute('allow', "autoplay 'none'; camera 'none'; microphone 'none'; geolocation 'none'");
    if (stage.dataset.interactive === 'true') {
      iframe.setAttribute('tabindex', '0');
    } else {
      iframe.setAttribute('tabindex', '-1');
      iframe.setAttribute('aria-hidden', 'true');
    }
    stage.appendChild(iframe);
    stage.classList.add('is-live');
    fit(stage);
  };

  if (noLivePreview) {
    stages.forEach((stage) => stage.classList.add('is-poster-only'));
  } else if ('IntersectionObserver' in window) {
    const previewObserver = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          loadPreview(entry.target);
          previewObserver.unobserve(entry.target);
        }
      });
    }, { rootMargin: '260px 0px' });
    stages.forEach((stage) => {
      if (stage.dataset.eager === 'true' || stage.dataset.interactive === 'true') {
        loadPreview(stage);
      } else {
        previewObserver.observe(stage);
      }
    });
  } else {
    stages.forEach(loadPreview);
  }

  window.addEventListener('resize', () => stages.forEach(fit), { passive: true });
  document.addEventListener('load', (event) => {
    if (event.target && event.target.tagName === 'IFRAME') {
      const stage = event.target.closest('.preview-stage');
      if (stage) {
        applyWindowShape(stage);
        fit(stage);
      }
    }
  }, true);

  // Gallery search + category filters (progressive enhancement)
  const grid = document.querySelector('[data-gallery-grid]');
  if (grid) {
    const cards = Array.from(grid.querySelectorAll('.template-card'));
    const search = document.querySelector('[data-gallery-search]');
    const chips = Array.from(document.querySelectorAll('[data-category-filter]'));
    const empty = document.querySelector('[data-empty-state]');
    const meta = document.querySelector('[data-gallery-meta]');
    const count = meta?.querySelector('[data-gallery-count]');
    let category = 'all';

    const apply = () => {
      const query = (search?.value || '').trim().toLowerCase();
      let visible = 0;
      cards.forEach((card) => {
        const categoryMatch = category === 'all' || card.dataset.category === category;
        const queryMatch = !query || (card.dataset.search || '').includes(query);
        const show = categoryMatch && queryMatch;
        card.hidden = !show;
        if (show) visible += 1;
      });
      if (empty) empty.hidden = visible !== 0;
      if (meta && count) {
        const template = visible === 1 ? meta.dataset.countOne : meta.dataset.countOther;
        if (template) {
          const next = template.replace('{n}', String(visible));
          if (count.textContent !== next) count.textContent = next;
        }
      }
    };

    const selectCategory = (chip) => {
      chips.forEach((item) => {
        const active = item === chip;
        item.classList.toggle('is-active', active);
        item.setAttribute('aria-pressed', String(active));
      });
      category = chip.dataset.categoryFilter || 'all';
      apply();
    };

    chips.forEach((chip) => {
      chip.addEventListener('click', () => selectCategory(chip));
    });
    if (search) {
      search.addEventListener('input', apply);
      search.addEventListener('search', apply);
      search.addEventListener('keydown', (event) => {
        if (event.key === 'Escape' && search.value) {
          search.value = '';
          apply();
        }
      });
    }
    apply();
  }
})();
