<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFormato } from '../card/useFormato';

// #2710, variante 2 — no quadro, o selo do card que a página de agendamento criou para quem já comprou: "Já é
// cliente desde 3 de novembro" (o `customer_since` do contato). Fica no lugar do selo "Cliente" só nesse card. É um
// botão: abre o card ganho. O clique não abre o card de baixo.
const props = defineProps({
  // `customer_since` do contato, em segundos (como vem no card); pode faltar.
  desde: { type: Number, default: null },
  ocupado: { type: Boolean, default: false },
});

const emit = defineEmits(['abrir']);

const { t, locale } = useI18n();
const formato = useFormato({ t, locale });
const texto = computed(() =>
  props.desde
    ? t('AUTOMACAO_NO_CRM.CLIENTE.SELO', {
        dia: formato.diaCurto(new Date(props.desde * 1000)),
      })
    : t('AUTOMACAO_NO_CRM.CLIENTE.SELO_SEM_DATA')
);
const rotulo = computed(() =>
  t('AUTOMACAO_NO_CRM.CLIENTE.SELO_ROTULO', { selo: texto.value })
);
</script>

<template>
  <button
    type="button"
    data-selo-ja-cliente
    class="group/selo inline-flex min-h-11 w-fit max-w-full items-center rounded-full text-start focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:cursor-wait"
    :aria-label="rotulo"
    :aria-busy="ocupado"
    :disabled="ocupado"
    @click.stop="emit('abrir')"
  >
    <span
      class="inline-flex max-w-full items-center gap-1.5 rounded-full bg-n-teal-3 px-2.5 py-1 text-xs font-medium leading-5 text-n-teal-11 ring-1 ring-inset ring-n-teal-7 transition group-hover/selo:bg-n-teal-4"
    >
      <span class="i-lucide-badge-check size-3.5 shrink-0" aria-hidden="true" />
      <span class="truncate">{{ texto }}</span>
      <span
        class="i-lucide-chevron-right size-3.5 shrink-0 rtl:rotate-180"
        aria-hidden="true"
      />
    </span>
  </button>
</template>
