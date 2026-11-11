// A file being dragged over the editor page or its canvas (#2908): shows the "Solte a imagem" area.
// dragenter/dragleave flicker between child elements and do not cross into the canvas frame, so the
// state follows dragover instead (the browser repeats it every few ms while the pointer is over a
// target) and ends a moment after the last one, or at once on drop.
import { ref } from 'vue';

export const DRAG_IDLE_MS = 250;

export const fileDragActive = ref(false);
let idleTimer = null;

export const hasFiles = dt => Array.from(dt?.types || []).includes('Files');

export const endFileDrag = () => {
  clearTimeout(idleTimer);
  fileDragActive.value = false;
};

export const noteFileDrag = dt => {
  if (!hasFiles(dt)) return;
  fileDragActive.value = true;
  clearTimeout(idleTimer);
  idleTimer = setTimeout(endFileDrag, DRAG_IDLE_MS);
};
