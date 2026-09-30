// "Crear nuevo": un formulario para agregar un asset al manifiesto.
// Los valores por defecto los calcula el servidor a partir de las entradas que ya
// existen (/api/templates), así lo nuevo sale igual que lo que ya tienes.
// El servidor vuelve a validar todo antes de escribir.

import { $, h, esc, api, toast, confirmDialog, job } from './shared.js';

const TYPES = [
  ['personaje', 'Imagen', 'Personaje', 'Un sprite quieto: héroe, enemigo, jefe.'],
  ['animacion', 'Imagen', 'Animación', 'Hoja de sprites de un personaje que ya existe.'],
  ['fondo', 'Imagen', 'Fondo / nivel', 'Fondo lejano o tramo de nivel con suelo.'],
  ['efecto', 'Imagen', 'Efecto', 'Hechizo, chispa o explosión animada.'],
  ['interfaz', 'Imagen', 'Interfaz / icono', 'Mira, panel, barra o icono.'],
  ['musica', 'Audio', 'Música', 'Pista larga que suena en loop.'],
  ['sfx', 'Audio', 'Efecto de sonido', 'Un sonido corto: golpe, hechizo, aviso.'],
];
const ID_PATTERN = /^[a-z][a-z0-9_]{1,47}$/;

let tpl = null;          // lo que devuelve /api/templates
let form = null;         // { type, f: campos, touched: campos que editaste a mano }
let onSaved = () => {};

const isAudio = type => type === 'musica' || type === 'sfx';
const isSheet = type => type === 'animacion' || type === 'efecto';

export async function openCreate({ audio = false, saved } = {}) {
  onSaved = saved || onSaved;
  tpl = await api('/api/templates');
  if (tpl.error) return toast(tpl.error, true);
  start(audio ? 'sfx' : 'personaje');
  $('#create').hidden = false;
  $('#detail-backdrop').hidden = false;
}

export function closeCreate() {
  form = null;
  $('#create').hidden = true;
  if ($('#detail').hidden) $('#detail-backdrop').hidden = true;
}

export const isOpen = () => form !== null;

// --- Valores por defecto y campos que se calculan solos ---------------------------

function start(type) {
  const t = tpl.types[type];
  const character = tpl.characters[0];
  form = {
    type,
    touched: new Set(),
    f: {
      id: '', prompt: '', action: '', link: '', out: '', out_dir: '',
      kind: type === 'fondo' ? 'panorama' : t.kind,
      size: t.size, background: t.background, pixel_height: t.pixel_height,
      columns: t.columns, rows: t.rows, fps: t.fps, loop: t.loop,
      // Solo se sugiere una referencia que ya exista como imagen: si no, el generador se detiene.
      reference: (t.reference || []).filter(r => tpl.generated_images.includes(r)),
      character: character?.id || '',
      length_s: t.length_s, duration_s: t.duration_s,
    },
  };
  derive();
  render();
}

/** Rellena lo que depende de otros campos, salvo lo que ya editaste a mano. */
function derive() {
  const { type, f, touched } = form;
  const t = tpl.types[type];
  const set = (key, value) => { if (!touched.has(key)) f[key] = value; };
  const character = tpl.characters.find(c => c.id === f.character);
  if (type === 'animacion') {
    set('id', f.character && f.action ? `${f.character}_${f.action}` : '');
    if (character) { set('pixel_height', character.pixel_height); f.reference = [character.id]; }
  }
  if (type === 'fondo') {
    const byKind = t.by_kind?.[f.kind] || {};
    set('size', byKind.size || t.size);
    set('background', byKind.background || t.background);
  }
  if (isSheet(type)) {
    const grid = `${f.columns}x${f.rows}`;
    set('size', tpl.sheet_sizes[grid] || tpl.rows_sizes[String(f.rows)] || t.size);
  }
  // Nombre sin prefijo: sfx_nova -> nova (así se llaman los archivos existentes).
  const name = t.prefix && f.id.startsWith(t.prefix) ? f.id.slice(t.prefix.length) : f.id;
  const fill = pattern => (pattern || '')
    .replaceAll('{id}', f.id || '<id>').replaceAll('{name}', name || '<id>').replaceAll('{folder}', t.folder || '')
    .replaceAll('{character}', f.character || '<personaje>').replaceAll('{action}', f.action || '<accion>')
    .replaceAll('{character_dir}', character?.folder || '');
  if (t.out) set('out', fill(t.out));
  if (t.out_dir) set('out_dir', fill(t.out_dir));
  set('link', t.link && f.id ? fill(t.link) : '');
}

// --- Dibujar el formulario ------------------------------------------------------------

function render() {
  const { type, f } = form;
  const t = tpl.types[type];
  const panel = $('#create');
  const audio = isAudio(type), sheet = isSheet(type);
  panel.innerHTML = `
    <header class="detail-head">
      <h2 style="font-family:var(--font)">Crear nuevo</h2>
      <span class="chip">${esc(t.label)}</span>
      <span class="spacer"></span>
      <button class="btn ghost small" data-act="close">Cerrar</button>
    </header>
    <div class="detail-scroll">
      <section class="form-section">
        <h3 class="section-title">Tipo</h3>
        <div class="type-grid">${TYPES.map(([id, tag, label, desc]) => `
          <button class="type-option${id === type ? ' active' : ''}" data-type="${id}">
            <span class="tag">${tag}</span><strong>${label}</strong><span>${desc}</span></button>`).join('')}
        </div>
      </section>

      <section class="form-section">
        <h3 class="section-title">Nombre</h3>
        <div class="form-grid">
          ${type === 'animacion' ? `
            ${field('Personaje', `<select data-f="character">${tpl.characters.map(c =>
              `<option value="${esc(c.id)}"${c.id === f.character ? ' selected' : ''}>${esc(c.id)}</option>`).join('')}</select>`,
              tpl.characters.length ? 'Se manda como referencia para que se vea igual.' : 'Primero crea un personaje.')}
            ${field('Acción', input('action', 'text', 'run, jump, attack'), 'En inglés y snake_case, como las existentes.')}` : ''}
          ${field('id', input('id', 'text', t.prefix ? `${t.prefix}nombre` : 'nombre_en_snake_case', 'mono'), '', 'id-help', type === 'animacion' ? '' : 'wide')}
        </div>
      </section>

      <section class="form-section">
        <h3 class="section-title">Formato</h3>
        <div class="form-grid">${audio ? audioFields() : imageFields(sheet)}</div>
        ${audio ? '' : referencesField()}
      </section>

      <section class="form-section">
        <h3 class="section-title">Dónde se guarda</h3>
        <div class="form-grid">
          ${sheet ? field('Carpeta de salida', input('out_dir', 'text', '', 'mono'), esc(framesHelp()), 'frames-help', 'wide')
                  : field('Archivo de salida', input('out', 'text', '', 'mono'), 'Sugerido según las carpetas que ya usas.', '', 'wide')}
          ${field('Enlace en game_config.json (opcional)', input('link', 'text', 'vacío = no enlazar', 'mono'),
            'Ruta con puntos donde el juego busca el asset. Si lo dejas vacío, o si el juego aún no tiene game_config.json, el generador solo avisa.', '', 'wide')}
        </div>
      </section>

      <section class="form-section">
        <h3 class="section-title">Descripción (prompt)</h3>
        <textarea class="prompt" data-f="prompt" spellcheck="false" placeholder="${audio
          ? 'Qué suena: instrumentos, tempo, ánimo. Por ejemplo: soft wooden chime, gentle and warm, video game'
          : 'Qué se ve: sujeto, pose, vista. Por ejemplo: small green goblin with a torch, side view facing right, whole body visible'}"></textarea>
        ${hints(type)}
      </section>

      <div id="create-errors"></div>
      <pre class="preview-out" id="create-preview" hidden></pre>

      <div class="prompt-actions">
        <button class="btn primary" data-act="generate">Guardar y generar</button>
        <button class="btn" data-act="save">Guardar en el manifiesto</button>
        <button class="btn" data-act="preview">Ver prompt final</button>
      </div>
      <p class="note">"Guardar en el manifiesto" agrega la entrada como Sin generar, gratis. "Guardar y generar" además llama a
        ${audio ? 'ElevenLabs' : 'OpenAI'} y gasta créditos.</p>
    </div>`;
  $('textarea[data-f=prompt]', panel).value = f.prompt;
  wire(panel);
  checkId();
}

const framesHelp = () => `Los fotogramas se guardan como ${form.f.id || '<id>'}_00.png, _01.png...`;

function field(label, control, help = '', helpId = '', cls = '') {
  return `<div class="field ${cls}"><label>${label}</label>${control}${help || helpId ? `<span class="help"${helpId ? ` id="${helpId}"` : ''}>${help}</span>` : ''}</div>`;
}

function input(key, type, placeholder = '', cls = '') {
  return `<input type="${type}" data-f="${key}" value="${esc(form.f[key] ?? '')}" placeholder="${esc(placeholder)}" class="${cls}" autocomplete="off" spellcheck="false">`;
}

function select(key, options) {
  return `<select data-f="${key}">${options.map(([value, label]) =>
    `<option value="${esc(value)}"${String(form.f[key]) === String(value) ? ' selected' : ''}>${esc(label)}</option>`).join('')}</select>`;
}

function imageFields(sheet) {
  const { type, f } = form;
  const onScreen = Number(f.pixel_height) * tpl.game_scale;
  const parts = [];
  if (type === 'fondo') parts.push(field('Tipo de fondo', select('kind', [['panorama', 'Tramo de nivel (con suelo)'], ['backdrop', 'Fondo lejano (pantalla completa)']])));
  parts.push(field('Tamaño pedido', select('size', tpl.sizes.map(s => [s, s])), 'Los que ya funcionan; 1024x512 falla.'));
  parts.push(field('Fondo de la imagen', select('background', [['transparent', 'Transparente'], ['opaque', 'Opaco']])));
  parts.push(field('Alto en pixel art (px)', input('pixel_height', 'number'),
    Number.isFinite(onScreen) ? `En pantalla: ${onScreen} px (x${tpl.game_scale}).` : ''));
  if (sheet) {
    parts.push(field('Columnas', input('columns', 'number')));
    parts.push(field('Filas', input('rows', 'number'), `${Number(f.columns) * Number(f.rows) || 0} fotogramas (máximo 16).`));
    parts.push(field('Fotogramas por segundo', input('fps', 'number')));
    parts.push(field('Repetición', `<label class="check"><input type="checkbox" data-f="loop"${f.loop ? ' checked' : ''}> Se repite en loop</label>`));
  }
  parts.push(field('Modelo', `<input type="text" value="${esc(tpl.image_model)}" disabled class="mono">`, `Calidad ${esc(tpl.quality)}, del manifiesto.`));
  return parts.join('');
}

function audioFields() {
  const music = form.type === 'musica';
  return [
    music ? field('Duración (s)', input('length_s', 'number'), 'De 10 a 600 segundos.')
          : field('Duración (s)', input('duration_s', 'number'), 'De 0.5 a 30 segundos.'),
    field('Modelo', `<input type="text" value="${esc(music ? tpl.music_model : tpl.sfx_model)}" disabled class="mono">`,
      music ? 'La música usa el modelo de música del manifiesto.' : 'Los efectos usan el modelo de efectos del manifiesto.'),
  ].join('');
}

function referencesField() {
  const { type, f } = form;
  if (type === 'animacion') return '';
  const available = tpl.image_ids.filter(id => !f.reference.includes(id));
  return `<div class="field"><label>Referencias de estilo</label>
    <div class="chips" id="refs">
      ${f.reference.map(r => `<span class="chip-x">${esc(r)}${tpl.generated_images.includes(r) ? '' : ' (sin generar)'}<button data-ref-remove="${esc(r)}" title="Quitar">x</button></span>`).join('')}
      <select id="ref-add"><option value="">Agregar referencia</option>${available.map(id => `<option>${esc(id)}</option>`).join('')}</select>
    </div>
    <span class="help${f.reference.some(r => !tpl.generated_images.includes(r)) ? ' bad' : ''}">${f.reference.some(r => !tpl.generated_images.includes(r))
      ? 'Una referencia todavía no está generada: genérala primero o quítala, o el generador se detendrá.'
      : 'Imágenes ya generadas que se mandan para mantener el mismo estilo. Por defecto, la que usan los de este tipo.'}</span></div>`;
}

function hints(type) {
  if (isAudio(type)) {
    return `<div class="hint-box"><strong>Reglas del proyecto</strong><ul>
      <li>No nombres artistas, bandas, canciones ni juegos: ElevenLabs rechaza el prompt. Describe el estilo (instrumentos, tempo, ánimo).</li>
      ${type === 'musica' ? '<li>Si va en loop, pide que empiece y termine suave ("seamless loop-friendly").</li><li>La música se pide instrumental, sin voces.</li>'
        : '<li>Corto y concreto; termina con "video game" como los demás efectos.</li>'}
      <li>Escríbelo en inglés, como el resto del manifiesto.</li></ul></div>`;
  }
  const f = form.f;
  const frames = Number(f.columns) * Number(f.rows);
  const ruleKey = type === 'efecto' ? 'effect_rules' : type === 'animacion' ? 'sheet_rules' : null;
  const rule = ruleKey ? (tpl.rules[ruleKey] || '').replaceAll('{frames}', frames).replaceAll('{columns}', f.columns).replaceAll('{rows}', f.rows) : '';
  return `<div class="hint-box">
    <details><summary>Se antepone el estilo común${rule ? ' y las reglas de la hoja' : ''} (como hace generate_art.py)</summary>
      <pre>${esc(tpl.style)}${rule ? `\n\n${esc(rule)}` : ''}</pre></details>
    <ul>
      <li>Sin texto, letras, números ni logos dentro de la imagen.</li>
      <li>Diseños originales: nada de personajes, marcas o franquicias existentes.</li>
      <li>Describe el sujeto, la pose y la vista; el estilo ya lo pone el bloque común.</li>
      ${isSheet(type) ? '<li>Di qué pasa en cada fotograma, en orden.</li>' : ''}
      ${f.background === 'transparent' ? '<li>Fondo transparente: pide el sujeto aislado, sin escenario, suelo ni sombra.</li>' : ''}
      <li>Escríbelo en inglés, como el resto del manifiesto.</li>
    </ul></div>`;
}

// --- Eventos ------------------------------------------------------------------

function wire(panel) {
  $('[data-act=close]', panel).onclick = closeCreate;
  panel.querySelectorAll('[data-type]').forEach(b => { b.onclick = () => start(b.dataset.type); });
  // Cambios que alteran qué campos se muestran: se vuelve a dibujar.
  const structural = new Set(['character', 'kind', 'columns', 'rows', 'background', 'pixel_height']);
  panel.querySelectorAll('[data-f]').forEach(el => {
    const key = el.dataset.f;
    const update = () => {
      const before = { ...form.f };
      form.f[key] = el.type === 'checkbox' ? el.checked : el.value;
      if (['id', 'out', 'out_dir', 'link', 'size', 'background', 'pixel_height'].includes(key)) form.touched.add(key);
      if (key === 'id' && !el.value) form.touched.delete('id');
      derive();
      if (structural.has(key)) { render(); return; }
      // Solo se actualizan los campos derivados, sin perder el foco de lo que escribes.
      for (const k of ['id', 'out', 'out_dir', 'link']) {
        const other = $(`[data-f=${k}]`, panel);
        if (other && other !== el && before[k] !== form.f[k]) other.value = form.f[k];
      }
      const frames = $('#frames-help', panel);
      if (frames) frames.textContent = framesHelp();
      checkId();
    };
    // Números, listas y casillas: al confirmar el valor (así no pierdes el foco mientras escribes).
    el.addEventListener(['SELECT'].includes(el.tagName) || ['checkbox', 'number'].includes(el.type) ? 'change' : 'input', update);
  });
  const add = $('#ref-add', panel);
  if (add) add.onchange = () => { if (add.value) { form.f.reference.push(add.value); render(); } };
  panel.querySelectorAll('[data-ref-remove]').forEach(b => {
    b.onclick = () => { form.f.reference = form.f.reference.filter(r => r !== b.dataset.refRemove); render(); };
  });
  $('[data-act=preview]', panel).onclick = () => submit('preview');
  $('[data-act=save]', panel).onclick = () => submit('save');
  $('[data-act=generate]', panel).onclick = () => submit('generate');
}

/** Aviso en vivo del id; el servidor lo valida de nuevo al guardar. */
function checkId() {
  const help = $('#id-help');
  if (!help) return;
  const id = form.f.id;
  const taken = (isAudio(form.type) ? tpl.audio_ids : tpl.image_ids).includes(id);
  const ok = ID_PATTERN.test(id) && !taken;
  help.className = `help ${id ? (ok ? 'good' : 'bad') : ''}`;
  help.textContent = !id ? 'Minúsculas, números y _ (snake_case). Tiene que ser único.'
    : taken ? `Ya existe un asset llamado ${id}.`
    : !ID_PATTERN.test(id) ? 'Usa snake_case: minúsculas, números y _, empezando por una letra.'
    : 'Disponible.';
}

async function submit(mode) {
  const body = { type: form.type, fields: { ...form.f } };
  if (mode === 'generate') {
    if (job.running) return toast('Ya hay una generación en curso: espera a que termine.', true);
    const audio = isAudio(form.type);
    const check = await api('/api/preview', body);           // valida antes de pedir confirmación
    if (showErrors(check)) return;
    const ok = await confirmDialog({
      title: `Guardar y generar ${form.f.id}`,
      bodyHtml: `<p>Se agrega la entrada a <code>${esc(check.manifest)}</code> y se llama a la API de
        ${audio ? 'ElevenLabs' : 'OpenAI'}, que <b>gasta créditos</b>.</p>
        <p>${audio ? `Modelo <b>${esc(form.type === 'musica' ? tpl.music_model : tpl.sfx_model)}</b>.`
          : `Modelo <b>${esc(tpl.image_model)}</b>, tamaño <b>${esc(form.f.size)}</b>, calidad <b>${esc(tpl.quality)}</b>.`}</p>`,
    });
    if (!ok) return;
    body.generate = true;
  }
  const result = await api(mode === 'preview' ? '/api/preview' : '/api/create', body);
  if (showErrors(result)) return;
  if (mode === 'preview') {
    const out = $('#create-preview');
    out.hidden = false;
    out.textContent = `Prompt final (lo que se enviaría; no gasta nada):\n\n${result.final_prompt}\n\n` +
      `Entrada que se agregaría a ${result.manifest}:\n\n${JSON.stringify(result.entry, null, 2)}`;
    out.scrollIntoView({ block: 'nearest' });
    return;
  }
  toast(`${result.entry.id} agregado a ${result.manifest}${mode === 'generate' ? '. Generando...' : ' como Sin generar.'}`);
  const kind = result.kind, id = result.entry.id;
  closeCreate();
  await onSaved(kind, id, result.job);
}

function showErrors(result) {
  const box = $('#create-errors');
  if (!result.error) { box.innerHTML = ''; return false; }
  box.innerHTML = `<div class="errors"><strong>${esc(result.error)}</strong>${result.errors?.length
    ? `<ul>${result.errors.map(e => `<li>${esc(e)}</li>`).join('')}</ul>` : ''}</div>`;
  box.scrollIntoView({ block: 'nearest' });
  return true;
}
