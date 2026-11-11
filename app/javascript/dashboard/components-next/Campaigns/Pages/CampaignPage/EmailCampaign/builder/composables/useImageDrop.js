// Images and text dropped or pasted on the e-mail canvas (#2908).
//
// GrapesJS, by default, turns an external drop into loose HTML inside a column: a dropped photo became
// <img src="data:..."> outside any mj-image, never uploaded, lost on save. Here every external drop and
// every image paste is taken over: images are uploaded and enter as Image blocks, text enters as a Text
// block, both where they were dropped (above the locked footer at most). Nothing loose, nothing silent:
// uploads show "Enviando imagem…", failures say what to do (with "Tentar de novo" when retrying helps).
// Module singleton, like useEmailEditor: the canvas (GrapesEditor) attaches it, the page waits on it.
import { computed, ref, shallowRef } from 'vue';

import EmailCampaignAssetsAPI from 'dashboard/api/emailCampaignAssets';

import {
  anchorFor,
  blockOf,
  componentFromElement,
  imageAt,
  insertBlock,
  replaceImageSrc,
} from '../canvasInsert';
import {
  ImageFileError,
  TOO_LARGE,
  UNREADABLE,
  UNSUPPORTED,
  altFromFileName,
  isImageFile,
  prepareImageFile,
} from '../imageFile';
import { plainTextToHtml, sanitizePastedHtml } from '../pastedHtml';
import {
  imageSectionMjml,
  isPublicImageSrc,
  textSectionMjml,
} from '../sectionMarkup';

const uploadingCount = ref(0);
// { key, count?, retry? } — key under CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.IMAGE_DROP.
const notice = shallowRef(null);
const pending = new Set();
// Bumped when the canvas goes away: an upload that finishes after that touches nothing.
let generation = 0;

const isUploadingImages = computed(() => uploadingCount.value > 0);

const track = promise => {
  pending.add(promise);
  promise.finally(() => pending.delete(promise));
  return promise;
};

// Save, test send and subject saves wait for images still uploading (EmailBuilderPage persist).
export const waitForImageUploads = () => Promise.allSettled([...pending]);

const dismissNotice = () => {
  notice.value = null;
};

const errorCode = error =>
  error instanceof ImageFileError ? error.code : error?.response?.data?.error;

const REFUSED = {
  [TOO_LARGE]: 'TOO_LARGE',
  [UNSUPPORTED]: 'UNSUPPORTED',
  [UNREADABLE]: 'UNREADABLE',
};

// ---- upload ----

const uploadOne = async (file, campaignId) => {
  if (!campaignId) throw new Error('campaign not saved');
  const prepared = await prepareImageFile(file);
  const { data } = await EmailCampaignAssetsAPI.upload(campaignId, prepared);
  return data.url;
};

let uploadFiles;

const reportFailures = (failed, ctx) => {
  const retryable = failed.filter(({ error }) => !REFUSED[errorCode(error)]);
  if (retryable.length) {
    notice.value = {
      key: 'UPLOAD_FAILED',
      count: retryable.length,
      retry: () => {
        dismissNotice();
        uploadFiles(
          ctx.editor,
          retryable.map(({ file }) => file),
          ctx
        );
      },
    };
    return;
  }
  notice.value = { key: REFUSED[errorCode(failed[0].error)] };
};

// Puts one uploaded image on the canvas; returns where the next one goes.
const placeImage = (editor, url, file, { next, target }) => {
  if (target) {
    replaceImageSrc(target, url);
    return { next: anchorFor(target), target: null };
  }
  const alt = altFromFileName(file.name);
  return {
    next: insertBlock(editor, next, imageSectionMjml({ src: url, alt })),
    target: null,
  };
};

// Uploads in order; the first image replaces `replace` (an mj-image) when given, the others enter as
// Image blocks one after the other from `anchor`.
uploadFiles = (editor, files, { anchor, replace = null, getCampaignId }) => {
  uploadingCount.value += files.length;
  const startedIn = generation;
  const run = async () => {
    let place = { next: anchor, target: replace };
    const failed = [];
    // eslint-disable-next-line no-restricted-syntax
    for (const file of files) {
      try {
        // eslint-disable-next-line no-await-in-loop
        const url = await uploadOne(file, getCampaignId());
        // The editor may have been closed meanwhile: then there is nothing to insert into.
        if (startedIn === generation) {
          place = placeImage(editor, url, file, place);
        }
      } catch (error) {
        failed.push({ file, error });
      } finally {
        uploadingCount.value -= 1;
      }
    }
    if (failed.length && startedIn === generation) {
      reportFailures(failed, {
        editor,
        anchor: place.next,
        replace: place.target,
        getCampaignId,
      });
    }
  };
  return track(run());
};

// ---- images and text that came as HTML (paste from Word/Docs, drag from another site) ----

// Images with a public address enter as they are; the others become the "Clique para subir sua imagem"
// frame, with a notice saying so.
const insertImages = (editor, images, anchor, replace = null) => {
  let next = anchor;
  let target = replace;
  let missing = 0;
  images.forEach(image => {
    const isPublic = isPublicImageSrc(image.src);
    if (!isPublic) missing += 1;
    if (target && isPublic) {
      replaceImageSrc(target, image.src.trim());
      next = anchorFor(target);
      target = null;
      return;
    }
    next = insertBlock(editor, next, imageSectionMjml(image));
  });
  if (missing) notice.value = { key: 'MISSING_PUBLIC', count: missing };
  return next;
};

const insertHtml = (editor, html, anchor, replace) => {
  const { html: clean, images } = sanitizePastedHtml(html);
  const next = clean
    ? insertBlock(editor, anchor, textSectionMjml(clean))
    : anchor;
  insertImages(editor, images, next, clean ? null : replace);
};

// ---- drop ----

const readTransfer = dt => {
  if (!dt) return null;
  const files = Array.from(dt.files || []);
  if (files.length) return { files };
  const html = dt.getData('text/html');
  if (html) return { html };
  const text = dt.getData('text/plain') || dt.getData('text/uri-list');
  return text ? { text } : null;
};

const dropAnchor = (component, clientY) => {
  const rect = blockOf(component)?.getEl?.()?.getBoundingClientRect?.();
  const before = Boolean(rect) && clientY < rect.top + rect.height / 2;
  return anchorFor(component, { before });
};

export const handleDrop = (
  editor,
  { payload, component, clientY },
  getCampaignId
) => {
  const anchor = dropAnchor(component, clientY);
  const replace = component ? imageAt(component) : null;
  if (payload.files) {
    const images = payload.files.filter(isImageFile);
    if (images.length < payload.files.length) {
      notice.value = { key: 'ONLY_IMAGES' };
    }
    if (images.length) {
      uploadFiles(editor, images, { anchor, replace, getCampaignId });
    }
    return;
  }
  if (payload.html) {
    insertHtml(editor, payload.html, anchor, replace);
    return;
  }
  const html = plainTextToHtml(payload.text);
  if (html) insertBlock(editor, anchor, textSectionMjml(html));
};

// ---- paste ----

const isEditableTarget = target =>
  Boolean(
    target?.isContentEditable || target?.closest?.('[contenteditable="true"]')
  );

export const handlePaste = (editor, event, getCampaignId) => {
  const dt = event.clipboardData;
  if (!dt) return;
  const inText = isEditableTarget(event.target);
  const html = dt.getData('text/html');
  // Word and Excel also put a picture of the copied text on the clipboard: text wins over files.
  const cleaned = html ? sanitizePastedHtml(html) : { html: '', images: [] };
  const selected = editor.getEditing?.() || editor.getSelected?.();
  const anchor = anchorFor(selected);
  if (cleaned.html) {
    // Outside a text the paste belongs to GrapesJS (copy/paste of blocks).
    if (!inText) return;
    event.preventDefault();
    event.target.ownerDocument.execCommand('insertHTML', false, cleaned.html);
    if (cleaned.images.length) insertImages(editor, cleaned.images, anchor);
    return;
  }
  const files = Array.from(dt.files || []).filter(isImageFile);
  const replace = !inText && selected ? imageAt(selected) : null;
  if (files.length) {
    event.preventDefault();
    uploadFiles(editor, files, { anchor, replace, getCampaignId });
    return;
  }
  if (cleaned.images.length) {
    event.preventDefault();
    insertImages(editor, cleaned.images, anchor, replace);
  }
};

// ---- wiring ----

// The canvas owner calls this once per editor; returns the detach function.
export const attachImageDrop = (editor, getCampaignId) => {
  let lastDrop = null;
  let frameWindow = null;

  // Capture phase on the frame: runs before GrapesJS reads the drop, while the data is readable.
  const onDrop = event => {
    // A block dragged from our panel: GrapesJS places it.
    if (editor.getModel().get('dragSource')?.content) return;
    const payload = readTransfer(event.dataTransfer);
    if (!payload) return;
    lastDrop = {
      payload,
      component: componentFromElement(event.target),
      clientY: event.clientY,
    };
  };
  // GrapesJS asks what to drop: nothing (the drop is cancelled), we insert it ourselves.
  const onDragData = (_dt, result) => {
    if (!lastDrop) return;
    const drop = lastDrop;
    lastDrop = null;
    result.setContent('');
    setTimeout(() => handleDrop(editor, drop, getCampaignId));
  };
  const onPaste = event => handlePaste(editor, event, getCampaignId);

  const unbindFrame = () => {
    frameWindow?.removeEventListener('drop', onDrop, true);
    frameWindow?.removeEventListener('paste', onPaste, true);
  };
  const bindFrame = ({ window: loadedWindow } = {}) => {
    unbindFrame();
    frameWindow = loadedWindow || editor.Canvas.getWindow();
    frameWindow?.addEventListener('drop', onDrop, true);
    frameWindow?.addEventListener('paste', onPaste, true);
  };

  editor.on('canvas:dragdata', onDragData);
  editor.on('canvas:frame:load', bindFrame);
  if (editor.Canvas.getBody()) bindFrame();

  return () => {
    unbindFrame();
    editor.off('canvas:dragdata', onDragData);
    editor.off('canvas:frame:load', bindFrame);
    generation += 1;
    notice.value = null;
  };
};

export function useImageDrop() {
  return {
    uploadingCount,
    isUploadingImages,
    notice,
    dismissNotice,
    waitForImageUploads,
  };
}

export default useImageDrop;
