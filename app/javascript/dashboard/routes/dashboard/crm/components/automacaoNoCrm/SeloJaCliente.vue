<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { diaCurto } from './datas';

// #2710 — o selo do card novo de quem já comprou: "Já é cliente · comprou em
// 03/11". É um botão: abre o card ganho. O clique não abre o card de baixo.
const props = defineProps({
  comprouEm: { type: String, required: true },
  ocupado: { type: Boolean, default: false },
});

const emit = defineEmits(['abrir']);

const { t, locale } = useI18n();
const dia = computed(() => diaCurto(props.comprouEm, locale.value));
</script>

<template>
  <button
    type="button"
    data-selo-ja-cliente
    class="group/selo inline-flex min-h-11 w-fit max-w-full items-center rounded-full text-start focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:cursor-wait"
    :aria-label="t('AUTOMACAO_NO_CRM.CLIENTE.SELO_ROTULO', { dia })"
    :aria-busy="ocupado"
    :disabled="ocupado"
    @click.stop="emit('abrir')"
  >
    <span
      class="inline-flex max-w-full items-center gap-1.5 rounded-full bg-n-teal-3 px-2.5 py-1 text-xs font-medium leading-5 text-n-teal-11 ring-1 ring-inset ring-n-teal-7 transition group-hover/selo:bg-n-teal-4"
    >
      <span class="i-lucide-badge-check size-3.5 shrink-0" aria-hidden="true" />
      <span class="truncate">
        {{ t('AUTOMACAO_NO_CRM.CLIENTE.SELO', { dia }) }}
      </span>
      <span
        class="i-lucide-chevron-right size-3.5 shrink-0 rtl:rotate-180"
        aria-hidden="true"
      />
    </span>
  </button>
</template>
