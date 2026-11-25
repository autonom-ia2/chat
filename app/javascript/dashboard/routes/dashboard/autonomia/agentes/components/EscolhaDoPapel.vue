<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import PapelCartao from './PapelCartao.vue';

// #3219 — passo 1, dentro do herói navy: o primeiro papel (atender clientes) em destaque, sozinho na linha; os outros
// embaixo, em cartões baixos. Quantos aparecem depende da conta (papeisDisponiveis): de 1 a 4 nos outros, e a grade
// se ajusta para não sobrar cartão sozinho ao lado de um buraco (3 viram 3 colunas; 1 ocupa a linha).
const props = defineProps({
  papeis: { type: Array, required: true },
  podeUsar: { type: Boolean, default: false },
  // Tela inicial: balões de exemplo no cartão em destaque (PapelCartao).
  exemplo: { type: Array, default: () => [] },
});

const emit = defineEmits(['escolher']);

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.CRIAR_EM_PASSOS.PAPEL';
const principal = computed(() => props.papeis[0]);
const outros = computed(() => props.papeis.slice(1));
const colunas = computed(() => {
  if (outros.value.length === 3) return 'md:grid-cols-3';
  return outros.value.length > 1 ? 'md:grid-cols-2' : '';
});
</script>

<template>
  <div data-escolha-do-papel class="flex flex-col gap-6">
    <ul :aria-label="t(`${NS}.ROTULO`)" class="flex flex-col p-0 m-0 list-none">
      <PapelCartao
        :papel="principal"
        destaque
        :exemplo="exemplo"
        :pode-usar="podeUsar"
        @escolher="chave => emit('escolher', chave)"
      />
    </ul>
    <section
      v-if="outros.length"
      aria-labelledby="outros-papeis-titulo"
      class="flex flex-col gap-3"
    >
      <h2
        id="outros-papeis-titulo"
        class="m-0 text-base font-semibold text-white/90"
      >
        {{ t(outros.length > 1 ? `${NS}.OUTROS` : `${NS}.OUTRO`) }}
      </h2>
      <ul class="grid grid-cols-1 gap-3 p-0 m-0 list-none" :class="colunas">
        <PapelCartao
          v-for="papel in outros"
          :key="papel.chave"
          :papel="papel"
          :pode-usar="podeUsar"
          @escolher="chave => emit('escolher', chave)"
        />
      </ul>
    </section>
  </div>
</template>
