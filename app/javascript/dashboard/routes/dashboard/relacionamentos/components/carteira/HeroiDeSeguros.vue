<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import HeroiEscuro from '../comum/HeroiEscuro.vue';
import { fraseDoHeroiDeSeguros } from '../../carteira/fraseDoHeroiDeSeguros';

// #2897 — o herói da aba Seguros: a frase do dia (escolhida por
// `fraseDoHeroiDeSeguros`) e, quando há para onde ir, UM botão, que leva ao
// grupo de que a frase fala. A carteira vazia só diz que ainda não há seguros.
const props = defineProps({
  resumo: { type: Object, required: true },
  // Quantos seguros estão vencidos (a contagem do grupo Vencido).
  vencidos: { type: Number, default: 0 },
});
const emit = defineEmits(['verGrupo']);

const { t } = useI18n();

const frase = computed(() =>
  fraseDoHeroiDeSeguros(props.resumo, props.vencidos)
);
const traduzir = ({ chave, count }) =>
  count === undefined ? t(chave) : t(chave, { count }, count);
</script>

<template>
  <HeroiEscuro data-carteira="heroi" :data-heroi="frase.id">
    <template #frase>{{ traduzir(frase.frase) }}</template>
    <template v-if="frase.apoio" #apoio>{{ traduzir(frase.apoio) }}</template>
    <template v-if="frase.principal" #acao>
      <Button
        size="lg"
        class="!bg-white !text-n-heroi font-semibold hover:enabled:!bg-white/90 focus-visible:!bg-white/90 focus-visible:!outline-white dark:!bg-white dark:!text-n-heroi"
        data-carteira="heroi-acao"
        :label="t(frase.principal.rotulo)"
        @click="emit('verGrupo', frase.principal.grupo)"
      />
    </template>
  </HeroiEscuro>
</template>
