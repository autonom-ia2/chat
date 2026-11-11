// Files dropped on the editor page outside the canvas (#2908): side menu, blocks and properties panels,
// header, or the "Como você quer começar?" screen. Left alone, the browser opens the photo in place of
// the panel and the person leaves the editor, losing what was not saved. While the page is on screen
// the browser never opens a dropped file: with the editor open an image goes to the end of the e-mail
// (above the locked footer); before the person chose how to start, a notice says what to do first.
// The canvas frame is a separate document: drops there are handled by useImageDrop.
import { onActivated, onBeforeUnmount, onDeactivated, onMounted } from 'vue';

import { endFileDrag, hasFiles, noteFileDrag } from './fileDragState';
import { dropFilesAtEnd } from './useImageDrop';

// isEditorOpen(): the canvas is on screen; onNotReady(): the notice for the screen before it.
export const createPageFileDrop = ({
  target = document,
  isEditorOpen,
  onNotReady,
}) => {
  const onDragOver = event => {
    if (!hasFiles(event.dataTransfer)) return;
    event.preventDefault();
    if (isEditorOpen()) noteFileDrag(event.dataTransfer);
  };
  const onDrop = event => {
    if (!hasFiles(event.dataTransfer)) return;
    // Another drop area of the page already took it.
    const handled = event.defaultPrevented;
    event.preventDefault();
    endFileDrag();
    if (handled) return;
    const files = Array.from(event.dataTransfer.files || []);
    if (!files.length) return;
    if (!isEditorOpen() || !dropFilesAtEnd(files)) onNotReady();
  };
  const detach = () => {
    target.removeEventListener('dragover', onDragOver);
    target.removeEventListener('drop', onDrop);
    endFileDrag();
  };
  const attach = () => {
    detach();
    target.addEventListener('dragover', onDragOver);
    target.addEventListener('drop', onDrop);
  };
  return { attach, detach };
};

// The editor page lives in keep-alive (CampaignsPageRouteView): listening only while it is shown.
export function usePageFileDrop(options) {
  const pageDrop = createPageFileDrop(options);
  onMounted(pageDrop.attach);
  onActivated(pageDrop.attach);
  onDeactivated(pageDrop.detach);
  onBeforeUnmount(pageDrop.detach);
  return pageDrop;
}

export default usePageFileDrop;
