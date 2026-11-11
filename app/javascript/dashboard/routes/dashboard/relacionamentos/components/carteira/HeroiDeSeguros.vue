<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import HeroiEscuro from '../comum/HeroiEscuro.vue';
import {
  ACOES_DO_HEROI_DE_SEGUROS,
  fraseDoHeroiDeSeguros,
} from '../../carteira/fraseDoHeroiDeSeguros';

// #2897 — o herói da aba Seguros: a frase do dia (escolhida por
// `fraseDoHeroiDeSeguros`) e UMA ação principal. "Trazer seguros" fica discreto
// ao lado quando não é a principal.
const props = defineProps({
  resumo: { type: Object, required: true },
});
const emit = defineEmits(['trazer', 'verGrupo']);

const { t } = useI18n();

const frase = computed(() => fraseDoHeroiDeSeguros(props.resumo));
const traduzir = ({ chave, count }) =>
  count === undefined ? t(chave) : t(chave, { count }, count);

const principal = () => {
  const { acao, grupo } = frase.value.principal;
  if (acao === ACOES_DO_HEROI_DE_SEGUROS.TRAZER) emit('trazer');
  else emit('verGrupo', grupo);
};
</script>

<template>
  <HeroiEscuro data-carteira="heroi" :data-heroi="frase.id">
    <template #frase>{{ traduzir(frase.frase) }}</template>
    <template v-if="frase.apoio" #apoio>{{ traduzir(frase.apoio) }}</template>
    <template #acao>
      <Button
        size="lg"
        class="!bg-white !text-n-heroi font-semibold hover:enabled:!bg-white/90 focus-visible:!bg-white/90 focus-visible:!outline-white dark:!bg-white dark:!text-n-heroi"
        data-carteira="heroi-acao"
        :label="t(frase.principal.rotulo)"
        @click="principal"
      />
      <Button
        v-if="frase.mostraTrazerDiscreto"
        size="lg"
        class="!bg-white/10 !text-white/90 ring-1 ring-inset ring-white/20 hover:enabled:!bg-white/20 focus-visible:!bg-white/20 focus-visible:!outline-white dark:!bg-white/10 dark:!text-white/90"
        data-carteira="heroi-trazer"
        :label="t('RELACIONAMENTOS_CARTEIRA.HEROI.TRAZER_SEGUROS')"
        @click="emit('trazer')"
      />
    </template>
  </HeroiEscuro>
</template>
