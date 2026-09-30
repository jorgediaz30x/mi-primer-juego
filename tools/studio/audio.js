// Pestaña Audio: música y efectos del manifiesto de ElevenLabs, con forma de onda,
// reproducción, loop para la música, versiones anteriores y regeneración.

import { $, h, esc, ui, api, toast, confirmDialog, runJob, job, matchesSearch, formatTime, filterButton, deleteEntry } from './shared.js';

const filters = { section: 'todas', status: 'todos' };
const expanded = new Set();                 // filas con el editor abierto
const drafts = new Map();                   // prompts editados y aún sin guardar
const noLoop = new Set();                   // músicas a las que les quitaste el loop
const waves = new Map();                    // url -> { peaks, duration, rmsDb, peakDb } | 'loading' | 'error'
let data = { items: [] };

// Un solo reproductor para toda la página: al tocar otra pista, la anterior se detiene.
const player = new Audio();
let playing = null;                         // { id, url }

export async function load() {
  data = await api('/api/audio');
  data.items ??= [];
  $('#count-audio').textContent = data.items.length;
  render();
}

// --- Lista --------------------------------------------------------------------

export function render() {
  renderFilters();
  const root = $('#audio-groups');
  root.innerHTML = '';
  $('#audio-manifest').innerHTML = data.manifest ? `Manifiesto: <code>${esc(data.manifest)}</code>` : '';
  if (data.error) root.append(h(`<div class="banner error">${esc(data.error)}</div>`));
  if (data.key_configured === false) {
    root.append(h(`<div class="banner">No encontré <b>ELEVENLABS_API_KEY</b> en <code>.env.local</code> ni en el entorno.
      Puedes escuchar todo, pero para generar necesitas la clave.</div>`));
  }
  if (!data.items.length) {
    root.append(h(`<div class="empty"><strong>El manifiesto no tiene audio todavía</strong>
      Agrega entradas a <code>tools/audio/audio_manifest.json</code> y recarga la página.</div>`));
    return;
  }
  const visible = data.items.filter(item =>
    (filters.section === 'todas' || item.section === filters.section) &&
    (filters.status === 'todos' || item.status === filters.status) &&
    matchesSearch(item, ui.search));
  if (!visible.length) {
    root.append(h(`<div class="empty"><strong>Nada coincide con los filtros</strong>
      ${ui.search ? `Prueba con otra búsqueda que no sea "${esc(ui.search)}".` : 'Cambia la sección o el estado.'}</div>`));
    return;
  }

  const music = visible.filter(i => i.section === 'musica');
  const sfx = visible.filter(i => i.section === 'efectos');
  if (music.length) root.append(section('Música', music, 'Pistas largas; el loop está activado como en el juego.'));
  if (sfx.length) {
    // Los efectos se agrupan por el prefijo de su id (sfx_boss_*); los sueltos van a "Varios".
    const groups = [...new Set(sfx.map(i => i.group))].sort((a, b) => (a === 'Varios') - (b === 'Varios') || a.localeCompare(b));
    const block = h(`<section class="group"><div class="group-head"><h2>Efectos</h2><span class="count">${sfx.length}</span></div></section>`);
    for (const group of groups) {
      const items = sfx.filter(i => i.group === group);
      block.append(h(`<div class="group-head" style="margin:18px 0 10px"><span class="mono" style="color:var(--muted)">${esc(group)}</span><span class="count">${items.length}</span></div>`));
      const list = h('<div class="tracks"></div>');
      items.forEach(item => list.append(track(item)));
      block.append(list);
    }
    root.append(block);
  }
  root.querySelectorAll('canvas.wave').forEach(canvas => observer.observe(canvas));
  paintAll();
}

/** Pinta después de insertar las filas: antes el canvas no tiene ancho. */
function paintAll() {
  refreshPlayButtons();
  document.querySelectorAll('.track').forEach(row => paintRow(row, data.items.find(i => i.id === row.dataset.track)));
}

function section(title, items, hint) {
  const block = h(`<section class="group"><div class="group-head"><h2>${esc(title)}</h2><span class="count">${items.length}</span>
    <span class="hint">${esc(hint)}</span></div><div class="tracks"></div></section>`);
  items.forEach(item => $('.tracks', block).append(track(item)));
  return block;
}

function renderFilters() {
  const count = s => data.items.filter(i => i.section === s).length;
  const sections = [['todas', 'Todo', data.items.length], ['musica', 'Música', count('musica')], ['efectos', 'Efectos', count('efectos')]];
  $('#audio-sections').replaceChildren(...sections.map(([id, label, n]) =>
    filterButton(label, n, filters.section === id, () => { filters.section = id; render(); })));
  const ok = data.items.filter(i => i.status === 'ok').length;
  const statuses = [['todos', 'Todos', data.items.length], ['ok', 'Generados', ok], ['missing', 'Sin generar', data.items.length - ok]];
  $('#audio-status').replaceChildren(...statuses.map(([id, label, n]) =>
    filterButton(label, n, filters.status === id, () => { filters.status = id; render(); })));
}

function track(item) {
  const isMusic = item.kind === 'music';
  const isOpen = expanded.has(item.id);
  const element = h(`<article class="track${playing?.id === item.id ? ' playing' : ''}" data-track="${esc(item.id)}">
    <div class="track-main">
      <button class="play" title="Reproducir o detener" ${item.url ? '' : 'disabled'}></button>
      <div class="track-title">
        <span class="id">${esc(item.id)}</span>
        <span class="sub">${item.status === 'ok' ? (isMusic ? 'Música' : 'Efecto') : '<span class="chip missing">Sin generar</span>'}</span>
      </div>
      <canvas class="wave${item.url ? '' : ' missing'}" data-url="${esc(item.url || '')}"></canvas>
      <span class="time"></span>
      <div class="track-actions">
        ${isMusic ? `<label class="toggle"><input type="checkbox" ${noLoop.has(item.id) ? '' : 'checked'}> Loop</label>` : ''}
        ${item.status === 'missing' ? '<button class="btn small primary" data-act="generate">Generar</button>' : ''}
        <button class="btn small${isOpen ? ' active' : ''}" data-act="edit">${isOpen ? 'Cerrar' : 'Editar'}</button>
      </div>
    </div>
    <div class="track-prompt">${esc(item.prompt)}</div>
    <div class="track-meta">
      <span><b>Modelo</b> <span class="mono">${esc(item.model)}</span></span>
      <span><b>Duración pedida</b> ${esc(item.target_s ?? '-')} s</span>
      <span><b>Archivo</b> <span class="mono">${esc(item.out_path)}</span></span>
      <span class="level"></span>
      ${item.history.length ? `<span><b>Versiones anteriores</b> ${item.history.length}</span>` : ''}
    </div>
    ${isOpen ? editor(item) : ''}
  </article>`);

  $('.play', element).onclick = () => toggle(item.id, item.url);
  const loop = $('.toggle input', element);
  if (loop) loop.onchange = () => {
    loop.checked ? noLoop.delete(item.id) : noLoop.add(item.id);
    if (playing?.id === item.id) player.loop = loop.checked;
  };
  $('[data-act=edit]', element).onclick = () => { isOpen ? expanded.delete(item.id) : expanded.add(item.id); render(); };
  $('[data-act=generate]', element)?.addEventListener('click', () => generateItem(item));
  $('canvas.wave', element).addEventListener('click', event => seek(item, event));
  if (isOpen) wireEditor(item, element);
  return element;
}

function editor(item) {
  return `<div class="track-edit">
    <div>
      <h3 class="section-title">Prompt</h3>
      <textarea class="prompt" spellcheck="false" style="min-height:96px"></textarea>
      <div class="prompt-actions">
        <button class="btn primary" data-act="regen">${item.status === 'ok' ? 'Regenerar' : 'Generar'}</button>
        <button class="btn" data-act="save" disabled>Guardar prompt</button>
        <button class="btn" data-act="dry">Ver prompt final</button>
        ${item.status === 'missing' ? '<button class="btn danger" data-act="delete">Eliminar entrada</button>' : ''}
        <span class="note"></span>
      </div>
      <p class="note">Generar llama a ElevenLabs y gasta créditos. "Ver prompt final" es gratis.</p>
    </div>
    <div>
      <h3 class="section-title">Versiones anteriores (${item.history.length})</h3>
      ${item.history.length ? '<div class="history-list"></div>'
        : '<p class="note">Todavía no hay. Cada vez que regeneras, la actual pasa a <code>assets/audio/_history/</code>.</p>'}
    </div>
  </div>`;
}

function wireEditor(item, element) {
  const textarea = $('textarea', element), note = $('.prompt-actions .note', element), save = $('[data-act=save]', element);
  textarea.value = drafts.get(item.id) ?? item.prompt;
  const sync = () => {
    const dirty = textarea.value.trim() !== item.prompt.trim();
    dirty ? drafts.set(item.id, textarea.value) : drafts.delete(item.id);
    save.disabled = !dirty;
    note.textContent = dirty ? 'Cambios sin guardar ("Ver prompt final" muestra la versión guardada).' : '';
    note.className = dirty ? 'note warn' : 'note';
  };
  textarea.addEventListener('input', sync);
  sync();
  save.onclick = () => savePrompt(item, textarea.value);
  $('[data-act=dry]', element).onclick = () => runJob({ kind: 'audio', id: item.id, dryRun: true });
  $('[data-act=regen]', element).onclick = () => generateItem(item, textarea.value);
  $('[data-act=delete]', element)?.addEventListener('click', async () => {
    if (await deleteEntry('audio', item.id)) { expanded.delete(item.id); await load(); }
  });

  const list = $('.history-list', element);
  if (!list) return;
  for (const version of item.history) {
    const row = h(`<div class="history-row">
      <button class="play" title="Reproducir o detener"></button>
      <span>${esc(version.date)}</span><span class="time" data-history="${esc(version.url)}"></span>
      <button class="btn small ghost">Restaurar</button></div>`);
    $('.play', row).onclick = () => toggle(`${item.id}@${version.name}`, version.url);
    $('.btn', row).onclick = () => restoreVersion(item, version);
    list.append(row);
  }
}

// --- Reproducción ---------------------------------------------------------------

function toggle(key, url) {
  if (!url) return;
  if (playing?.key === key) { stop(); return; }
  const id = key.split('@')[0];
  const item = data.items.find(i => i.id === id);
  player.src = url;
  player.loop = item?.kind === 'music' && !noLoop.has(id) && !key.includes('@');
  player.play().catch(error => toast(`No se pudo reproducir: ${error.message}`, true));
  playing = { key, id, url };
  requestAnimationFrame(progressLoop);
  refreshPlayButtons();
}

function stop() {
  player.pause();
  playing = null;
  paintAll();
}

player.addEventListener('ended', () => { if (!player.loop) stop(); });

function seek(item, event) {
  if (!item.url) return;
  const canvas = event.currentTarget;
  const ratio = (event.clientX - canvas.getBoundingClientRect().left) / canvas.clientWidth;
  if (playing?.key !== item.id) toggle(item.id, item.url);
  const apply = () => { if (Number.isFinite(player.duration)) player.currentTime = ratio * player.duration; };
  player.readyState >= 1 ? apply() : player.addEventListener('loadedmetadata', apply, { once: true });
}

function refreshPlayButtons() {
  document.querySelectorAll('.track').forEach(row => {
    row.classList.toggle('playing', playing?.id === row.dataset.track && !playing.key.includes('@'));
    const button = $('.track-main .play', row);
    button.innerHTML = playing?.key === row.dataset.track ? '<span class="glyph-stop"></span>' : '<span class="glyph-play"></span>';
    row.querySelectorAll('.history-row').forEach(hr => {
      const url = $('.time', hr).dataset.history;
      $('.play', hr).innerHTML = playing?.url === url ? '<span class="glyph-stop"></span>' : '<span class="glyph-play"></span>';
    });
  });
}

function progressLoop() {
  if (!playing) return;
  const row = document.querySelector(`.track[data-track="${CSS.escape(playing.id)}"]`);
  if (row) {
    if (playing.key.includes('@')) {
      const time = row.querySelector(`.history-row .time[data-history="${CSS.escape(playing.url)}"]`);
      if (time) time.textContent = `${formatTime(player.currentTime, player.duration)} / ${formatTime(player.duration)}`;
    } else {
      paintRow(row, data.items.find(i => i.id === playing.id));
    }
  }
  requestAnimationFrame(progressLoop);
}

// --- Forma de onda ------------------------------------------------------------------
// Se decodifica el MP3 en el navegador (Web Audio) solo cuando la fila se ve en pantalla,
// de a uno por vez, y se guarda en memoria. De paso medimos el nivel (RMS y pico).

const queue = [];
let decoding = false;
const observer = new IntersectionObserver(entries => {
  for (const entry of entries) {
    const url = entry.target.dataset.url;
    if (entry.isIntersecting && url && !waves.has(url)) { waves.set(url, 'loading'); queue.push(url); }
  }
  pump();
});

async function pump() {
  if (decoding || !queue.length) return;
  decoding = true;
  const url = queue.shift();
  try {
    waves.set(url, await analyse(url));
  } catch {
    waves.set(url, 'error');
  }
  decoding = false;
  const item = data.items.find(i => i.url === url);
  const row = item && document.querySelector(`.track[data-track="${CSS.escape(item.id)}"]`);
  if (row) paintRow(row, item);            // en su lugar: no rompe un prompt que estés escribiendo
  pump();
}

async function analyse(url) {
  const bytes = await (await fetch(url)).arrayBuffer();
  const buffer = await new OfflineAudioContext(1, 1, 44100).decodeAudioData(bytes);
  const channels = Array.from({ length: buffer.numberOfChannels }, (_, c) => buffer.getChannelData(c));
  const length = channels[0].length, buckets = 480, size = Math.max(1, Math.floor(length / buckets));
  const peaks = new Float32Array(buckets);
  let sum = 0, peak = 0;
  for (let b = 0; b < buckets; b++) {
    let max = 0;
    for (let i = b * size; i < Math.min(length, (b + 1) * size); i++) {
      for (const data of channels) {
        const v = Math.abs(data[i]);
        if (v > max) max = v;
        sum += v * v;
      }
    }
    peaks[b] = max;
    if (max > peak) peak = max;
  }
  const rms = Math.sqrt(sum / (buckets * size * channels.length));
  const db = v => (v > 0 ? 20 * Math.log10(v) : -Infinity);
  return { peaks, duration: buffer.duration, rmsDb: db(rms), peakDb: db(peak) };
}

/** Dibuja la onda de una fila, con la parte ya escuchada en ámbar, y actualiza el tiempo. */
function paintRow(row, item) {
  if (!row || !item) return;
  const canvas = $('canvas.wave', row), time = $('.track-main .time', row);
  const wave = waves.get(item.url);
  const isCurrent = playing?.key === item.id;
  const duration = (typeof wave === 'object' && wave?.duration) || (isCurrent && player.duration) || NaN;
  time.textContent = item.url ? `${isCurrent ? formatTime(player.currentTime, duration) + ' / ' : ''}${formatTime(duration)}` : '';
  if (!item.url) return;

  const ratio = window.devicePixelRatio || 1;
  const width = Math.max(1, Math.round(canvas.clientWidth * ratio)), height = Math.round(40 * ratio);
  if (canvas.width !== width || canvas.height !== height) { canvas.width = width; canvas.height = height; }
  const ctx = canvas.getContext('2d');
  ctx.clearRect(0, 0, width, height);
  const progress = isCurrent && Number.isFinite(player.duration) ? player.currentTime / player.duration : 0;
  const mid = height / 2;

  const level = $('.level', row);
  if (typeof wave === 'object' && wave && !level.textContent) {
    level.innerHTML = `<b>Nivel</b> RMS ${wave.rmsDb.toFixed(1)} dB, pico ${wave.peakDb.toFixed(1)} dB`;
  }
  if (typeof wave !== 'object' || !wave) {
    // Aún sin onda (cargando o falló): una barra de progreso simple.
    ctx.fillStyle = '#262b35';
    ctx.fillRect(0, mid - 2 * ratio, width, 4 * ratio);
    ctx.fillStyle = '#f0b65a';
    ctx.fillRect(0, mid - 2 * ratio, width * progress, 4 * ratio);
    return;
  }
  const bar = 3 * ratio, gap = 1 * ratio, count = Math.floor(width / (bar + gap));
  const top = Math.max(...wave.peaks) || 1;
  for (let i = 0; i < count; i++) {
    const value = wave.peaks[Math.floor(i / count * wave.peaks.length)] / top;
    const barHeight = Math.max(2 * ratio, value * (height - 6 * ratio));
    ctx.fillStyle = (i / count) < progress ? '#f0b65a' : '#4a5263';
    ctx.fillRect(i * (bar + gap), mid - barHeight / 2, bar, barHeight);
  }
}

window.addEventListener('resize', paintAll);

// --- Acciones -----------------------------------------------------------------

async function savePrompt(item, prompt) {
  const result = await api('/api/prompt', { kind: 'audio', id: item.id, prompt });
  if (result.error) return toast(result.error, true);
  drafts.delete(item.id);
  toast(`Prompt de ${item.id} guardado en ${data.manifest}.`);
  await load();
}

async function generateItem(item, prompt) {
  if (job.running) return toast('Ya hay una generación en curso: espera a que termine.', true);
  const changed = prompt !== undefined && prompt.trim() !== item.prompt.trim();
  const ok = await confirmDialog({
    title: `${item.status === 'ok' ? 'Regenerar' : 'Generar'} ${item.id}`,
    bodyHtml: `
      <p>Esto llama a la API de ElevenLabs y <b>gasta créditos</b>.</p>
      <p>Modelo <b>${esc(item.model)}</b>, duración <b>${esc(item.target_s ?? '-')} s</b>.</p>
      ${changed ? `<p>Antes se guarda tu prompt nuevo en <code>${esc(data.manifest)}</code>.</p>` : ''}
      ${item.url ? '<p>La versión actual pasa a <code>assets/audio/_history/</code>: no se pierde nada.</p>' : ''}
      ${data.key_configured ? '' : '<p class="note warn">No encontré ELEVENLABS_API_KEY: la generación va a fallar.</p>'}`,
  });
  if (!ok) return;
  if (playing?.id === item.id) stop();
  drafts.delete(item.id);
  await runJob({ kind: 'audio', id: item.id, prompt: changed ? prompt : undefined });
}

async function restoreVersion(item, version) {
  const ok = await confirmDialog({
    title: `Restaurar ${item.id}`,
    bodyHtml: `<p>Vuelve a la versión del <b>${esc(version.date)}</b>. No gasta créditos.</p>
      <p>La versión actual pasa a <code>assets/audio/_history/</code>.</p>`,
    okLabel: 'Restaurar',
  });
  if (!ok) return;
  stop();
  const result = await api('/api/restore', { kind: 'audio', id: item.id, name: version.name });
  if (result.error) return toast(result.error, true);
  toast(`Versión restaurada: ${item.id}.`);
  await load();
}

/** Abre el editor de una fila (lo usa "Crear nuevo" al terminar). */
export function expand(id) { expanded.add(id); render(); }

export function stopAudio() { if (playing) stop(); }
