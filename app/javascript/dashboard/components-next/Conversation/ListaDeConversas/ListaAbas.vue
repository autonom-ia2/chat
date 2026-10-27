<script setup>
// #2202 — as abas da lista com a chave lista_quem_espera: "Minhas" e "Para pegar" com
// contador, "Todas" sem (o número de todas não ajuda a decidir nada). As abas que a
// pessoa vê são as de hoje (permissões e funções personalizadas, #1800).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import wootConstants from 'dashboard/constants/globals';

const props = defineProps({
  items: { type: Array, default: () => [] },
  activeTab: { type: String, default: wootConstants.ASSIGNEE_TYPE.ME },
});
const emit = defineEmits(['chatTabChange']);
const { t } = useI18n();

const { ME, UNASSIGNED, ALL } = wootConstants.ASSIGNEE_TYPE;
const NOMES = { [ME]: 'MINHAS', [UNASSIGNED]: 'PARA_PEGAR', [ALL]: 'TODAS' };

const abas = computed(() =>
  props.items.map(item => ({
    key: item.key,
    nome: NOMES[item.key]
      ? t(`LISTA_DE_CONVERSAS.ABAS.${NOMES[item.key]}`)
      : item.name,
    contador: item.key === ALL ? null : item.count,
  }))
);

const escolher = key => {
  if (key !== props.activeTab) emit('chatTabChange', key);
};
</script>

<template>
  <div
    role="tablist"
    :aria-label="t('LISTA_DE_CONVERSAS.ABAS.ARIA')"
    class="flex items-end gap-5 px-4 border-b border-n-weak"
    data-lista-abas
  >
    <button
      v-for="aba in abas"
      :key="aba.key"
      type="button"
      role="tab"
      :aria-selected="aba.key === activeTab"
      :data-aba="aba.key"
      class="relative flex items-center gap-1.5 px-0 text-sm bg-transparent border-0 min-h-11 after:absolute after:inset-x-0 after:bottom-0 after:h-0.5 after:rounded-full"
      :class="
        aba.key === activeTab
          ? 'font-medium text-n-blue-11 after:bg-n-brand'
          : 'text-n-slate-11 hover:text-n-slate-12 after:bg-transparent'
      "
      @click="escolher(aba.key)"
    >
      {{ aba.nome }}
      <span
        v-if="aba.contador !== null"
        class="px-1.5 text-xs font-medium rounded-full min-w-5 h-5 inline-flex items-center justify-center tabular-nums"
        :class="
          aba.key === activeTab
            ? 'bg-n-blue-3 text-n-blue-11'
            : 'bg-n-alpha-1 text-n-slate-11'
        "
      >
        {{ aba.contador }}
      </span>
    </button>
  </div>
</template>
