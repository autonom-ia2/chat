<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFileDrop } from '../../composables/useFileDrop';

// Drag-and-drop tile for one materials group (saber|enviar). Drop files onto it
// or click to open the native picker. Validates extensions and emits the valid
// File[] to the parent, which owns the upload. Tokens adapt to light/dark.
const props = defineProps({
  kind: {
    type: String,
    default: 'knowledge',
    validator: value => ['knowledge', 'media'].includes(value),
  },
  disabled: {
    type: Boolean,
    default: false,
  },
  // Slim horizontal variant used once materials exist (an unobtrusive "add more"
  // affordance above the list). The full centered tile is the empty-state hero.
  compact: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['files']);

const { t } = useI18n();

const ACCEPTED = ['pdf', 'docx', 'xlsx', 'txt', 'md', 'json'];
const ACCEPT_ATTR = ACCEPTED.map(ext => `.${ext}`).join(',');

const fileInput = ref(null);

const onValidFiles = files => emit('files', files);
const { isDragging, bind, filterValid } = useFileDrop(onValidFiles, ACCEPTED);

const openPicker = () => {
  if (props.disabled) return;
  fileInput.value?.click();
};

const onPicked = event => {
  const valid = filterValid(event.target.files);
  if (valid.length) emit('files', valid);
  // Reset so picking the same file again re-fires `change`.
  if (fileInput.value) fileInput.value.value = '';
};

const onKeydown = event => {
  if (event.key === 'Enter' || event.key === ' ') {
    event.preventDefault();
    openPicker();
  }
};

const formatsHint = computed(() => ACCEPTED.join(', ').toUpperCase());

// Announce which group (saber|enviar) this dropzone feeds so the picker is
// unambiguous to screen readers when both tabs are present.
const dropLabel = computed(() => {
  const group =
    props.kind === 'media'
      ? t('AGENTS.MATERIALS.TABS.MEDIA')
      : t('AGENTS.MATERIALS.TABS.KNOWLEDGE');
  return `${t('AGENTS.MATERIALS.DROP_HINT')} — ${group}`;
});
</script>

<template>
  <div
    role="button"
    tabindex="0"
    :aria-label="dropLabel"
    :aria-disabled="disabled"
    class="transition-colors border border-dashed cursor-pointer rounded-xl outline-none focus-visible:outline-1 focus-visible:outline focus-visible:outline-n-brand"
    :class="[
      compact
        ? 'flex items-center gap-3 px-4 py-3 text-left'
        : 'flex flex-col items-center justify-center gap-2 px-6 py-8 text-center',
      isDragging
        ? 'border-n-brand bg-n-alpha-1'
        : 'border-n-weak bg-n-alpha-black2 hover:border-n-slate-6',
      { 'cursor-not-allowed opacity-50': disabled },
    ]"
    v-bind="bind"
    @click="openPicker"
    @keydown="onKeydown"
  >
    <span
      class="flex items-center justify-center rounded-full shrink-0 bg-n-alpha-2 text-n-slate-11"
      :class="compact ? 'size-8' : 'size-10'"
    >
      <i class="i-lucide-upload-cloud" :class="compact ? 'size-4' : 'size-5'" />
    </span>
    <div :class="compact ? 'flex flex-col min-w-0' : 'contents'">
      <p
        class="font-medium text-n-slate-12"
        :class="compact ? 'text-xs' : 'text-sm'"
      >
        {{ t('AGENTS.MATERIALS.DROP_HINT') }}
      </p>
      <p class="text-xs truncate text-n-slate-11">{{ formatsHint }}</p>
    </div>
    <input
      ref="fileInput"
      type="file"
      multiple
      class="hidden"
      :accept="ACCEPT_ATTR"
      :disabled="disabled"
      @change="onPicked"
    />
  </div>
</template>
