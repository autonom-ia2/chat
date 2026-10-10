<script setup>
import { computed, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { IMAGE_TYPES } from '../constants';

// Enviar logo ou foto, com a prévia da imagem já salva. A conferência de tipo e
// tamanho é de quem usa (o assistente), que mostra o aviso em `error`.
const props = defineProps({
  label: { type: String, required: true },
  alt: { type: String, required: true },
  url: { type: String, default: '' },
  busy: { type: Boolean, default: false },
  error: { type: String, default: '' },
  round: { type: Boolean, default: false },
});

const emit = defineEmits(['pick']);
const { t } = useI18n();
const input = useTemplateRef('input');

const actionLabel = computed(() =>
  props.url ? t('BOOKING.LOOK.CHANGE') : t('BOOKING.LOOK.UPLOAD')
);

const onFile = event => {
  const [file] = event.target.files || [];
  // Limpa para o mesmo arquivo poder ser escolhido de novo depois de um erro.
  event.target.value = '';
  if (file) emit('pick', file);
};
</script>

<template>
  <div
    class="flex flex-col gap-3 p-4 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
  >
    <p class="m-0 text-base font-semibold text-n-slate-12">{{ label }}</p>
    <div class="flex items-center gap-4">
      <span
        class="grid place-items-center overflow-hidden size-20 shrink-0 bg-n-alpha-2"
        :class="round ? 'rounded-full' : 'rounded-xl'"
      >
        <img v-if="url" :src="url" :alt="alt" class="size-full object-cover" />
        <span
          v-else
          class="i-lucide-image size-7 text-n-slate-10"
          aria-hidden="true"
        />
      </span>
      <div class="flex flex-col gap-2">
        <button
          type="button"
          data-upload
          :disabled="busy"
          :aria-label="`${label}: ${actionLabel}`"
          class="inline-flex items-center gap-2 min-h-11 px-4 rounded-xl text-base font-medium text-n-slate-12 bg-n-solid-1 ring-1 ring-inset ring-n-weak hover:ring-n-blue-7 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:opacity-60"
          @click="input?.click()"
        >
          <span
            class="size-4"
            :class="
              busy ? 'i-lucide-loader-circle animate-spin' : 'i-lucide-upload'
            "
            aria-hidden="true"
          />
          {{ busy ? t('BOOKING.LOOK.UPLOADING') : actionLabel }}
        </button>
        <p class="m-0 text-sm text-n-slate-11">
          {{ t('BOOKING.LOOK.IMAGE_HINT') }}
        </p>
      </div>
    </div>
    <input
      ref="input"
      data-file
      type="file"
      :accept="IMAGE_TYPES.join(',')"
      class="hidden"
      @change="onFile"
    />
    <p v-if="error" role="alert" class="m-0 text-base text-n-ruby-11">
      {{ error }}
    </p>
  </div>
</template>
