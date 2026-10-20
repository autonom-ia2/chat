<script setup>
import { computed } from 'vue';
import { SEM_LOGIN, phoneLabel } from './anunciosSemLogin';

// Anúncios sem login (#1960), tela "pronto": o WhatsApp oficial está pronto, mas ninguém veio de anúncio em 90
// dias. Diz que o resultado aparece aqui e oferece o exemplo.
const props = defineProps({
  inboxes: { type: Array, default: () => [] },
});

const emit = defineEmits(['example']);

const phone = computed(() =>
  props.inboxes.length === 1 ? phoneLabel(props.inboxes[0].phone) : null
);

const readyText = computed(() => {
  if (props.inboxes.length > 1) return { key: 'READY.TEXT_MANY' };
  if (phone.value) {
    return { key: 'READY.TEXT_PHONE', values: { phone: phone.value } };
  }
  return { key: 'READY.TEXT' };
});
</script>

<template>
  <section
    data-anuncios-vazio
    class="flex flex-col items-start gap-4 p-6 border border-solid shadow-sm rounded-3xl border-n-weak bg-n-solid-1 sm:p-10"
  >
    <span
      aria-hidden="true"
      class="flex items-center justify-center rounded-2xl size-12 bg-n-teal-3 text-n-teal-11"
    >
      <span class="i-lucide-message-circle size-6" />
    </span>
    <p
      data-ready-text
      class="m-0 max-w-2xl font-interDisplay text-xl font-520 leading-snug tracking-[-0.01em] text-n-slate-12 sm:text-2xl"
    >
      {{ $t(`${SEM_LOGIN}.${readyText.key}`, readyText.values || {}) }}
    </p>
    <button
      type="button"
      data-see-example
      class="inline-flex items-center gap-2 px-5 text-sm border border-solid rounded-xl min-h-11 font-520 border-n-weak bg-n-solid-1 text-n-slate-12 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
      @click="emit('example')"
    >
      <span class="i-lucide-eye size-4" aria-hidden="true" />
      {{ $t(`${SEM_LOGIN}.READY.EXAMPLE`) }}
    </button>
  </section>
</template>
