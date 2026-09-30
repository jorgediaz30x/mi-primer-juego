// Punto de entrada: pestañas, búsqueda, rutas (#imagenes, #imagenes/<id>, #audio) y atajos.

import { $, ui, initLog, onJobDone, resumeJob } from './shared.js';
import * as images from './images.js';
import * as audio from './audio.js';
import { openCreate, closeCreate, isOpen as createOpen } from './create.js';

function showTab(name) {
  document.querySelectorAll('.tab').forEach(t => t.classList.toggle('active', t.dataset.tab === name));
  $('#tab-imagenes').hidden = name !== 'imagenes';
  $('#tab-audio').hidden = name !== 'audio';
  if (name === 'imagenes') images.render(); else { images.closeDetail(); audio.render(); }
  if (name !== 'audio') audio.stopAudio();
}

/** La dirección manda: así puedes compartir o recargar un enlace a un asset concreto. */
function route() {
  closeCreate();                                 // cambiar de pestaña o de asset cierra el formulario
  const [tab, id] = location.hash.replace('#', '').split('/');
  showTab(tab === 'audio' ? 'audio' : 'imagenes');
  if (tab !== 'audio' && id) images.openDetail(decodeURIComponent(id));
  else images.closeDetail();
}

document.querySelectorAll('.tab').forEach(t => t.addEventListener('click', () => { location.hash = `#${t.dataset.tab}`; }));
window.addEventListener('hashchange', route);
$('#detail-backdrop').addEventListener('click', () => { closeCreate(); images.closeDetail(); });

// "Crear nuevo": en la pestaña Audio empieza con un efecto de sonido; en Imágenes, con un personaje.
$('#create-open').addEventListener('click', () => openCreate({
  audio: !$('#tab-audio').hidden,
  saved: async (kind, id, startedJob) => {
    await Promise.all([images.load(), audio.load()]);
    if (kind === 'image') location.hash = `#imagenes/${id}`;
    else { location.hash = '#audio'; audio.expand(id); }
    if (startedJob) resumeJob();                 // el servidor ya la inició: seguimos su registro
  },
}));

$('#search').addEventListener('input', event => {
  ui.search = event.target.value.trim();
  $('#tab-audio').hidden ? images.render() : audio.render();
});

document.addEventListener('keydown', event => {
  if (createOpen()) { if (event.key === 'Escape' && !$('#confirm').open) closeCreate(); return; }
  if (images.handleKey(event)) { event.preventDefault(); return; }
  const typing = /TEXTAREA|INPUT/.test(document.activeElement?.tagName);
  if (event.key === '/' && !typing) { event.preventDefault(); $('#search').focus(); }
});

// Al terminar una generación real, se recarga la lista de esa pestaña (con ?v= nuevo en las URLs).
onJobDone(finished => {
  if (finished.dry_run) return;
  (finished.kind === 'image' ? images.load() : audio.load());
});

initLog();
await Promise.all([images.load(), audio.load()]);
route();
resumeJob();
