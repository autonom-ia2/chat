<script setup>
import { ref, computed, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { useAutoGrowTextarea } from '../../composables/useAutoGrowTextarea.js';
import { useFileDrop } from '../../composables/useFileDrop.js';

// The chat input, reused by the Builder, the Test sandbox and Tune.
//
// IDENTITY + STRUCTURE: one rounded container that mirrors Chatwoot's own
// ReplyBox shell (`border-n-weak rounded-xl bg-n-solid-1`) so it feels native,
// laid out like the composers people know (ChatGPT/Claude/Intercom): a single
// surface with the attach clip on the left, a seamless auto-grow field in the
// middle, and a clean send button on the right. The CONTAINER is the focus
// target (subtle `focus-within:border-n-slate-6`), never the field.
//
// CRITICAL FIX (PO "faixa azul"): Chatwoot ships a GLOBAL `textarea { @apply
// field-base h-16 }` rule (_base.scss) that forces a 64px height, a 1rem bottom
// margin, its own background, and a bright `focus:outline-n-brand` ring — that
// blue band on focus and the broken/tall box were that global leaking in. A
// plain `outline-none` loses to `textarea:focus` on specificity, so the field
// is neutralised with `!important` utilities (`!h-auto !m-0 !bg-transparent
// !outline-none focus:!outline-none ...`). This is contained to this component
// — no change to the shared SCSS, so nothing else regresses.
//
// Enter sends, Shift+Enter inserts a newline, IME composition is respected.
const props = defineProps({
  placeholder: {
    type: String,
    default: '',
  },
  disabled: {
    type: Boolean,
    default: false,
  },
  isSending: {
    type: Boolean,
    default: false,
  },
  // When true the clip is rendered. The builder keeps it on for the whole
  // conversation (like any messenger); other reuses (Test/Tune) leave it off.
  canAttach: {
    type: Boolean,
    default: false,
  },
  // True while an attached file is being uploaded — the clip shows a spinner.
  isAttaching: {
    type: Boolean,
    default: false,
  },
});

// MULTIMODAL: the clip now handles TWO kinds of attachment with different fates.
//  - DOCUMENTS (pdf/docx/xlsx/txt/md/json) → emit `attach` tagged as knowledge
//    so the parent reuses the Materiais pipeline (autonomiaSources/create).
//    This is the EXISTING behaviour, byte-for-byte unchanged.
//  - IMAGES (png/jpg/jpeg/gif/webp) → NOT knowledge (the BE rejects images as
//    sources). They are held as PENDING attachments of the NEXT message and
//    travel with `send` so the model reads them inline (multimodal input_image).
// `send` always carries `{ content, images }`; `images` is empty on the pure
// text path, so the three parent handlers stay backward-compatible.
const emit = defineEmits(['send', 'attach']);

const { t } = useI18n();

// Extensions the backend ingests as knowledge. Mirrors MaterialDropzone and the
// Source model allowlist. Reused as the allowlist for `useFileDrop.filterValid`.
const ACCEPTED = ['pdf', 'docx', 'xlsx', 'txt', 'md', 'json'];
// Image extensions read inline by the model (NOT knowledge). Mirrors the BE
// allowlist (EmailCampaigns::Ai::Generator::IMAGE_TYPES).
const IMAGE_EXT = ['png', 'jpg', 'jpeg', 'gif', 'webp'];
const ACCEPT_ATTR = [...ACCEPTED, ...IMAGE_EXT].map(ext => `.${ext}`).join(',');

// Image limits — single source of truth on the FE, mirrored by the BE.
const MAX_IMAGES = 4;
const MAX_IMAGE_BYTES = 5 * 1024 * 1024; // 5 MB

const draft = ref('');
const textareaRef = ref(null);
const fileInput = ref(null);
// Images staged for the next message: { file, name, previewUrl }.
const pendingImages = ref([]);

const { resize } = useAutoGrowTextarea(textareaRef, draft);
// Reuse the dropzone's extension filter for the native picker so attaching docs
// by click validates the same way as drag-and-drop.
const { filterValid } = useFileDrop(() => {}, ACCEPTED);

const extOf = name => (name.split('.').pop() || '').toLowerCase();
const isImageFile = file => IMAGE_EXT.includes(extOf(file.name || ''));

// A message can be sent with text alone, or text + images. The BE always
// requires text (an image accompanies a message), so text remains mandatory.
const canSend = computed(
  () => draft.value.trim() && !props.isSending && !props.disabled
);

// Stage valid images as pending; warn (and skip) on type/size/quantity breach.
const addPendingImages = files => {
  let overflow = false;
  files.forEach(file => {
    if (!isImageFile(file)) {
      useAlert(t('AGENTS.BUILDER.ATTACH.IMAGE_INVALID_TYPE'));
    } else if (file.size > MAX_IMAGE_BYTES) {
      useAlert(t('AGENTS.BUILDER.ATTACH.IMAGE_TOO_LARGE'));
    } else if (pendingImages.value.length >= MAX_IMAGES) {
      overflow = true;
    } else {
      pendingImages.value.push({
        file,
        name: file.name,
        previewUrl: URL.createObjectURL(file),
      });
    }
  });
  // Warn once if the cap dropped one or more images, not per skipped file.
  if (overflow) useAlert(t('AGENTS.BUILDER.ATTACH.IMAGE_TOO_MANY'));
};

const removePendingImage = index => {
  const [removed] = pendingImages.value.splice(index, 1);
  if (removed?.previewUrl) URL.revokeObjectURL(removed.previewUrl);
};

const clearPendingImages = () => {
  pendingImages.value.forEach(image => {
    if (image.previewUrl) URL.revokeObjectURL(image.previewUrl);
  });
  pendingImages.value = [];
};

const send = () => {
  if (!canSend.value) return;
  const content = draft.value.trim();
  const images = pendingImages.value.map(image => image.file);
  draft.value = '';
  // Force the field back to its single-row height immediately on send.
  if (textareaRef.value) textareaRef.value.style.height = 'auto';
  resize();
  // The chips own the object URLs; clear (and revoke) them after handing the
  // File[] to the parent, which reads them independently.
  pendingImages.value = [];
  emit('send', { content, images });
};

// #1427 — the parent hands back what was typed when the server refused the
// photo sent with it, so it can go again with another photo. Never overwrites a
// new draft.
const restoreDraft = text => {
  if (text && !draft.value) draft.value = text;
};

defineExpose({ restoreDraft });

const onEnter = event => {
  // Shift+Enter (newline) and IME composition must never send.
  if (event.shiftKey || event.isComposing) return;
  event.preventDefault();
  send();
};

const openPicker = () => {
  if (props.isAttaching || props.disabled) return;
  fileInput.value?.click();
};

const onPicked = event => {
  const all = Array.from(event.target.files || []);
  // Documents follow the existing knowledge path; images are staged inline.
  const docs = filterValid(all);
  const images = all.filter(isImageFile);
  if (docs.length) emit('attach', { files: docs, kind: 'knowledge' });
  if (images.length) addPendingImages(images);
  // Nothing usable picked (neither a valid doc nor an image): nudge the user.
  if (!docs.length && !images.length && all.length) {
    useAlert(t('AGENTS.BUILDER.ATTACH.INVALID_EXT'));
  }
  // Reset so picking the same file again re-fires `change`.
  if (fileInput.value) fileInput.value.value = '';
};

// Revoke any outstanding object URLs if the composer is torn down mid-draft.
onBeforeUnmount(clearPendingImages);
</script>

<template>
  <div class="flex flex-col gap-1.5">
    <!-- PENDING IMAGES — removable chips for the next message (read inline). -->
    <div
      v-if="pendingImages.length"
      class="flex flex-wrap gap-2"
      :aria-label="t('AGENTS.BUILDER.ATTACH.IMAGE_PENDING')"
    >
      <div
        v-for="(image, index) in pendingImages"
        :key="index"
        class="relative flex items-center gap-2 py-1 pl-1 pr-2 border rounded-lg bg-n-solid-1 border-n-weak"
      >
        <img
          :src="image.previewUrl"
          :alt="image.name"
          class="object-cover rounded size-8"
        />
        <span class="text-xs max-w-32 truncate text-n-slate-11">
          {{ image.name }}
        </span>
        <button
          type="button"
          :aria-label="t('AGENTS.BUILDER.ATTACH.IMAGE_REMOVE')"
          :title="t('AGENTS.BUILDER.ATTACH.IMAGE_REMOVE')"
          class="flex items-center justify-center transition-colors rounded outline-none size-5 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 focus-visible:outline-1 focus-visible:outline focus-visible:outline-n-brand"
          @click="removePendingImage(index)"
        >
          <i class="i-lucide-x size-3.5" />
        </button>
      </div>
    </div>

    <div
      class="flex items-end gap-1 p-1.5 border shadow-sm rounded-xl bg-n-solid-1 border-n-weak transition-colors focus-within:border-n-slate-6"
    >
      <!-- ATTACH (clip) — bottom-left, opens the picker directly. -->
      <button
        v-if="canAttach"
        type="button"
        :disabled="isAttaching || disabled"
        :aria-label="t('AGENTS.BUILDER.ATTACH.LABEL')"
        :title="t('AGENTS.BUILDER.ATTACH.LABEL')"
        class="flex items-center justify-center transition-colors rounded-lg outline-none shrink-0 size-9 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 focus-visible:outline-1 focus-visible:outline focus-visible:outline-n-brand disabled:opacity-50 disabled:cursor-not-allowed"
        @click="openPicker"
      >
        <Spinner v-if="isAttaching" :size="18" />
        <i v-else class="i-lucide-paperclip size-[18px]" />
      </button>

      <input
        v-if="canAttach"
        ref="fileInput"
        type="file"
        multiple
        class="hidden"
        :accept="ACCEPT_ATTR"
        @change="onPicked"
      />

      <!-- AUTO-GROW field. Fully neutralises the global `textarea` style so the
         container owns the look (no blue ring, no forced height/margin/bg). -->
      <textarea
        ref="textareaRef"
        v-model="draft"
        rows="1"
        :disabled="disabled"
        :placeholder="placeholder || t('AGENTS.BUILDER.PLACEHOLDER')"
        :aria-label="placeholder || t('AGENTS.BUILDER.PLACEHOLDER')"
        class="flex-1 text-sm leading-6 resize-none text-n-slate-12 placeholder:text-n-slate-10 disabled:opacity-50 min-h-[2.5rem] max-h-40 !m-0 !h-auto !px-2 !py-2 !border-0 !rounded-none !bg-transparent !shadow-none !outline-none focus:!outline-none"
        @keydown.enter="onEnter"
      />

      <!-- SEND — bottom-right, clean brand button (up-arrow, modern composer). -->
      <button
        type="button"
        :disabled="!canSend"
        :aria-label="t('AGENTS.BUILDER.SEND')"
        :title="t('AGENTS.BUILDER.SEND')"
        class="flex items-center justify-center transition rounded-lg outline-none shrink-0 size-9 bg-n-brand text-white hover:enabled:brightness-110 focus-visible:outline-1 focus-visible:outline focus-visible:outline-n-brand disabled:opacity-40 disabled:cursor-not-allowed"
        @click="send"
      >
        <Spinner v-if="isSending" :size="18" class="text-white" />
        <i v-else class="i-lucide-arrow-up size-5" />
      </button>
    </div>
  </div>
</template>
