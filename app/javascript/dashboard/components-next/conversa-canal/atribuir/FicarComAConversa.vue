<script setup>
// #2067: a opção "ficar com a conversa ao enviar", em duas formas do protótipo.
// - chip (A): um ícone ao lado do Enviar; clicar alterna. A frase vai na dica.
// - linha (B): uma linha calma acima da barra, no estilo do aviso do WhatsApp API.
// Só aparece com algo para enviar; quem decide é a caixa de resposta.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  ficar: { type: Object, required: true },
  forma: {
    type: String,
    default: 'linha',
    validator: valor => ['chip', 'linha'].includes(valor),
  },
});

const { t } = useI18n();

const icone = computed(() =>
  props.ficar.ligada ? 'i-lucide-user-round-check' : 'i-lucide-user-round'
);
const acao = computed(() =>
  props.ficar.ligada
    ? t('CONVERSA_CANAL.FICAR.NAO_FICAR')
    : t('CONVERSA_CANAL.FICAR.FICAR_COM_ELA')
);
const dica = computed(() => {
  const clique = props.ficar.ligada
    ? t('CONVERSA_CANAL.FICAR.DICA_LIGADA')
    : t('CONVERSA_CANAL.FICAR.DICA_DESLIGADA');
  return `${props.ficar.frase}. ${clique}`;
});
</script>

<template>
  <button
    v-if="forma === 'chip'"
    v-tooltip.top-end="dica"
    type="button"
    role="switch"
    :aria-checked="ficar.ligada"
    :aria-label="dica"
    data-ficar-com-a-conversa
    class="grid flex-shrink-0 transition-colors rounded-full place-content-center size-9 me-1 self-center outline-none focus-visible:ring-2 focus-visible:ring-n-teal-8"
    :class="
      ficar.ligada
        ? 'bg-n-teal-3 text-n-teal-11 hover:bg-n-teal-4'
        : 'text-n-slate-10 hover:bg-n-alpha-2'
    "
    @click="ficar.alternar"
  >
    <span :class="icone" class="size-5" aria-hidden="true" />
  </button>
  <p
    v-else
    class="flex flex-wrap items-center gap-x-1.5 gap-y-0.5 mx-2 mb-2 text-xs text-n-slate-11"
    data-ficar-com-a-conversa
    aria-live="polite"
  >
    <span
      :class="[icone, ficar.ligada ? 'text-n-teal-11' : '']"
      class="size-3.5 flex-shrink-0"
      aria-hidden="true"
    />
    <span>{{ ficar.frase }}</span>
    <span class="text-n-slate-9" aria-hidden="true">·</span>
    <button
      type="button"
      class="px-1 -mx-1 py-1 -my-1 text-xs font-medium rounded outline-none text-n-blue-11 hover:underline focus-visible:ring-2 focus-visible:ring-n-blue-8"
      @click="ficar.alternar"
    >
      {{ acao }}
    </button>
  </p>
</template>
