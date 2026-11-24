<script setup>
import { computed, nextTick, useId, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ChaveDeOpcoes from '../comum/ChaveDeOpcoes.vue';
import LinhaDaCondicao from './LinhaDaCondicao.vue';
import { JUNTAR, novaCondicao } from '../../lista/informacoes';

// #3168 — a seção "Por outra informação" da gaveta "Mais filtros" (só na aba
// Pessoas): "+ Escolher uma informação" cria uma linha (e leva o foco a ela);
// com duas ou mais, "Mostrar quem tem: Tudo isso | Pelo menos uma" vale para
// todas. `erros` diz o que falta em cada linha ({ [id]: código }); a gaveta só
// os passa depois de "Ver resultado". Não muda nada: as linhas novas sobem por
// `update:condicoes`.
const props = defineProps({
  condicoes: { type: Array, required: true },
  juntar: { type: String, default: JUNTAR.TODAS },
  informacoes: { type: Object, required: true },
  erros: { type: Object, default: () => ({}) },
});
const emit = defineEmits(['update:condicoes', 'update:juntar']);

const { t } = useI18n();
const idDoTitulo = useId();
const lista = useTemplateRef('lista');
const secao = useTemplateRef('secao');
const CC = 'RELACIONAMENTOS.LISTA.CONDICOES';

const opcoesDeJuntar = computed(() => [
  { value: JUNTAR.TODAS, label: t(`${CC}.TUDO_ISSO`) },
  { value: JUNTAR.QUALQUER, label: t(`${CC}.PELO_MENOS_UMA`) },
]);

const proximoId = () =>
  props.condicoes.reduce((maior, { id }) => Math.max(maior, id), 0) + 1;

const focarInformacao = async id => {
  await nextTick();
  lista.value
    ?.querySelector(
      `[data-condicao="${id}"] [data-relacionamentos="informacao-da-condicao"] button`
    )
    ?.focus();
};

const adicionar = () => {
  const nova = novaCondicao(proximoId());
  emit('update:condicoes', [...props.condicoes, nova]);
  focarInformacao(nova.id);
};
const mudar = nova =>
  emit(
    'update:condicoes',
    props.condicoes.map(condicao => (condicao.id === nova.id ? nova : condicao))
  );
// Depois da lixeira o foco não se perde: vai para a "Informação" da linha que
// ficou no lugar (ou da anterior, se era a última) ou, sem nenhuma linha, para
// "Escolher uma informação".
const focarDepoisDeTirar = async indice => {
  await nextTick();
  const restantes = props.condicoes;
  if (!restantes.length) {
    secao.value
      ?.querySelector('[data-relacionamentos="escolher-informacao"]')
      ?.focus();
    return;
  }
  focarInformacao(restantes[Math.min(indice, restantes.length - 1)].id);
};
const tirar = id => {
  const indice = props.condicoes.findIndex(condicao => condicao.id === id);
  emit(
    'update:condicoes',
    props.condicoes.filter(condicao => condicao.id !== id)
  );
  focarDepoisDeTirar(indice);
};
</script>

<template>
  <section
    ref="secao"
    :aria-labelledby="idDoTitulo"
    class="flex flex-col gap-4 pt-5 border-t border-n-weak"
    data-relacionamentos="por-outra-informacao"
  >
    <div class="flex flex-col gap-1">
      <h3 :id="idDoTitulo" class="m-0 text-base font-semibold text-n-slate-12">
        {{ t(`${CC}.TITULO`) }}
      </h3>
      <p class="m-0 text-sm text-n-slate-11">{{ t(`${CC}.AJUDA`) }}</p>
    </div>
    <ChaveDeOpcoes
      v-if="condicoes.length > 1"
      :model-value="juntar"
      :opcoes="opcoesDeJuntar"
      :rotulo="t(`${CC}.MOSTRAR_QUEM_TEM`)"
      marca="juntar-condicoes"
      @update:model-value="emit('update:juntar', $event)"
    />
    <ul
      v-if="condicoes.length"
      ref="lista"
      class="flex flex-col gap-3 p-0 m-0 list-none"
    >
      <li v-for="(condicao, indice) in condicoes" :key="condicao.id">
        <LinhaDaCondicao
          :condicao="condicao"
          :informacoes="informacoes"
          :numero="indice + 1"
          :erro="erros[condicao.id] ?? ''"
          @mudar="mudar"
          @tirar="tirar(condicao.id)"
        />
      </li>
    </ul>
    <Button
      link
      type="button"
      icon="i-lucide-plus"
      class="self-start min-h-11"
      data-relacionamentos="escolher-informacao"
      :label="t(`${CC}.ESCOLHER`)"
      @click="adicionar"
    />
  </section>
</template>
