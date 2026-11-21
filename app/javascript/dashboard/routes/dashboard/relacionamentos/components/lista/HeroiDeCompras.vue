<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import HeroiEscuro from '../comum/HeroiEscuro.vue';
import { formatarDinheiro } from '../../ficha/compras';
import { useIdioma } from '../../ficha/idioma';
import { escolherFraseDeCompras } from '../../lista/fraseDoHeroiDeCompras';

// #3097 — o herói da lista na visão por compra: uma frase sobre compra (quem
// passou da hora, quem está sem comprar, os campeões) e o quanto essas pessoas
// já compraram, em letra branca grande. UMA ação: ver o grupo. Sem "Trazer
// minha lista" aqui (uma ação por tela). O valor só aparece com uma moeda só:
// moedas diferentes não se somam. `textos`: as faixas da conta em palavras.
const props = defineProps({
  resumo: { type: Object, default: () => ({}) },
  textos: { type: Object, required: true },
  // O grupo já aberto na lista: aí o botão não teria o que fazer.
  grupoEscolhido: { type: String, default: '' },
});
const emit = defineEmits(['verGrupo']);

const { t } = useI18n();
const idioma = useIdioma();
const H = 'RELACIONAMENTOS_COMPRAS.HEROI';

const frase = computed(() => escolherFraseDeCompras(props.resumo?.compras));
const texto = computed(() =>
  t(
    `${H}.${frase.value.frase}`,
    { count: frase.value.count, ...props.textos },
    frase.value.count
  )
);
const valor = computed(() => {
  const moedas = frase.value.porMoeda;
  if (moedas.length !== 1 || !(moedas[0].total > 0)) return '';
  return formatarDinheiro(moedas[0].total, moedas[0].moeda, idioma.value);
});
const apoio = computed(() => {
  if (frase.value.id === 'nenhuma') return t(`${H}.NENHUMA_APOIO`);
  return valor.value
    ? t(`${H}.JUNTOS`, { valor: valor.value }, frase.value.count)
    : '';
});
</script>

<template>
  <HeroiEscuro data-relacionamentos="heroi-de-compras">
    <template #frase>{{ texto }}</template>
    <template v-if="apoio" #apoio>{{ apoio }}</template>
    <template v-if="frase.grupo && frase.grupo !== grupoEscolhido" #acao>
      <Button
        size="lg"
        class="!bg-white !text-n-heroi font-semibold hover:enabled:!bg-white/90 focus-visible:!bg-white/90 focus-visible:!outline-white dark:!bg-white dark:!text-n-heroi"
        data-relacionamentos="heroi-acao"
        :label="t(`${H}.${frase.botao}`)"
        @click="emit('verGrupo', frase.grupo)"
      />
    </template>
  </HeroiEscuro>
</template>
