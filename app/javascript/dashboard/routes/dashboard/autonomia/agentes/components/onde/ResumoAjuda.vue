<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// Tema 14 (#1434) — o resumo do ajudante: quem ele ajuda ("Ajuda: Clara, Bruno") e, quando conhecido, o
// "quando chamar". Usado no topo da criação, no Pronto e na página do ajudante.
// `principais`: [{ id, name }]; `quando`: a frase, ou vazio quando não foi lida.
const props = defineProps({
  principais: { type: Array, default: () => [] },
  quando: { type: String, default: '' },
});

const { t } = useI18n();

const nomes = computed(() =>
  props.principais.map(principal => principal.name).join(', ')
);
</script>

<template>
  <ul data-resumo-ajuda class="flex flex-col gap-3 p-0 m-0 list-none">
    <li class="flex items-start gap-3 text-sm text-n-slate-12">
      <span
        aria-hidden="true"
        class="grid rounded-lg place-items-center size-9 shrink-0 bg-n-iris-3 text-n-iris-11"
      >
        <span class="i-lucide-bot size-5" />
      </span>
      <span class="flex flex-col gap-0.5 min-w-0">
        <b data-ajuda-nomes class="font-semibold">
          {{ t('AGENTS.JORNADA.ONDE.AJUDA', { agentes: nomes }) }}
        </b>
        <span v-if="quando" data-ajuda-quando class="text-n-slate-11">
          {{ t('AGENTS.JORNADA.AJUDANTE.QUANDO.RESUMO', { quando }) }}
        </span>
      </span>
    </li>
  </ul>
</template>
