// ==UserScript==
// @name         小红书同步到收藏导航
// @namespace    xhs-organizer-file-sync
// @version      3.0.0
// @description  在浏览器里把当前小红书收藏页导出为同步文件，供本地收藏导航 App 自动导入
// @match        https://www.xiaohongshu.com/*
// @grant        none
// ==/UserScript==

(function () {
  'use strict';

  const ROOT_ID = 'xhs-organizer-sync-root';
  const BUTTON_ID = 'xhs-organizer-sync-button';
  const BADGE_ID = 'xhs-organizer-sync-badge';
  const BANNER_ID = 'xhs-organizer-sync-banner';

  function normalize(text) {
    return (text || '').replace(/\s+/g, ' ').trim();
  }

  function unique(items) {
    return Array.from(new Set(items.filter(Boolean)));
  }

  function extractNoteId(value) {
    const text = typeof value === 'string' ? value : '';
    const match = text.match(/\/(?:explore|discovery\/item)\/([^/?#]+)/i) || text.match(/^([0-9a-f]{24,})$/i);
    return match ? match[1] : '';
  }

  function buildTokenMap() {
    const roots = [window.__INITIAL_STATE__, window.__INITIAL_SSR_STATE__, window.__INITIAL_SERVER_STATE__].filter(Boolean);
    const visited = new Set();
    const stack = [...roots];
    const map = new Map();

    while (stack.length) {
      const current = stack.pop();
      if (!current || typeof current !== 'object' || visited.has(current)) continue;
      visited.add(current);

      if (Array.isArray(current)) {
        for (const item of current) stack.push(item);
        continue;
      }

      const noteId = extractNoteId(current.id) || extractNoteId(current.noteId) || extractNoteId(current.note_id);
      const token = typeof current.xsecToken === 'string'
        ? current.xsecToken
        : (typeof current.xsec_token === 'string' ? current.xsec_token : '');

      if (noteId && token && !map.has(noteId)) {
        map.set(noteId, token);
      }

      for (const value of Object.values(current)) {
        if (value && typeof value === 'object') {
          stack.push(value);
        }
      }
    }

    return map;
  }

  function resolveNoteURL(rawHref, tokenMap) {
    const resolved = new URL(rawHref, location.href);
    const noteId = extractNoteId(resolved.pathname);
    if (!noteId) return resolved.href;

    if (!resolved.searchParams.get('xsec_token')) {
      const token = tokenMap.get(noteId);
      if (token) {
        resolved.searchParams.set('xsec_token', token);
        if (!resolved.searchParams.get('xsec_source')) {
          resolved.searchParams.set('xsec_source', 'pc_feed');
        }
      }
    }

    return resolved.href;
  }

  function pickContainer(anchor) {
    let current = anchor;
    const candidates = [];

    for (let depth = 0; current && depth < 8; depth += 1, current = current.parentElement) {
      const text = normalize(current.innerText || '');
      if (!text) continue;
      const linkCount = current.querySelectorAll ? current.querySelectorAll('a[href]').length : 0;
      const imageCount = current.querySelectorAll ? current.querySelectorAll('img').length : 0;
      const score = Math.min(text.length, 900) - Math.max(0, (linkCount - 3) * 60) + imageCount * 10;
      candidates.push({ node: current, score, textLength: text.length });
    }

    candidates.sort((lhs, rhs) => {
      if (lhs.score === rhs.score) return rhs.textLength - lhs.textLength;
      return rhs.score - lhs.score;
    });

    return candidates[0]?.node || anchor;
  }

  function extractNote(anchor) {
    const container = pickContainer(anchor);
    const imageNode = anchor.querySelector('img') || container?.querySelector('img');
    const authorNode = container?.querySelector('[class*="author"], [class*="user"], [class*="name"], [data-testid*="author"]');
    const textCandidates = [];
    const pushText = (value) => {
      const normalized = normalize(value);
      if (normalized) textCandidates.push(normalized);
    };

    pushText(anchor.getAttribute?.('aria-label'));
    pushText(anchor.innerText);
    pushText(container?.getAttribute?.('aria-label'));

    const nodes = container
      ? Array.from(container.querySelectorAll('h1, h2, h3, h4, p, span, div, img[alt], [class*="title"], [class*="desc"], [class*="content"], [class*="note"], [class*="text"]'))
      : [];

    for (const node of nodes) {
      if (node.tagName === 'IMG') {
        pushText(node.getAttribute('alt'));
      } else {
        pushText(node.innerText || node.textContent || '');
      }
    }

    pushText(container?.innerText || '');

    const segments = unique(
      textCandidates
        .flatMap((value) => value.split(/\n+/))
        .map((value) => normalize(value))
        .filter((value) => value.length >= 2)
    );

    const title = (segments.find((value) => value.length >= 4) || normalize(anchor.innerText) || '未命名收藏').slice(0, 120);
    const bodyLines = segments.filter((value) => value !== title);
    const text = bodyLines.join('\n').slice(0, 1800);

    return {
      title,
      text,
      coverImageURL: imageNode?.src || imageNode?.getAttribute('src') || '',
      author: normalize(authorNode?.innerText || '')
    };
  }

  function collectVisibleNotes() {
    const tokenMap = buildTokenMap();
    const anchors = Array.from(document.querySelectorAll('a[href]'));
    const notes = [];
    const seen = new Set();

    for (const anchor of anchors) {
      const rawHref = anchor.getAttribute('href');
      if (!rawHref) continue;

      const href = resolveNoteURL(rawHref, tokenMap);
      if (!(href.includes('/explore/') || href.includes('/discovery/item/') || href.includes('xhslink.com'))) continue;
      if (seen.has(href)) continue;

      const note = extractNote(anchor);
      if (!note.title) continue;

      seen.add(href);
      notes.push({
        url: href,
        title: note.title,
        text: note.text,
        coverImageURL: note.coverImageURL,
        author: note.author
      });
    }

    return notes;
  }

  function showToast(message, isError) {
    console[isError ? 'error' : 'log']('[XHS Organizer]', message);
    const toast = document.createElement('div');
    toast.textContent = message;
    toast.style.cssText = `
      position: fixed;
      right: 24px;
      bottom: 24px;
      z-index: 999999;
      background: ${isError ? '#b42318' : '#111827'};
      color: white;
      padding: 12px 16px;
      border-radius: 12px;
      font-size: 14px;
      box-shadow: 0 12px 24px rgba(0,0,0,0.18);
    `;
    document.body.appendChild(toast);
    setTimeout(() => toast.remove(), 2600);
  }

  function ensureBanner() {
    if (!document.body) return false;
    let banner = document.getElementById(BANNER_ID);
    if (!banner) {
      banner = document.createElement('div');
      banner.id = BANNER_ID;
      banner.style.cssText = `
        position: fixed;
        left: 50%;
        top: 18px;
        transform: translateX(-50%);
        z-index: 2147483647;
        background: rgba(17,24,39,0.94);
        color: white;
        border-radius: 999px;
        padding: 10px 16px;
        font-size: 13px;
        font-weight: 700;
        box-shadow: 0 12px 28px rgba(0,0,0,0.22);
        pointer-events: none;
      `;
      document.body.appendChild(banner);
    }
    return true;
  }

  function updateBanner(text) {
    if (!ensureBanner()) return;
    const banner = document.getElementById(BANNER_ID);
    if (!banner) return;
    banner.textContent = text;
  }

  function ensureMount() {
    if (!document.body) return false;
    let root = document.getElementById(ROOT_ID);
    if (!root) {
      root = document.createElement('div');
      root.id = ROOT_ID;
      root.style.cssText = `
        position: fixed;
        right: 24px;
        top: 120px;
        z-index: 2147483647;
        display: flex;
        flex-direction: column;
        align-items: flex-end;
        gap: 10px;
        pointer-events: none;
      `;
      document.body.appendChild(root);
    }

    let badge = document.getElementById(BADGE_ID);
    if (!badge) {
      badge = document.createElement('div');
      badge.id = BADGE_ID;
      badge.textContent = '收藏导航脚本已加载';
      badge.style.cssText = `
        pointer-events: auto;
        background: rgba(17,24,39,0.92);
        color: white;
        border-radius: 999px;
        padding: 8px 14px;
        font-size: 13px;
        font-weight: 600;
        box-shadow: 0 10px 20px rgba(0,0,0,0.18);
      `;
      root.appendChild(badge);
    }

    return true;
  }

  function exportNow() {
    const notes = collectVisibleNotes();
    if (!notes.length) {
      updateBanner('脚本已加载，但当前页面没有识别到收藏卡片');
      showToast('当前页面没有识别到可同步的笔记卡片', true);
      return;
    }

    const payload = {
      source: 'tampermonkey-file-sync',
      pageURL: location.href,
      pageTitle: document.title,
      exportedAt: new Date().toISOString(),
      notes
    };

    const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = `xhs-organizer-sync-${Date.now()}.json`;
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);

    updateBanner(`已导出 ${notes.length} 条，回到 App 等待自动导入`);
    showToast(`已导出 ${notes.length} 条到下载文件夹，回到 App 等待自动导入`, false);
  }

  function ensureButton() {
    if (!ensureMount()) return;
    if (document.getElementById(BUTTON_ID)) return;
    const root = document.getElementById(ROOT_ID);
    if (!root) return;

    const button = document.createElement('button');
    button.id = BUTTON_ID;
    button.textContent = '同步到收藏导航';
    button.style.cssText = `
      pointer-events: auto;
      background: #ef4444;
      color: white;
      border: none;
      border-radius: 999px;
      padding: 13px 18px;
      font-size: 14px;
      font-weight: 700;
      cursor: pointer;
      box-shadow: 0 12px 20px rgba(239,68,68,0.28);
    `;
    button.addEventListener('click', exportNow);
    root.appendChild(button);
  }

  function boot() {
    console.log('[XHS Organizer] userscript boot');
    ensureButton();
    updateBanner('收藏导航脚本已加载，右侧可点“同步到收藏导航”');
    showToast('收藏导航脚本已加载', false);
  }

  const observer = new MutationObserver(() => ensureButton());
  observer.observe(document.documentElement, { childList: true, subtree: true });
  const interval = setInterval(() => ensureButton(), 1500);
  window.addEventListener('beforeunload', () => clearInterval(interval), { once: true });

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot, { once: true });
  } else {
    boot();
  }
})();
