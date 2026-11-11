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

// A stalled upload would hold save, test send and review (they wait for it): it fails instead, with
// "Tentar de novo". Generous for a 10 MB file on a slow connection; reduced photos take seconds.
export const UPLOAD_TIMEOUT_MS = 90 * 1000;

const uploadOne = async (file, campaignId) => {
  if (!campaignId) throw new Error('campaign not saved');
  const prepared = await prepareImageFile(file);
  const { data } = await EmailCampaignAssetsAPI.upload(campaignId, prepared, {
    timeout: UPLOAD_TIMEOUT_MS,
  });
  return data.url;
};

const sameAnchor = (a, b) =>
  Boolean(a && b) && a.block === b.block && a.after === b.after;

let uploadFiles;

// Each failed file keeps where it was going (its anchor, or the image it was replacing), so a retry
// puts it back in its place, not at the end.
const reportFailures = (editor, failed, campaignId) => {
  const retryable = failed.filter(({ error }) => !REFUSED[errorCode(error)]);
  if (!retryable.length) {
    notice.value = { key: REFUSED[errorCode(failed[0].error)] };
    return;
  }
  notice.value = {
    key: 'UPLOAD_FAILED',
    count: retryable.length,
    retry: () => {
      dismissNotice();
      uploadFiles(
        editor,
        retryable.map(({ file, anchor, replace }) => ({
          file,
          anchor,
          replace,
        })),
        { campaignId }
      );
    },
  };
};

// Puts one uploaded image on the canvas; returns where the next one goes.
const placeImage = (editor, url, file, { next, target }) => {
  if (target) {
    replaceImageSrc(target, url);
    return anchorFor(target);
  }
  const alt = altFromFileName(file.name);
  return insertBlock(editor, next, imageSectionMjml({ src: url, alt }));
};

// Where this item goes: its own recorded place, or right after the previous item of the same place.
const itemPlace = (item, previous, next) => {
  if (item.replace) return { target: item.replace, next };
  if (item.anchor && !sameAnchor(item.anchor, previous?.anchor)) {
    return { target: null, next: item.anchor };
  }
  return { target: null, next };
};

// items: [{ file, anchor?, replace? }] in order. Only the first item of a drop carries the anchor (or the
// image to replace); the others follow it. The campaign is read once, when the upload starts.
uploadFiles = (editor, items, { campaignId }) => {
  uploadingCount.value += items.length;
  const startedIn = generation;
  const run = async () => {
    let next = items[0]?.anchor || anchorFor(null);
    let previous = null;
    const failed = [];
    // eslint-disable-next-line no-restricted-syntax
    for (const item of items) {
      const place = itemPlace(item, previous, next);
      previous = item;
      try {
        // eslint-disable-next-line no-await-in-loop
        const url = await uploadOne(item.file, campaignId);
        // The editor may have been closed meanwhile: then there is nothing to insert into.
        if (startedIn === generation) {
          next = placeImage(editor, url, item.file, place);
        }
      } catch (error) {
        failed.push({
          file: item.file,
          error,
          replace: place.target,
          anchor: place.target ? null : place.next,
        });
        next = place.target ? anchorFor(place.target) : place.next;
      } finally {
        uploadingCount.value -= 1;
      }
    }
    if (failed.length && startedIn === generation) {
      reportFailures(editor, failed, campaignId);
    }
  };
  return track(run());
};

const dropItems = (files, { anchor, replace = null }) =>
  files.map((file, index) =>
    index === 0 ? { file, anchor, replace } : { file }
  );

// ---- pasted/dropped HTML: text and images in the order they came ----

// Images with a public address enter as they are; the others become the "Clique para subir sua imagem"
// frame, with a notice saying so. `replace` (an image dropped on) only takes a lone public image.
const insertSegments = (editor, segments, anchor, replace = null) => {
  const lonePublicImage =
    segments.length === 1 &&
    segments[0].type === 'image' &&
    isPublicImageSrc(segments[0].src);
  if (replace && lonePublicImage) {
    replaceImageSrc(replace, segments[0].src.trim());
    return;
  }
  let next = anchor;
  let missing = 0;
  segments.forEach(segment => {
    if (segment.type === 'text') {
      next = insertBlock(editor, next, textSectionMjml(segment.html));
      return;
    }
    if (!isPublicImageSrc(segment.src)) missing += 1;
    next = insertBlock(editor, next, imageSectionMjml(segment));
  });
  if (missing) notice.value = { key: 'MISSING_PUBLIC', count: missing };
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
  campaignId
) => {
  const anchor = dropAnchor(component, clientY);
  // Dropping on an image replaces it: the person aimed at that picture.
  const replace = component ? imageAt(component) : null;
  if (payload.files) {
    const images = payload.files.filter(isImageFile);
    if (images.length < payload.files.length) {
      notice.value = { key: 'ONLY_IMAGES' };
    }
    if (images.length) {
      uploadFiles(editor, dropItems(images, { anchor, replace }), {
        campaignId,
      });
    }
    return;
  }
  if (payload.html) {
    insertSegments(
      editor,
      sanitizePastedHtml(payload.html).segments,
      anchor,
      replace
    );
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

// GrapesJS pastes its own copied blocks (core:paste reads only its internal clipboard) when something
// is selected; then the system clipboard is not ours to insert.
const grapesPastesBlocks = editor =>
  Boolean(editor.getModel().get('clipboard')?.length && editor.getSelected());

const pasteInText = (editor, event, segments, anchor) => {
  event.preventDefault();
  const [first, ...rest] = segments;
  // The text before the first image goes where the cursor is; what follows enters as blocks, in order.
  if (first.type === 'text') {
    event.target.ownerDocument.execCommand('insertHTML', false, first.html);
    insertSegments(editor, rest, anchor);
  } else {
    insertSegments(editor, segments, anchor);
  }
};

// A paste never replaces an image: it goes below the selected block (replacing is for a drop aimed
// at the image).
export const handlePaste = (editor, event, campaignId) => {
  const dt = event.clipboardData;
  if (!dt) return;
  const inText = isEditableTarget(event.target);
  const html = dt.getData('text/html');
  // Word and Excel also put a picture of the copied text on the clipboard: text wins over files.
  const cleaned = html
    ? sanitizePastedHtml(html)
    : { html: '', segments: [], images: [] };
  const anchor = anchorFor(editor.getEditing?.() || editor.getSelected?.());
  if (cleaned.html && inText) {
    pasteInText(editor, event, cleaned.segments, anchor);
    return;
  }
  if (cleaned.html) {
    // Outside a text, a text paste is ours only when GrapesJS is not pasting copied blocks.
    if (grapesPastesBlocks(editor)) return;
    event.preventDefault();
    insertSegments(editor, cleaned.segments, anchor);
    return;
  }
  const files = Array.from(dt.files || []).filter(isImageFile);
  if (files.length) {
    event.preventDefault();
    uploadFiles(editor, dropItems(files, { anchor }), { campaignId });
    return;
  }
  if (cleaned.segments.length) {
    event.preventDefault();
    insertSegments(editor, cleaned.segments, anchor);
  }
};

// ---- wiring ----

// The canvas owner calls this once per editor; returns the detach function.
export const attachImageDrop = (editor, getCampaignId) => {
  let lastDrop = null;
  let frameWindow = null;
  // A drag that started inside the canvas (moving selected text): never a new block.
  let dragFromFrame = false;
  const attachedIn = generation;
  const isAlive = () => attachedIn === generation;

  const onDragStart = () => {
    dragFromFrame = true;
  };
  const onDragEnd = () => {
    dragFromFrame = false;
  };
  // Capture phase on the frame: runs before GrapesJS reads the drop, while the data is readable.
  const onDrop = event => {
    lastDrop = null;
    // A block dragged from our panel: GrapesJS places it.
    if (editor.getModel().get('dragSource')?.content) return;
    if (dragFromFrame) {
      dragFromFrame = false;
      lastDrop = { ignore: true };
      return;
    }
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
    const drop = lastDrop;
    lastDrop = null;
    if (!drop || !isAlive()) return;
    if (editor.getModel().get('dragSource')?.content) return;
    result.setContent('');
    if (drop.ignore) return;
    const campaignId = getCampaignId();
    setTimeout(() => {
      if (isAlive()) handleDrop(editor, drop, campaignId);
    });
  };
  const onPaste = event => handlePaste(editor, event, getCampaignId());

  const LISTENERS = [
    ['dragstart', onDragStart],
    ['dragend', onDragEnd],
    ['drop', onDrop],
    ['paste', onPaste],
  ];
  const unbindFrame = () => {
    LISTENERS.forEach(([name, fn]) =>
      frameWindow?.removeEventListener(name, fn, true)
    );
  };
  const bindFrame = ({ window: loadedWindow } = {}) => {
    unbindFrame();
    frameWindow = loadedWindow || editor.Canvas.getWindow();
    LISTENERS.forEach(([name, fn]) =>
      frameWindow?.addEventListener(name, fn, true)
    );
  };

  editor.on('canvas:dragdata', onDragData);
  editor.on('canvas:frame:load', bindFrame);
  if (editor.Canvas.getBody()) bindFrame();

  return () => {
    unbindFrame();
    lastDrop = null;
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
