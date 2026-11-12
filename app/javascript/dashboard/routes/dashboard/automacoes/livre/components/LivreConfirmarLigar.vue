<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import DialogoDaCasa from 'dashboard/routes/dashboard/settings/funcoesDaEquipe/guiada/DialogoDaCasa.vue';
import { custoPorExecucao, oQueLigarFaz } from '../aoLigar';
import { custoEmTexto } from '../custoDaIa';

// #2574 (F5.4) — antes de ligar a automação que manda mensagem, avisa a equipe
// ou usa IA: diz isso em frase e o custo. O valor e os tokens da IA (a média
// dos últimos 30 dias ou, antes da primeira vez, a estimativa pelo modelo de
// cada passo) só para quem vê os custos da conta (`com_valores`: administrador
// ou financial_view, #2559). Quem abre chama `abrir()`; "Ligar" emite `ligar`.
const props = defineProps({
  receita: { type: Object, default: null },
  // { com_valores, custos: { <passo>: { media, vezes, tokens } },
  //   estimativa: { <tipo>: { modelo, tokens, custo_usd } } } (custos da IA).
  custos: { type: Object, default: () => ({ com_valores: false }) },
});

const emit = defineEmits(['ligar']);

const { t, locale } = useI18n();
const C = 'AUTOMACAO_LIVRE.LIGAR.CONFIRMAR';
const dialogo = ref(null);

const faz = computed(() => oQueLigarFaz(props.receita));

const tokensEmTexto = tokens =>
  new Intl.NumberFormat(locale.value.replace('_', '-')).format(tokens);

// As linhas do custo: o valor (ou que ele aparece depois da primeira vez) e,
// quando todos os passos os têm, os tokens.
const linhasDoCusto = () => {
  const custo = custoPorExecucao(faz.value.ia, props.custos || {});
  if (!custo) {
    return [{ chave: 'custo', texto: t('AUTOMACAO_LIVRE.IA.CUSTO.PRIMEIRA') }];
  }
  const frase = custo.estimado ? `${C}.IA_CUSTO_ESTIMADO` : `${C}.IA_CUSTO`;
  return [
    {
      chave: 'custo',
      texto: t(frase, { custo: custoEmTexto(custo.valor, t, locale.value) }),
    },
    custo.tokens !== null && {
      chave: 'tokens',
      texto: t(`${C}.TOKENS`, { tokens: tokensEmTexto(custo.tokens) }),
    },
  ];
};

const linhas = computed(() => {
  const usaIa = faz.value.ia.length > 0;
  const mostraCusto = usaIa && Boolean(props.custos?.com_valores);
  return [
    faz.value.manda && { chave: 'clientes', texto: t(`${C}.CLIENTES`) },
    faz.value.modeloDaMeta && { chave: 'meta', texto: t(`${C}.META`) },
    faz.value.avisa && { chave: 'equipe', texto: t(`${C}.EQUIPE`) },
    faz.value.agente && { chave: 'agente', texto: t(`${C}.AGENTE`) },
    usaIa && { chave: 'ia', texto: t(`${C}.IA`) },
    ...(mostraCusto ? linhasDoCusto() : []),
  ].filter(Boolean);
});

defineExpose({ abrir: () => dialogo.value?.abrir() });
</script>

<template>
  <DialogoDaCasa
    ref="dialogo"
    tipo="cuidado"
    icone="i-lucide-power"
    :titulo="$t(`${C}.TITULO`)"
    :seguro="$t(`${C}.CANCELAR`)"
    :acao="$t(`${C}.LIGAR`)"
    @acao="emit('ligar')"
  >
    <p
      v-for="linha in linhas"
      :key="linha.chave"
      :data-confirmar="linha.chave"
      class="m-0 text-[0.9375rem] text-n-slate-11"
    >
      {{ linha.texto }}
    </p>
  </DialogoDaCasa>
</template>
