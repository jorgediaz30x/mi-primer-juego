// Pestaña Imágenes: tarjetas agrupadas por categoría y el panel de detalle
// (vista previa ampliada, animación, prompt, datos y versiones anteriores).

import { $, h, esc, ui, api, toast, confirmDialog, runJob, job, matchesSearch, setBackground, loadImage, filterButton, deleteEntry } from './shared.js';

const ZOOMS = [1, 2, 3, 4, 6, 8];
const filters = { category: 'todas', status: 'todos' };
let data = { items: [], categories: [] };
let detail = null;          // { item, mode, zoom, compare, player }

// --- Datos --------------------------------------------------------------------

export async function load() {
  data = await api('/api/images');
  data.items ??= [];
  $('#count-imagenes').textContent = data.items.length;
  render();
  if (detail) {
    const fresh = data.items.find(i => i.id === detail.item.id);
    if (fresh) openDetail(fresh.id, { keepMode: true });
  }
}

const byId = id => data.items.find(item => item.id === id);
const categoryLabel = id => (data.categories.find(c => c.id === id) || {}).label || id;

// --- Lista --------------------------------------------------------------------

export function render() {
  renderFilters();
  const root = $('#image-groups');
  root.innerHTML = '';
  $('#image-manifest').innerHTML = data.manifest ? `Manifiesto: <code>${esc(data.manifest)}</code>` : '';

  if (data.error) root.append(h(`<div class="banner error">${esc(data.error)}</div>`));
  if (data.key_configured === false) {
    root.append(h(`<div class="banner">No encontré <b>OPENAI_API_KEY</b> en <code>.env.local</code> ni en el entorno.
      Puedes mirar todo, pero para generar necesitas la clave.</div>`));
  }
  const visible = data.items.filter(item =>
    (filters.category === 'todas' || item.category === filters.category) &&
    (filters.status === 'todos' || item.status === filters.status) &&
    matchesSearch(item, ui.search));

  if (!data.items.length) {
    root.append(h(`<div class="empty"><strong>El manifiesto no tiene imágenes todavía</strong>
      Agrega entradas a <code>tools/art/asset_manifest.json</code> y recarga la página.</div>`));
    return;
  }
  if (!visible.length) {
    root.append(h(`<div class="empty"><strong>Nada coincide con los filtros</strong>
      ${ui.search ? `Prueba con otra búsqueda que no sea "${esc(ui.search)}".` : 'Cambia la categoría o el estado.'}</div>`));
    return;
  }
  for (const category of data.categories) {
    const items = visible.filter(item => item.category === category.id);
    if (!items.length) continue;
    const missing = items.filter(i => i.status === 'missing').length;
    const group = h(`<section class="group">
      <div class="group-head"><h2>${esc(category.label)}</h2><span class="count">${items.length}</span>
      ${missing ? `<span class="hint">${missing} sin generar</span>` : ''}</div>
      <div class="grid"></div></section>`);
    const grid = $('.grid', group);
    items.forEach(item => grid.append(card(item)));
    root.append(group);
  }
}

function renderFilters() {
  const counts = { todas: data.items.length };
  data.items.forEach(item => { counts[item.category] = (counts[item.category] || 0) + 1; });
  const categories = [{ id: 'todas', label: 'Todas' }, ...data.categories];
  $('#image-categories').replaceChildren(...categories.map(c =>
    filterButton(c.label, counts[c.id] || 0, filters.category === c.id, () => { filters.category = c.id; render(); })));

  const ok = data.items.filter(i => i.status === 'ok').length;
  const statuses = [['todos', 'Todos', data.items.length], ['ok', 'Generados', ok], ['missing', 'Sin generar', data.items.length - ok]];
  $('#image-status').replaceChildren(...statuses.map(([id, label, n]) =>
    filterButton(label, n, filters.status === id, () => { filters.status = id; render(); })));

  document.querySelectorAll('#bg-switch button').forEach(button => {
    button.classList.toggle('active', button.dataset.bg === ui.bg);
    button.onclick = () => { setBackground(button.dataset.bg); render(); if (detail) renderDetail(); };
  });
}

function card(item) {
  const frames = item.frames.length;
  const meta = [item.kind_label];
  if (item.kind === 'sheet') meta.push(`${item.columns * item.rows} fotogramas`, `${item.fps} fps`);
  const element = h(`<button class="card" data-id="${esc(item.id)}">
    <div class="thumb ${item.status === 'missing' ? 'missing' : `bg-${ui.bg}`}"></div>
    <div class="card-body">
      <div class="card-top"><span class="card-id">${esc(item.id)}</span>
        ${item.frame_size ? `<span class="card-size">${item.frame_size[0]}x${item.frame_size[1]}</span>` : ''}</div>
      <div class="card-meta">${meta.map(esc).join('<span class="dot">/</span>')}</div>
    </div></button>`);
  const thumb = $('.thumb', element);
  if (item.status === 'missing') {
    thumb.append(h('<span class="chip missing">Sin generar</span>'));
    const generate = h('<span class="btn small primary" role="button" style="position:absolute;bottom:10px">Generar</span>');
    generate.addEventListener('click', event => { event.stopPropagation(); generateItem(item); });
    thumb.append(generate);
  } else {
    const source = frames ? item.frames[0] : item.raw.url;
    const img = h(`<img class="pixel" alt="${esc(item.id)}" src="${esc(source)}">`);
    img.addEventListener('load', () => fitThumb(img, thumb, !frames), { once: true });
    thumb.append(img);
    if (!frames) thumb.append(h('<span class="scale" style="left:6px;right:auto">solo original</span>'));
    if (frames > 1) animateThumb(img, item.frames, item.fps);
  }
  element.addEventListener('click', () => { location.hash = `#imagenes/${item.id}`; });
  return element;
}

/** Zoom ENTERO si cabe (pixel art nítido); si la imagen es más grande que la tarjeta, se reduce. */
function fitThumb(img, box, isRaw) {
  if (!box.clientWidth) return;                   // pestaña oculta: se ajusta al volver a mostrarla
  const w = img.naturalWidth, h2 = img.naturalHeight;
  const fit = Math.min((box.clientWidth - 20) / w, (box.clientHeight - 20) / h2);
  const scale = fit >= 1 ? Math.floor(fit) : fit;
  img.style.width = `${Math.round(w * scale)}px`;
  img.style.height = `${Math.round(h2 * scale)}px`;
  if (isRaw) img.classList.remove('pixel');      // el original es grande: reducirlo suave se ve mejor
  const label = scale >= 1 ? `${scale}x` : `${Math.round(scale * 100)}%`;
  box.append(h(`<span class="scale">${label}</span>`));
}

// Las tarjetas de animación se mueven solas, a los fps del manifiesto.
let thumbs = [];
function animateThumb(img, frames, fps) {
  thumbs.push({ img, frames, fps, index: 0 });
}
function tickThumbs(now) {
  thumbs = thumbs.filter(t => t.img.isConnected);
  if (!$('#tab-imagenes').hidden) {
    for (const t of thumbs) {
      const index = Math.floor(now / 1000 * t.fps) % t.frames.length;
      if (index !== t.index) { t.index = index; t.img.src = t.frames[index]; }
    }
  }
  requestAnimationFrame(tickThumbs);
}
requestAnimationFrame(tickThumbs);

// --- Reproductor de animaciones ------------------------------------------------
// Un reloj compartido mueve una o varias "vistas" (el juego, el original cortado
// por su rejilla, o dos versiones lado a lado) en el mismo fotograma.

class Player {
  constructor(onFrame) {
    this.views = []; this.frame = 0; this.count = 1; this.fps = 10; this.playing = true;
    this.onFrame = onFrame; this.last = 0; this.elapsed = 0;
    this.loop = this.loop.bind(this);
    this.raf = requestAnimationFrame(this.loop);
  }
  setViews(views) {
    this.views = views;
    this.count = Math.max(1, ...views.map(v => v.count));
    this.frame = Math.min(this.frame, this.count - 1);
    this.draw();
  }
  loop(now) {
    const dt = this.last ? now - this.last : 0;
    this.last = now;
    if (this.playing && this.count > 1) {
      this.elapsed += dt;
      const step = 1000 / this.fps;
      if (this.elapsed >= step) {
        this.elapsed %= step;
        this.frame = (this.frame + 1) % this.count;
        this.draw();
      }
    }
    this.raf = requestAnimationFrame(this.loop);
  }
  go(frame) { this.frame = (frame + this.count) % this.count; this.draw(); }
  draw() { this.views.forEach(v => v.draw(this.frame)); this.onFrame?.(this.frame, this.count); }
  destroy() { cancelAnimationFrame(this.raf); }
}

/** Los PNG del juego (ya en pixel real), ampliados a un zoom entero y sin suavizado. */
function framesView(images, scale) {
  const w = Math.max(...images.map(i => i.naturalWidth)), hh = Math.max(...images.map(i => i.naturalHeight));
  const canvas = document.createElement('canvas');
  canvas.width = w * scale; canvas.height = hh * scale;
  const ctx = canvas.getContext('2d');
  return {
    canvas, count: images.length,
    draw(frame) {
      const img = images[frame % images.length];
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      ctx.imageSmoothingEnabled = false;
      // Alineado abajo al centro, como en el juego (el ancla está en los pies).
      const dw = img.naturalWidth * scale, dh = img.naturalHeight * scale;
      ctx.drawImage(img, Math.round((canvas.width - dw) / 2), canvas.height - dh, dw, dh);
    },
  };
}

/** Un fotograma de la hoja original: la misma rejilla que usa sprite_ops.slice_grid (celda = ancho // columnas). */
function cellView(img, columns, rows, maxW, maxH) {
  const cellW = Math.floor(img.naturalWidth / columns), cellH = Math.floor(img.naturalHeight / rows);
  const scale = Math.min(maxW / cellW, maxH / cellH, 1);
  const canvas = document.createElement('canvas');
  canvas.width = Math.round(cellW * scale); canvas.height = Math.round(cellH * scale);
  const ctx = canvas.getContext('2d');
  return {
    canvas, count: columns * rows,
    draw(frame) {
      const f = frame % (columns * rows);
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      ctx.imageSmoothingEnabled = true;
      ctx.drawImage(img, (f % columns) * cellW, Math.floor(f / columns) * cellH, cellW, cellH, 0, 0, canvas.width, canvas.height);
    },
  };
}

/** La hoja original entera, con su rejilla dibujada y la celda actual resaltada. */
function sheetView(img, columns, rows, maxW, maxH, showGrid) {
  const scale = Math.min(maxW / img.naturalWidth, maxH / img.naturalHeight, 1);
  const canvas = document.createElement('canvas');
  canvas.width = Math.round(img.naturalWidth * scale); canvas.height = Math.round(img.naturalHeight * scale);
  const ctx = canvas.getContext('2d');
  const cw = canvas.width / columns, ch = canvas.height / rows;
  return {
    canvas, count: showGrid ? columns * rows : 1,
    draw(frame) {
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      ctx.imageSmoothingEnabled = true;
      ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
      if (!showGrid) return;
      ctx.strokeStyle = 'rgba(240, 182, 90, 0.35)';
      ctx.lineWidth = 1;
      for (let c = 1; c < columns; c++) { ctx.beginPath(); ctx.moveTo(Math.round(c * cw) + 0.5, 0); ctx.lineTo(Math.round(c * cw) + 0.5, canvas.height); ctx.stroke(); }
      for (let r = 1; r < rows; r++) { ctx.beginPath(); ctx.moveTo(0, Math.round(r * ch) + 0.5); ctx.lineTo(canvas.width, Math.round(r * ch) + 0.5); ctx.stroke(); }
      const f = frame % (columns * rows);
      ctx.strokeStyle = '#f0b65a'; ctx.lineWidth = 2;
      ctx.strokeRect((f % columns) * cw + 1, Math.floor(f / columns) * ch + 1, cw - 2, ch - 2);
    },
  };
}

// --- Panel de detalle --------------------------------------------------------------

export function openDetail(id, { keepMode = false } = {}) {
  const item = byId(id);
  if (!item) { closeDetail(); return; }
  const previous = detail;
  detail?.player?.destroy();
  detail = {
    item,
    mode: keepMode && previous ? previous.mode : (item.frames.length ? 'juego' : 'original'),
    zoom: keepMode && previous ? previous.zoom : 'fit',
    compare: keepMode && previous ? previous.compare : null,
    fps: keepMode && previous ? previous.fps : item.fps,
    draft: keepMode && previous ? previous.draft : null,
    player: null,
  };
  if (detail.compare && !item.history.some(v => v.name === detail.compare)) detail.compare = null;
  if (detail.mode === 'comparar' && !detail.compare) detail.mode = item.frames.length ? 'juego' : 'original';
  $('#detail').hidden = false;
  $('#detail-backdrop').hidden = false;
  renderDetail();
}

export function closeDetail() {
  detail?.player?.destroy();
  detail = null;
  $('#detail').hidden = true;
  $('#detail-backdrop').hidden = true;
  if (location.hash.startsWith('#imagenes/')) history.replaceState(null, '', '#imagenes');
}

function renderDetail() {
  const d = detail, item = d.item;
  d.player?.destroy();
  const isSheet = item.kind === 'sheet';
  const panel = $('#detail');
  const hasHistory = item.history.length > 0;
  panel.innerHTML = `
    <header class="detail-head">
      <h2>${esc(item.id)}</h2>
      <span class="chip">${esc(item.kind_label)}</span>
      <span class="chip ${item.status}">${item.status === 'ok' ? 'Generado' : 'Sin generar'}</span>
      <span class="spacer"></span>
      <button class="btn ghost small" data-act="close">Cerrar</button>
    </header>
    <div class="detail-scroll">
      ${item.status === 'missing' ? '' : `
      <div class="toolbar">
        <span class="label">Vista</span>
        <div class="segmented" style="width:290px">
          <button data-mode="juego" ${item.frames.length ? '' : 'disabled'}>En el juego</button>
          <button data-mode="original" ${item.raw ? '' : 'disabled'}>Original</button>
          <button data-mode="comparar" ${hasHistory && item.raw ? '' : 'disabled'}>Comparar</button>
        </div>
        <span class="spacer"></span>
        ${d.mode === 'juego' ? `<span class="label">Zoom</span>
          <button class="btn small" data-zoom="fit">Ajustar</button>
          ${ZOOMS.map(z => `<button class="btn small" data-zoom="${z}">${z}x</button>`).join('')}` : ''}
      </div>
      <div class="stage bg-${ui.bg}" id="stage"></div>
      <div class="stage-caption" id="caption"></div>
      <div class="anim-controls" id="anim"></div>
      <div class="strip" id="strip"></div>`}
      ${item.status === 'missing' ? `<div class="empty"><strong>Esta imagen aún no existe</strong>
        Revisa el prompt y pulsa Generar. Se guarda en <code>${esc(item.out_path)}</code>.</div>` : ''}
      <div>
        <h3 class="section-title">Prompt</h3>
        <textarea class="prompt" id="prompt" spellcheck="false"></textarea>
        <div class="prompt-actions">
          <button class="btn primary" data-act="generate">${item.status === 'ok' ? 'Regenerar' : 'Generar'}</button>
          <button class="btn" data-act="save" disabled>Guardar prompt</button>
          <button class="btn" data-act="dry">Ver prompt final</button>
          ${item.status === 'missing' ? '<button class="btn danger" data-act="delete">Eliminar entrada</button>' : ''}
          <span class="note" id="prompt-note"></span>
        </div>
        <p class="note">Generar llama a OpenAI y gasta créditos. "Ver prompt final" es gratis: muestra el texto completo
          (estilo común + reglas de hoja + tu prompt) tal como está guardado en el manifiesto.</p>
      </div>
      <div>
        <h3 class="section-title">Datos</h3>
        <dl class="facts">${facts(item)}</dl>
      </div>
      <div>
        <h3 class="section-title">Versiones anteriores (${item.history.length})</h3>
        ${hasHistory ? `<div class="versions" id="versions"></div>
          <div class="prompt-actions" id="version-actions"></div>`
          : '<p class="note">Todavía no hay versiones anteriores. Cada vez que regeneras, la actual pasa a <code>assets/art/_history/</code>.</p>'}
      </div>
    </div>`;

  // Prompt: el borrador sobrevive a los refrescos mientras no lo guardes.
  const textarea = $('#prompt', panel);
  textarea.value = d.draft ?? item.prompt;
  const syncDirty = () => {
    const dirty = textarea.value.trim() !== item.prompt.trim();
    d.draft = dirty ? textarea.value : null;
    $('[data-act=save]', panel).disabled = !dirty;
    $('#prompt-note', panel).textContent = dirty ? 'Cambios sin guardar ("Ver prompt final" muestra la versión guardada).' : '';
    $('#prompt-note', panel).className = dirty ? 'note warn' : 'note';
  };
  textarea.addEventListener('input', syncDirty);
  syncDirty();

  panel.querySelectorAll('[data-mode]').forEach(b => {
    b.classList.toggle('active', b.dataset.mode === d.mode);
    b.onclick = () => {
      d.mode = b.dataset.mode;
      if (d.mode === 'comparar' && !d.compare) d.compare = item.history[0].name;
      renderDetail();
    };
  });
  panel.querySelectorAll('[data-zoom]').forEach(b => {
    b.classList.toggle('active', String(d.zoom) === b.dataset.zoom);
    b.onclick = () => { d.zoom = b.dataset.zoom === 'fit' ? 'fit' : Number(b.dataset.zoom); renderDetail(); };
  });
  $('[data-act=close]', panel).onclick = closeDetail;
  $('[data-act=save]', panel).onclick = () => savePrompt(item, textarea.value);
  $('[data-act=dry]', panel).onclick = () => runJob({ kind: 'image', id: item.id, dryRun: true });
  $('[data-act=generate]', panel).onclick = () => generateItem(item, textarea.value);
  $('[data-act=delete]', panel)?.addEventListener('click', async () => {
    if (await deleteEntry('image', item.id)) { closeDetail(); await load(); }
  });

  if (hasHistory) renderVersions(panel);
  if (item.status !== 'missing') renderStage(isSheet);
}

function facts(item) {
  // Cada valor ya es HTML seguro: el texto que viene de datos pasa por esc().
  const mono = text => `<span class="mono">${esc(text)}</span>`;
  const rows = [['Tipo', `${esc(item.kind_label)} (${esc(item.kind)})`], ['Categoría', esc(categoryLabel(item.category))]];
  if (item.frame_size) {
    const n = item.frames.length;
    rows.push(['Tamaño real', `${item.frame_size[0]} x ${item.frame_size[1]} px${n > 1 ? ` por fotograma, ${n} fotogramas` : ''}`]);
  }
  rows.push(['Alto en pixel art', `${esc(item.pixel_height ?? '-')} px`]);
  if (item.kind === 'sheet') {
    rows.push(['Rejilla', `${item.columns} columnas x ${item.rows} filas`]);
    rows.push(['Velocidad', `${esc(item.fps)} fps, ${item.loop ? 'se repite' : 'se reproduce una vez'}`]);
  }
  rows.push(['Archivo del juego', mono(item.out_path)]);
  if (item.raw) rows.push(['Original', `${mono(item.raw.path)} (${item.raw.size.join(' x ')} px)`]);
  rows.push(['Modelo', mono(item.model)]);
  rows.push(['Pedido', `${esc(item.size)}, calidad ${esc(item.quality)}, fondo ${esc(item.background)}`]);
  if (item.reference.length) {
    rows.push(['Referencias', item.reference.map(r =>
      mono(r) + (byId(r)?.status === 'missing' ? ' (sin generar)' : '')).join(', ')]);
  }
  return rows.map(([key, value]) => `<dt>${key}</dt><dd>${value}</dd>`).join('');
}

async function renderStage(isSheet) {
  const d = detail, item = d.item;
  const stage = $('#stage'), caption = $('#caption');
  const token = d;                                   // si el panel cambia mientras cargamos, abandonamos
  const counter = h('<span class="frame-counter"></span>');
  d.player = new Player((frame, count) => {
    counter.textContent = `${frame + 1} / ${count}`;
    document.querySelectorAll('#strip button').forEach((b, i) => b.classList.toggle('active', i === frame));
  });
  d.player.fps = d.fps;
  const boxW = stage.clientWidth - 48;
  const boxH = Math.min(window.innerHeight * 0.58, 560) - 48;

  try {
    if (d.mode === 'juego') {
      const images = await Promise.all(item.frames.map(loadImage));
      if (detail !== token) return;
      const w = Math.max(...images.map(i => i.naturalWidth)), hh = Math.max(...images.map(i => i.naturalHeight));
      const fit = Math.max(1, Math.floor(Math.min(boxW / w, boxH / hh)));
      const zoom = d.zoom === 'fit' ? Math.min(fit, 8) : d.zoom;
      const view = framesView(images, zoom);
      stage.replaceChildren(view.canvas);
      d.player.setViews([view]);
      caption.textContent = `${w} x ${hh} px${images.length > 1 ? ` por fotograma` : ''}, zoom ${zoom}x${d.zoom === 'fit' ? ' (ajustado)' : ''}. Así se ve en el juego (sin suavizado).`;
      if (images.length > 1) renderStrip(images);
    } else if (d.mode === 'original') {
      const img = await loadImage(item.raw.url);
      if (detail !== token) return;
      const view = sheetView(img, item.columns, item.rows, boxW, boxH, isSheet);
      stage.replaceChildren(view.canvas);
      d.player.setViews([view]);
      caption.textContent = `Original de GPT Image, ${img.naturalWidth} x ${img.naturalHeight} px${isSheet ? `, rejilla ${item.columns} x ${item.rows} (la celda resaltada es el fotograma actual)` : ''}.`;
    } else {
      const version = item.history.find(v => v.name === d.compare);
      const [current, old] = await Promise.all([loadImage(item.raw.url), loadImage(version.url)]);
      if (detail !== token) return;
      stage.classList.add('compare');
      const paneW = (stage.clientWidth - 36) / 2, paneH = boxH - 30;
      // Solo se corta con la rejilla actual si la versión vieja tiene el mismo tamaño:
      // si no, pudo tener otra rejilla (por ejemplo una tira de 1 fila) y cortarla mentiría.
      const sameSize = current.naturalWidth === old.naturalWidth && current.naturalHeight === old.naturalHeight;
      const slice = isSheet && sameSize;
      const make = img => slice ? cellView(img, item.columns, item.rows, paneW, paneH) : sheetView(img, 1, 1, paneW, paneH, false);
      const views = [make(current), make(old)];
      stage.replaceChildren(
        pane('Actual', views[0].canvas),
        pane(`Versión del ${version.date}`, views[1].canvas));
      d.player.setViews(views);
      caption.textContent = slice ? 'Los dos originales cortados con la misma rejilla y animados a la vez.'
        : isSheet ? `La versión anterior mide ${old.naturalWidth} x ${old.naturalHeight} px (la actual ${current.naturalWidth} x ${current.naturalHeight}): su rejilla pudo ser otra, así que se muestran enteras.`
        : 'Los dos originales, lado a lado.';
    }
  } catch (error) {
    stage.replaceChildren(h(`<div class="empty"><strong>No pude cargar la imagen</strong>${esc(error.message)}</div>`));
    return;
  }
  if (d.player.count > 1) renderAnimControls(counter);
}

function pane(title, canvas) {
  const element = h(`<div class="pane"><span class="pane-title">${esc(title)}</span><div class="pane-canvas"></div></div>`);
  $('.pane-canvas', element).append(canvas);
  return element;
}

function renderAnimControls(counter) {
  const d = detail, player = d.player;
  const box = $('#anim');
  const play = h(`<button class="btn icon" title="Reproducir o pausar (Espacio)"></button>`);
  const setPlayIcon = () => { play.innerHTML = player.playing ? '<span class="glyph-pause"></span>' : '<span class="glyph-play"></span>'; };
  setPlayIcon();
  play.onclick = () => { player.playing = !player.playing; setPlayIcon(); };
  const prev = h('<button class="btn small" title="Fotograma anterior (flecha izquierda)">Anterior</button>');
  const next = h('<button class="btn small" title="Fotograma siguiente (flecha derecha)">Siguiente</button>');
  prev.onclick = () => { player.playing = false; setPlayIcon(); player.go(player.frame - 1); };
  next.onclick = () => { player.playing = false; setPlayIcon(); player.go(player.frame + 1); };
  const fps = h(`<label class="fps">Velocidad <input type="range" min="1" max="30" value="${d.fps}"><output>${d.fps} fps</output></label>`);
  const range = $('input', fps), out = $('output', fps);
  range.oninput = () => { d.fps = player.fps = Number(range.value); out.textContent = `${range.value} fps`; };
  const reset = h(`<button class="btn small ghost" title="Volver a los fps del manifiesto">Usar ${d.item.fps} fps</button>`);
  reset.onclick = () => { range.value = d.item.fps; range.oninput(); };
  box.replaceChildren(play, prev, counter, next, fps, reset);
  box.playToggle = play.onclick;
  box.step = delta => (delta < 0 ? prev : next).onclick();
  player.draw();
}

function renderStrip(images) {
  const strip = $('#strip');
  const scale = Math.max(1, Math.floor(64 / Math.max(...images.map(i => i.naturalHeight))));
  strip.replaceChildren(...images.map((img, i) => {
    const button = h(`<button class="bg-${ui.bg}" title="Fotograma ${i + 1}"><span>${String(i + 1).padStart(2, '0')}</span></button>`);
    const view = framesView([img], scale);
    view.draw(0);
    button.prepend(view.canvas);
    button.onclick = () => { detail.player.playing = false; detail.player.go(i); renderAnimControlsIcon(); };
    return button;
  }));
}

function renderAnimControlsIcon() {
  const play = $('#anim .btn.icon');
  if (play) play.innerHTML = '<span class="glyph-play"></span>';
}

function renderVersions(panel) {
  const d = detail, item = d.item;
  const box = $('#versions', panel);
  const entries = [{ name: null, url: item.raw?.url, date: 'Actual' }, ...item.history];
  box.replaceChildren(...entries.filter(v => v.url).map(v => {
    const active = v.name ? d.mode === 'comparar' && d.compare === v.name : d.mode !== 'comparar';
    const element = h(`<button class="version${active ? ' active' : ''}">
      <div class="vthumb bg-${ui.bg}"><img alt="" src="${esc(v.url)}"></div>
      <span>${esc(v.date)}</span></button>`);
    element.onclick = () => {
      if (v.name) { d.mode = 'comparar'; d.compare = v.name; } else { d.mode = item.frames.length ? 'juego' : 'original'; }
      renderDetail();
    };
    return element;
  }));
  const actions = $('#version-actions', panel);
  if (d.mode === 'comparar' && d.compare) {
    const version = item.history.find(v => v.name === d.compare);
    const restore = h(`<button class="btn">Restaurar la versión del ${esc(version.date)}</button>`);
    restore.onclick = () => restoreVersion(item, version);
    actions.replaceChildren(restore, h('<span class="note">Gratis: no llama a la API. La actual pasa al historial.</span>'));
  }
}

// --- Acciones -----------------------------------------------------------------

async function savePrompt(item, prompt) {
  const result = await api('/api/prompt', { kind: 'image', id: item.id, prompt });
  if (result.error) return toast(result.error, true);
  if (detail) detail.draft = null;
  toast(`Prompt de ${item.id} guardado en ${data.manifest}.`);
  await load();
}

export async function generateItem(item, prompt) {
  if (job.running) return toast('Ya hay una generación en curso: espera a que termine.', true);
  const changed = prompt !== undefined && prompt.trim() !== item.prompt.trim();
  const missingRefs = item.reference.filter(r => byId(r)?.status === 'missing');
  const ok = await confirmDialog({
    title: `${item.status === 'ok' ? 'Regenerar' : 'Generar'} ${item.id}`,
    bodyHtml: `
      <p>Esto llama a la API de OpenAI y <b>gasta créditos</b>.</p>
      <p>Modelo <b>${esc(item.model)}</b>, tamaño <b>${esc(item.size)}</b>, calidad <b>${esc(item.quality)}</b>.</p>
      ${changed ? `<p>Antes se guarda tu prompt nuevo en <code>${esc(data.manifest)}</code>.</p>` : ''}
      ${item.raw ? '<p>La versión actual pasa a <code>assets/art/_history/</code>: no se pierde nada.</p>' : ''}
      ${missingRefs.length ? `<p class="note warn">Falta generar la referencia: ${missingRefs.map(esc).join(', ')}. El generador se detendrá.</p>` : ''}
      ${data.key_configured ? '' : '<p class="note warn">No encontré OPENAI_API_KEY: la generación va a fallar.</p>'}`,
  });
  if (!ok) return;
  if (detail) detail.draft = null;
  await runJob({ kind: 'image', id: item.id, prompt: changed ? prompt : undefined });
}

async function restoreVersion(item, version) {
  const ok = await confirmDialog({
    title: `Restaurar ${item.id}`,
    bodyHtml: `<p>Vuelve a la versión del <b>${esc(version.date)}</b> y rehace los PNG del juego a partir de ella.</p>
      <p>No gasta créditos. La versión actual pasa a <code>assets/art/_history/</code>.</p>`,
    okLabel: 'Restaurar',
  });
  if (!ok) return;
  const result = await api('/api/restore', { kind: 'image', id: item.id, name: version.name });
  if (result.error) return toast(result.error, true);
  toast(result.warnings?.length ? `Restaurado con avisos: ${result.warnings.join('; ')}` : `Versión restaurada: ${item.id}.`);
  detail.mode = 'juego';
  detail.compare = null;
  await load();
}

/** Atajos del panel: Esc cierra, Espacio reproduce o pausa, flechas avanzan fotograma a fotograma. */
export function handleKey(event) {
  if (!detail) return false;
  const typing = /TEXTAREA|INPUT/.test(document.activeElement?.tagName);
  if (event.key === 'Escape' && !$('#confirm').open) { closeDetail(); return true; }
  if (typing) return false;
  const anim = $('#anim');
  if (event.key === ' ' && anim?.playToggle) { anim.playToggle(); return true; }
  if (event.key === 'ArrowLeft' && anim?.step) { anim.step(-1); return true; }
  if (event.key === 'ArrowRight' && anim?.step) { anim.step(1); return true; }
  return false;
}
