<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import DialogoDaCasa from 'dashboard/routes/dashboard/settings/funcoesDaEquipe/guiada/DialogoDaCasa.vue';
import { custoPorExecucao, oQueLigarFaz } from '../aoLigar';
import { custoEmTexto } from '../custoDaIa';

// #2574 (F5.4) — antes de ligar a automação que manda mensagem, avisa a equipe
// ou usa IA: diz isso em frase e o custo. O valor da IA (a média dos últimos 30
// dias) só para quem vê os custos da conta (`com_valores`: administrador ou
// financial_view, #2559). Quem abre chama `abrir()`; "Ligar" emite `ligar`.
const props = defineProps({
  receita: { type: Object, default: null },
  // { com_valores, custos: { <passo>: { media, vezes } } } (custosDaAutomacao).
  custos: { type: Object, default: () => ({ com_valores: false }) },
});

const emit = defineEmits(['ligar']);

const { t, locale } = useI18n();
const C = 'AUTOMACAO_LIVRE.LIGAR.CONFIRMAR';
const dialogo = ref(null);

const faz = computed(() => oQueLigarFaz(props.receita));

const custoDaIa = () => {
  const valor = custoPorExecucao(faz.value.ia, props.custos?.custos);
  return valor === null
    ? t('AUTOMACAO_LIVRE.IA.CUSTO.PRIMEIRA')
    : t(`${C}.IA_CUSTO`, { custo: custoEmTexto(valor, t, locale.value) });
};

const linhas = computed(() => {
  const usaIa = faz.value.ia.length > 0;
  const mostraCusto = usaIa && Boolean(props.custos?.com_valores);
  return [
    faz.value.manda && { chave: 'clientes', texto: t(`${C}.CLIENTES`) },
    faz.value.modeloDaMeta && { chave: 'meta', texto: t(`${C}.META`) },
    faz.value.avisa && { chave: 'equipe', texto: t(`${C}.EQUIPE`) },
    usaIa && { chave: 'ia', texto: t(`${C}.IA`) },
    mostraCusto && { chave: 'custo', texto: custoDaIa() },
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
