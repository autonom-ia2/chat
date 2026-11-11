<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import DetalheDaLista from '../../trazer/DetalheDaLista.vue';
import HistoricoDeListas from '../../trazer/HistoricoDeListas.vue';
import { formatarHora } from '../../../carteira/formatosDoSeguro';
import { COMO } from '../../../carteira/passosDeTrazerSeguros';
import { useIdioma } from '../../../ficha/idioma';
import { SITUACOES_DA_LISTA, formatarDia } from '../../../trazer/prazo';

// #2897 — "O que você já trouxe" na conta de seguros: o mesmo histórico do
// bloco A, agora com as levas de seguros (planilha, PDFs e Agger) por cima das
// listas de pessoas. A linha do Agger diz que ele busca todo dia e deixa parar
// (e voltar), sem prazo. Desfazer continua igual.
const props = defineProps({
  listas: { type: Array, required: true },
  carregando: { type: Boolean, default: false },
  comErro: { type: Boolean, default: false },
  fonte: { type: Object, required: true },
});
const emit = defineEmits(['desfazer', 'tentar', 'mudou']);

const { t, locale } = useI18n();
const th = (chave, ...resto) =>
  t(`RELACIONAMENTOS_CARTEIRA.TRAZER.HISTORICO.${chave}`, ...resto);
const idioma = useIdioma();
const mudando = ref('');

const MS_POR_SEGUNDO = 1000;
const dia = ms => formatarDia(ms, locale.value);
const hora = ms => formatarHora(ms / MS_POR_SEGUNDO, idioma.value);

// O nome de cada leva: o arquivo da planilha, "40 PDFs de apólices" ou "Agger".
const nomeDe = lista => {
  if (lista.tipo === COMO.AGGER) return th('AGGER');
  if (lista.tipo === COMO.PDFS) {
    return th('PDFS', { count: lista.pdfs }, lista.pdfs);
  }
  return lista.arquivo;
};
const comNome = computed(() =>
  props.listas.map(lista => ({ ...lista, arquivo: nomeDe(lista) }))
);

const doAgger = lista =>
  lista.tipo === COMO.AGGER && lista.situacao === SITUACOES_DA_LISTA.PRONTO;

const ultimaBusca = lista =>
  dia(lista.ultimaBusca) === dia(Date.now())
    ? th('ULTIMA_HOJE', { hora: hora(lista.ultimaBusca) })
    : th('ULTIMA_EM', {
        data: dia(lista.ultimaBusca),
        hora: hora(lista.ultimaBusca),
      });

// "busca todo dia · última hoje, 06:10 · 2 seguros novos"
const buscaDe = lista =>
  lista.buscaTodoDia
    ? [
        th('BUSCA_TODO_DIA'),
        ultimaBusca(lista),
        lista.novos ? th('NOVOS', { count: lista.novos }, lista.novos) : '',
      ]
        .filter(Boolean)
        .join(' · ')
    : th('PAROU_DE_BUSCAR');

const buscarTodoDia = async (lista, ligado) => {
  mudando.value = lista.id;
  try {
    await props.fonte.buscarTodoDia(lista.id, ligado);
    useAlert(th(ligado ? 'VOLTOU' : 'PAROU'));
    emit('mudou');
  } catch {
    useAlert(th('ERRO_PARAR'));
  } finally {
    mudando.value = '';
  }
};
</script>

<template>
  <HistoricoDeListas
    :titulo="t('RELACIONAMENTOS_CARTEIRA.TRAZER.COMO.JA_TROUXE')"
    :listas="comNome"
    :carregando="carregando"
    :com-erro="comErro"
    @desfazer="emit('desfazer', $event)"
    @tentar="emit('tentar')"
  >
    <template #detalhe="{ lista }">
      <DetalheDaLista v-if="!lista.tipo" :lista="lista" />
      <template v-else>
        {{
          t('RELACIONAMENTOS_TRAZER.HISTORICO.EM', { data: dia(lista.quando) })
        }}
        ·
        {{ t('RELACIONAMENTOS_TRAZER.HISTORICO.POR', { nome: lista.quem }) }}
        ·
        <span data-carteira="historico-seguros" class="tabular-nums">
          {{ th('SEGUROS', { count: lista.seguros }, lista.seguros) }}
        </span>
        <span
          v-if="doAgger(lista)"
          data-carteira="agger-historico"
          class="block tabular-nums"
        >
          {{ buscaDe(lista) }}
        </span>
      </template>
    </template>
    <template #acoes="{ lista }">
      <Button
        v-if="doAgger(lista)"
        slate
        ghost
        :data-carteira="
          lista.buscaTodoDia ? 'agger-parar' : 'agger-voltar-a-buscar'
        "
        :label="th(lista.buscaTodoDia ? 'PARAR' : 'VOLTAR_A_BUSCAR')"
        :is-loading="mudando === lista.id"
        :disabled="mudando === lista.id"
        @click="buscarTodoDia(lista, !lista.buscaTodoDia)"
      />
    </template>
  </HistoricoDeListas>
</template>
