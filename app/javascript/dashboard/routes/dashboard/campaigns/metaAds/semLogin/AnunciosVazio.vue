<script setup>
import { computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { SEM_LOGIN, phoneLabel } from './anunciosSemLogin';

// Anúncios sem login (#1960), tela "pronto": o WhatsApp oficial está pronto, mas ninguém veio de anúncio em 90
// dias. Diz que o resultado aparece aqui e oferece o exemplo. Quem já anuncia para fora do WhatsApp (site, perfil,
// vídeo) ou ainda vai começar conecta a conta de anúncios daqui mesmo (#2190); só quem pode configurar.
const props = defineProps({
  inboxes: { type: Array, default: () => [] },
  canConnect: { type: Boolean, default: false },
});

const emit = defineEmits(['example', 'connect']);

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
    class="flex flex-col items-start gap-4 rounded-2xl bg-n-solid-1 p-6 ring-1 ring-inset ring-n-weak sm:p-10"
  >
    <span
      aria-hidden="true"
      class="flex items-center justify-center rounded-xl size-12 bg-n-teal-3 text-n-teal-11"
    >
      <span class="i-lucide-message-circle size-6" />
    </span>
    <p
      data-ready-text
      class="m-0 max-w-2xl text-xl font-semibold leading-snug text-n-slate-12 sm:text-2xl"
    >
      {{ $t(`${SEM_LOGIN}.${readyText.key}`, readyText.values || {}) }}
    </p>
    <button
      type="button"
      data-see-example
      class="inline-flex min-h-11 items-center gap-2 rounded-xl border-0 bg-n-solid-1 px-4 text-sm font-medium text-n-slate-12 no-underline ring-1 ring-inset ring-n-weak transition hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
      @click="emit('example')"
    >
      <span class="i-lucide-eye size-4" aria-hidden="true" />
      {{ $t(`${SEM_LOGIN}.READY.EXAMPLE`) }}
    </button>
    <div
      v-if="canConnect"
      data-anuncios-vazio-conectar
      class="flex flex-col items-start gap-3 w-full pt-4 border-0 border-t border-solid border-n-weak"
    >
      <p class="m-0 max-w-2xl text-sm leading-6 text-n-slate-11">
        {{ $t(`${SEM_LOGIN}.READY.CONNECT_TEXT`) }}
      </p>
      <Button
        data-anuncios-vazio-conectar-botao
        class="!min-h-11 !rounded-xl"
        icon="i-lucide-plug"
        :label="$t(`${SEM_LOGIN}.READY.CONNECT_CTA`)"
        @click="emit('connect')"
      />
    </div>
  </section>
</template>
