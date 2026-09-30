// Piezas comunes a las dos pestañas: pedir datos al servidor, avisos,
// la confirmación antes de gastar créditos y el registro de una generación.

export const $ = (selector, root = document) => root.querySelector(selector);

/** Crea un elemento a partir de HTML. Todo texto que viene de datos pasa antes por esc(). */
export function h(html) {
  const template = document.createElement('template');
  template.innerHTML = html.trim();
  return template.content.firstElementChild;
}

export function esc(text) {
  return String(text ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

/** Minúsculas y sin tildes, para que buscar "animacion" encuentre "animación". */
export function normalize(text) {
  return String(text ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
}

export function matchesSearch(item, query) {
  if (!query) return true;
  const haystack = normalize(`${item.id} ${item.prompt} ${item.group ?? ''} ${item.kind_label ?? ''}`);
  return normalize(query).split(/\s+/).every(word => haystack.includes(word));
}

/** Estado de la interfaz que comparten las pestañas. */
export const ui = {
  search: '',
  bg: localStorage.getItem('studio.bg') || 'checker',   // fondo para ver la transparencia
};

export function setBackground(bg) {
  ui.bg = bg;
  localStorage.setItem('studio.bg', bg);
}

/** Botón de filtro de la barra lateral: etiqueta a la izquierda, cantidad a la derecha. */
export function filterButton(label, count, active, onClick) {
  const button = h(`<button class="filter${active ? ' active' : ''}"><span>${esc(label)}</span><span class="count">${count}</span></button>`);
  button.addEventListener('click', onClick);
  return button;
}

/** GET si no hay body, POST con JSON si lo hay. Siempre devuelve un objeto; los fallos traen .error. */
export async function api(path, body) {
  const options = body
    ? { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }
    : { cache: 'no-store' };
  try {
    const response = await fetch(path, options);
    const data = await response.json().catch(() => ({ error: `Respuesta inválida del servidor (${response.status})` }));
    if (!response.ok && !data.error) data.error = `Error ${response.status}`;
    return data;
  } catch (error) {
    return { error: `No hay conexión con el servidor. ¿Sigue abierto python tools/studio/server.py? (${error.message})` };
  }
}

let toastTimer = null;
export function toast(message, isError = false) {
  const box = $('#toast');
  box.textContent = message;
  box.classList.toggle('error', isError);
  box.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { box.hidden = true; }, isError ? 7000 : 3500);
}

/** Diálogo modal. Resuelve true solo si pulsas el botón de confirmar. El foco empieza en Cancelar. */
export function confirmDialog({ title, bodyHtml, okLabel = 'Sí, generar' }) {
  const dialog = $('#confirm');
  $('#confirm-title').textContent = title;
  $('#confirm-body').innerHTML = bodyHtml;
  $('#confirm-ok').textContent = okLabel;
  dialog.returnValue = '';
  dialog.showModal();
  return new Promise(resolve => {
    dialog.addEventListener('close', () => resolve(dialog.returnValue === 'ok'), { once: true });
  });
}

// --- Generaciones -----------------------------------------------------------
// El servidor corre el generador real en segundo plano. Aquí lo iniciamos y
// preguntamos cada 400 ms por las líneas nuevas del registro.

export const job = { running: false, current: null };
const doneListeners = [];
export function onJobDone(listener) { doneListeners.push(listener); }

export async function runJob({ kind, id, dryRun = false, prompt }) {
  const body = { kind, id, dry_run: dryRun };
  if (prompt !== undefined) body.prompt = prompt;
  const data = await api('/api/job', body);
  if (data.error) {
    toast(data.error, true);
    return false;
  }
  follow(data.job);
  return true;
}

/** Si recargas la página en mitad de una generación, retoma su registro. */
export async function resumeJob() {
  const data = await api('/api/job');
  if (data.job && data.job.status === 'running') follow(data.job);
}

async function follow(started) {
  job.running = true;
  job.current = started;
  openLog(started);
  appendLines(started.lines);
  let since = started.total;
  for (;;) {
    await new Promise(resolve => setTimeout(resolve, 400));
    const data = await api(`/api/job?since=${since}`);
    const current = data.job;
    if (!current || current.id !== started.id) break;
    appendLines(current.lines);
    since = current.total;
    updateStatus(current);
    if (current.status !== 'running') {
      job.running = false;
      doneListeners.forEach(listener => listener(current));
      if (current.status === 'ok') toast(current.dry_run ? 'Prompt final listo en el registro.' : `Listo: ${current.asset_id} actualizado.`);
      else toast(`La generación de ${current.asset_id} falló. Mira el registro.`, true);
      break;
    }
  }
  job.running = false;
}

function openLog(started) {
  $('#log-title').textContent = started.dry_run ? `Prompt final de ${started.asset_id}` : `Generando ${started.asset_id}`;
  $('#log-body').textContent = '';
  $('#log').hidden = false;
  updateStatus(started);
}

function appendLines(lines) {
  const body = $('#log-body');
  for (const line of lines) {
    const row = document.createElement('div');
    row.textContent = line || ' ';
    if (line.startsWith('$ ')) row.className = 'l-cmd';
    else if (/^\[error\]|Traceback|Error\b|^No pude/.test(line)) row.className = 'l-err';
    else if (/aviso|Tip:/.test(line)) row.className = 'l-warn';
    else if (/^\[ok\]/.test(line)) row.className = 'l-ok';
    body.append(row);
  }
  body.scrollTop = body.scrollHeight;
}

function updateStatus(current) {
  const labels = { running: `En curso, ${current.seconds} s`, ok: `Terminado en ${current.seconds} s`, error: 'Falló' };
  const chip = $('#log-status');
  chip.className = `chip ${current.status}`;
  chip.textContent = labels[current.status];

  const pill = $('#job-pill');
  pill.hidden = false;
  pill.className = `job-pill ${current.status === 'running' ? '' : current.status}`;
  const what = current.dry_run ? 'Prompt final' : 'Generación';
  pill.textContent = current.status === 'running' ? `${what}: ${current.asset_id}` : `${what}: ${current.asset_id} (${labels[current.status].toLowerCase()})`;
}

export function initLog() {
  $('#log-close').addEventListener('click', () => { $('#log').hidden = true; });
  $('#job-pill').addEventListener('click', () => { $('#log').hidden = !$('#log').hidden; });
}

/** Quita del manifiesto una entrada que aún no se generó. El servidor se niega si ya tiene archivos. */
export async function deleteEntry(kind, id) {
  const ok = await confirmDialog({
    title: `Eliminar ${id}`,
    bodyHtml: `<p>Se quita la entrada <b>${esc(id)}</b> del manifiesto.</p>
      <p>No se borra ningún archivo: esta entrada todavía no se generó.</p>`,
    okLabel: 'Eliminar',
  });
  if (!ok) return false;
  const result = await api('/api/delete', { kind, id });
  if (result.error) { toast(result.error, true); return false; }
  toast(`${id} eliminado del manifiesto.`);
  return true;
}

// --- Formatos ---------------------------------------------------------------

/** 1:05 para pistas largas; 0.5 s para efectos cortos. [total] decide el formato, así los dos lados coinciden. */
export function formatTime(seconds, total = seconds) {
  if (!Number.isFinite(seconds)) return '-:--';
  if (total < 10) return `${seconds.toFixed(1)} s`;      // efectos cortos: 0.5 s, no 0:00
  const s = Math.max(0, Math.round(seconds));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

export function loadImage(url) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error(`no se pudo cargar ${url}`));
    img.src = url;
  });
}
