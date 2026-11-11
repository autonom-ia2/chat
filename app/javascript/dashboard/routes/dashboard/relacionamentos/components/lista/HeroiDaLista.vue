<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import HeroiEscuro from '../comum/HeroiEscuro.vue';
import { ACOES_DO_HEROI, escolherFrase } from '../../lista/fraseDoHeroi';

// #2894 — o herói da lista: a frase do dia (escolhida por `escolherFrase`) e
// UMA ação principal. "Trazer minha lista" fica discreto no canto quando não é
// a principal.
const props = defineProps({
  resumo: { type: Object, required: true },
});
const emit = defineEmits(['trazer', 'verGrupo']);

const { t } = useI18n();

const frase = computed(() => escolherFrase(props.resumo));
const texto = computed(() =>
  frase.value.partes
    .map(({ chave, count }) =>
      count === undefined ? t(chave) : t(chave, { count }, count)
    )
    .join(' ')
);

const principal = () => {
  const { acao, grupo } = frase.value.principal;
  if (acao === ACOES_DO_HEROI.TRAZER) emit('trazer');
  else emit('verGrupo', grupo);
};
</script>

<template>
  <HeroiEscuro>
    <template #frase>{{ texto }}</template>
    <template #acao>
      <button
        type="button"
        data-relacionamentos="heroi-acao"
        class="inline-flex items-center justify-center px-6 text-base font-semibold bg-white min-h-12 rounded-xl text-n-heroi hover:bg-white/90 focus-visible:outline-2 focus-visible:outline-white"
        @click="principal"
      >
        {{ t(frase.principal.rotulo) }}
      </button>
    </template>
    <template v-if="frase.mostraTrazerDiscreto" #discreta>
      <button
        type="button"
        data-relacionamentos="heroi-trazer"
        class="inline-flex items-center justify-center px-4 text-sm text-white/90 min-h-11 rounded-xl bg-white/10 ring-1 ring-inset ring-white/20 hover:bg-white/20 focus-visible:outline-2 focus-visible:outline-white"
        @click="emit('trazer')"
      >
        {{ t('RELACIONAMENTOS.COMUM.TRAZER_MINHA_LISTA') }}
      </button>
    </template>
  </HeroiEscuro>
</template>
