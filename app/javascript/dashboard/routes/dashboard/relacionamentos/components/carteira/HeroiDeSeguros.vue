<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import HeroiEscuro from '../comum/HeroiEscuro.vue';
import { fraseDoHeroiDeSeguros } from '../../carteira/fraseDoHeroiDeSeguros';

// #2897 — o herói da aba Seguros: a frase do dia (escolhida por
// `fraseDoHeroiDeSeguros`) e, quando há para onde ir, UM botão, que leva ao
// grupo de que a frase fala. A carteira vazia só diz que ainda não há seguros.
// Quem pode trazer lista (`podeTrazer`) tem também o botão de trazer seguros:
// na carteira vazia ele é a ação principal ("Trazer meus seguros"); com
// seguros, fica discreto ao lado da principal.
const props = defineProps({
  resumo: { type: Object, required: true },
  // Quantos seguros estão vencidos (a contagem do grupo Vencido).
  vencidos: { type: Number, default: 0 },
  podeTrazer: { type: Boolean, default: false },
});
const emit = defineEmits(['verGrupo', 'trazer']);

const { t } = useI18n();
const PRINCIPAL =
  '!bg-white !text-n-heroi font-semibold hover:enabled:!bg-white/90 focus-visible:!bg-white/90 focus-visible:!outline-white dark:!bg-white dark:!text-n-heroi';
const DISCRETO =
  '!bg-white/10 !text-white/90 !outline-white/20 hover:enabled:!bg-white/20 focus-visible:!outline-white';

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
    <template v-if="frase.principal || podeTrazer" #acao>
      <Button
        v-if="frase.principal"
        size="lg"
        :class="PRINCIPAL"
        data-carteira="heroi-acao"
        :label="t(frase.principal.rotulo)"
        @click="emit('verGrupo', frase.principal.grupo)"
      />
      <Button
        v-if="podeTrazer"
        size="lg"
        :class="frase.principal ? DISCRETO : PRINCIPAL"
        data-carteira="heroi-trazer"
        :label="
          t(
            frase.principal
              ? 'RELACIONAMENTOS_CARTEIRA.TRAZER.BOTAO'
              : 'RELACIONAMENTOS_CARTEIRA.TRAZER.BOTAO_VAZIO'
          )
        "
        @click="emit('trazer')"
      />
    </template>
  </HeroiEscuro>
</template>
