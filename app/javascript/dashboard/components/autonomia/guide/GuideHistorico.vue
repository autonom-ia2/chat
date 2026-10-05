<script setup>
import { ref, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import GuideConversas from './GuideConversas.vue';
import GuideFeitos from './GuideFeitos.vue';

// #861 — o histórico do Guia, em duas abas: as conversas anteriores e o que
// ele fez na conta (#855). Abas próprias, no visual do TabBar da casa, porque
// o alvo de toque do TabBar é 32 px e o painel pede 44.
defineProps({
  conversaAtual: {
    type: Number,
    default: null,
  },
});

const emit = defineEmits(['abrir', 'apagou']);

const { t } = useI18n();

const ABAS = [
  { id: 'conversas', rotulo: () => t('AUTONOMIA_GUIDE.HISTORY.TAB_CONVERSAS') },
  { id: 'feitos', rotulo: () => t('AUTONOMIA_GUIDE.DONE.LIST_TITLE') },
];

const ativa = ref('conversas');
const botoes = ref([]);

// Setas trocam de aba, como o padrão de abas do WAI-ARIA.
const mover = async passo => {
  const indice = ABAS.findIndex(aba => aba.id === ativa.value);
  const proximo = (indice + passo + ABAS.length) % ABAS.length;
  ativa.value = ABAS[proximo].id;
  await nextTick();
  botoes.value[proximo]?.focus();
};
</script>

<template>
  <div class="flex flex-col gap-4 w-full">
    <div
      role="tablist"
      class="flex items-center gap-1 p-1 rounded-lg bg-n-alpha-1 w-full"
      @keydown.right.prevent="mover(1)"
      @keydown.left.prevent="mover(-1)"
    >
      <button
        v-for="(aba, indice) in ABAS"
        :id="`guia-aba-${aba.id}`"
        :key="aba.id"
        :ref="el => (botoes[indice] = el)"
        type="button"
        role="tab"
        :aria-selected="ativa === aba.id ? 'true' : 'false'"
        :aria-controls="`guia-painel-${aba.id}`"
        :tabindex="ativa === aba.id ? 0 : -1"
        class="flex-1 min-h-11 px-3 text-sm rounded-md transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :class="
          ativa === aba.id
            ? 'bg-n-solid-active text-n-blue-11 shadow-sm'
            : 'text-n-slate-11 hover:text-n-slate-12'
        "
        @click="ativa = aba.id"
      >
        {{ aba.rotulo() }}
      </button>
    </div>
    <div
      :id="`guia-painel-${ativa}`"
      role="tabpanel"
      :aria-labelledby="`guia-aba-${ativa}`"
    >
      <GuideConversas
        v-if="ativa === 'conversas'"
        :conversa-atual="conversaAtual"
        @abrir="emit('abrir', $event)"
        @apagou="emit('apagou', $event)"
      />
      <GuideFeitos v-else />
    </div>
  </div>
</template>
