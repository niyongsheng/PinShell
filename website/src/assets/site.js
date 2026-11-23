(() => {
  'use strict';

  const root = document.documentElement;
  root.classList.add('js');

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
      if (stage) fit(stage);
    }
  }, true);

  // Gallery search + category filters (progressive enhancement)
  const grid = document.querySelector('[data-gallery-grid]');
  if (grid) {
    const cards = Array.from(grid.querySelectorAll('.template-card'));
    const search = document.querySelector('[data-gallery-search]');
    const chips = Array.from(document.querySelectorAll('[data-category-filter]'));
    const empty = document.querySelector('[data-empty-state]');
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
    };

    chips.forEach((chip) => {
      chip.addEventListener('click', () => {
        chips.forEach((item) => item.classList.toggle('is-active', item === chip));
        category = chip.dataset.categoryFilter || 'all';
        apply();
      });
    });
    if (search) search.addEventListener('input', apply);
    apply();
  }
})();
