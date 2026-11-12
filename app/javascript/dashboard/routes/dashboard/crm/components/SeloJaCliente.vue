<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFormato } from './card/useFormato';

// #2710, variante 2 — no quadro, o selo do card que a página de agendamento criou para quem já comprou: "Já é cliente
// desde 3 de novembro". Fica no lugar do selo "Cliente" só nesse card. É um botão: abre o card ganho (a compra). O clique
// não abre o card de baixo. O servidor só manda o selo para quem pode ver o card ganho (Crm::Cards::JaECliente).
const props = defineProps({
  // Em segundos, como as outras datas do quadro; pode faltar.
  desde: { type: Number, default: null },
});

const emit = defineEmits(['abrir']);

const { t, locale } = useI18n();
const formato = useFormato({ t, locale });
const texto = computed(() =>
  props.desde
    ? t('CRM_CARD.JA_CLIENTE.SELO', {
        dia: formato.diaCurto(new Date(props.desde * 1000)),
      })
    : t('CRM_CARD.JA_CLIENTE.SELO_SEM_DATA')
);
const rotulo = computed(() =>
  t('CRM_CARD.JA_CLIENTE.SELO_ROTULO', { selo: texto.value })
);
</script>

<template>
  <button
    type="button"
    data-selo-ja-cliente
    class="group/selo inline-flex min-h-11 w-fit max-w-full items-center rounded-full text-start focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
    :aria-label="rotulo"
    @click.stop="emit('abrir')"
  >
    <span
      class="inline-flex max-w-full items-center gap-1.5 rounded-2xl bg-n-teal-3 px-2.5 py-1 text-xs font-medium leading-5 text-n-teal-11 ring-1 ring-inset ring-n-teal-7 transition group-hover/selo:bg-n-teal-4"
    >
      <span class="i-lucide-badge-check size-3.5 shrink-0" aria-hidden="true" />
      <span class="min-w-0 break-words">{{ texto }}</span>
      <span
        class="i-lucide-chevron-right size-3.5 shrink-0 rtl:rotate-180"
        aria-hidden="true"
      />
    </span>
  </button>
</template>
