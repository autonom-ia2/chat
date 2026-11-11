<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ErroComTentarDeNovo from '../comum/ErroComTentarDeNovo.vue';
import EsqueletoDeLista from '../comum/EsqueletoDeLista.vue';
import {
  baixarArquivo,
  csvDaHistoria,
  nomeDoArquivoDaHistoria,
} from '../../carteira/exportarHistoria';
import { variacaoDaProposta } from '../../carteira/situacaoDoSeguro';
import { ESTADOS_DA_HISTORIA } from '../../carteira/useSeguroAberto';
import { useTextosDoSeguro } from '../../carteira/useTextosDoSeguro';
import OQueMudou from './OQueMudou.vue';

// #2897 — a história do seguro: tudo o que aconteceu, do mais novo para o mais
// velho. Cada passo diz quando, o que foi e quem fez. "Exportar" baixa o mesmo
// conteúdo num arquivo. É leitura: nenhuma ação principal mora aqui.
const props = defineProps({
  itens: { type: Array, required: true },
  estado: { type: String, default: ESTADOS_DA_HISTORIA.PRONTO },
  numero: { type: String, default: '' },
  agora: { type: Number, default: () => Date.now() },
});
const emit = defineEmits(['tentar', 'exportado', 'verProposta']);

const { t } = useI18n();
const textos = useTextosDoSeguro();
const th = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.HISTORIA.${chave}`, valores);
const idDoTitulo = useId();

const valoresEscritos = ({ valor, motivo, ...resto }) => ({
  ...resto,
  ...(valor === undefined ? {} : { valor: textos.valor(valor) }),
  ...(motivo
    ? {
        motivo: t(`RELACIONAMENTOS_CARTEIRA.MOTIVOS.${motivo.toUpperCase()}`),
      }
    : {}),
});

const mudancaEscrita = ({ campo, antes, depois }) =>
  th('MUDOU_DE_PARA', {
    item: t(`RELACIONAMENTOS_CARTEIRA.PDF.CAMPOS.${campo.toUpperCase()}`),
    antes: textos.doCampo(campo, antes),
    depois: textos.doCampo(campo, depois),
  });

const oQueAconteceu = item => {
  const variacao = variacaoDaProposta(
    'variacao' in item.valores ? item.valores : null
  );
  return [
    th(`TIPOS.${item.tipo.toUpperCase()}`, valoresEscritos(item.valores)),
    ...(item.mudancas ?? []).map(mudancaEscrita),
    variacao && variacao.id !== 'IGUAL'
      ? th(variacao.id, { count: variacao.count })
      : '',
  ].filter(Boolean);
};

const quemFez = item => {
  if (!item.quem) return '';
  return item.quem.nome ?? th(`QUEM.${item.quem.papel.toUpperCase()}`);
};

const passos = computed(() =>
  props.itens.map(item => ({
    ...item,
    dia: textos.diaMes(item.quando, props.agora),
    hora: textos.hora(item.quando),
    texto: oQueAconteceu(item),
    quemFez: quemFez(item),
    // O que a tela escreve: o que aconteceu e, no fim, quem fez.
    linha: [...oQueAconteceu(item), quemFez(item)].filter(Boolean).join(' · '),
    tabela: (item.mudancas ?? []).map(({ campo, antes, depois }) => ({
      campo,
      antes,
      noPdf: depois,
    })),
  }))
);

const exportar = () => {
  const cabecalho = ['DATA', 'HORA', 'O_QUE', 'QUEM'].map(chave =>
    th(`ARQUIVO.${chave}`)
  );
  const linhas = passos.value.map(passo => [
    passo.dia,
    passo.hora,
    passo.texto.join(' · '),
    passo.quemFez,
  ]);
  baixarArquivo(
    nomeDoArquivoDaHistoria(props.numero),
    csvDaHistoria([cabecalho, ...linhas])
  );
  emit('exportado');
};
</script>

<template>
  <section
    data-carteira="historia"
    :aria-labelledby="idDoTitulo"
    class="flex flex-col gap-4"
  >
    <header class="flex items-center justify-between gap-3">
      <h3 :id="idDoTitulo" class="m-0 text-base font-semibold text-n-slate-12">
        {{ th('TITULO') }}
      </h3>
      <Button
        v-if="estado === ESTADOS_DA_HISTORIA.PRONTO"
        slate
        faded
        size="lg"
        icon="i-lucide-download"
        data-carteira="exportar"
        :label="th('EXPORTAR')"
        @click="exportar"
      />
    </header>
    <div
      v-if="estado === ESTADOS_DA_HISTORIA.ERRO"
      data-carteira="historia-erro"
    >
      <ErroComTentarDeNovo :mensagem="th('ERRO')" @tentar="emit('tentar')" />
    </div>
    <EsqueletoDeLista
      v-else-if="estado === ESTADOS_DA_HISTORIA.CARREGANDO"
      :linhas="3"
      data-carteira="historia-carregando"
    />
    <ol v-else class="flex flex-col gap-4 p-0 m-0 list-none">
      <li
        v-for="passo in passos"
        :key="passo.id"
        data-carteira="item-da-historia"
        :data-passo="passo.tipo"
        class="flex flex-col min-w-0 gap-1 border-s-2 border-n-weak ps-4"
      >
        <span class="text-sm tabular-nums text-n-slate-11">
          {{ passo.dia }} · {{ passo.hora }}
        </span>
        <span class="text-base break-words text-n-slate-12">
          {{ passo.linha }}
        </span>
        <details v-if="passo.tabela.length" class="text-sm">
          <summary
            class="inline-flex items-center rounded-md cursor-pointer min-h-11 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          >
            {{ t('RELACIONAMENTOS_CARTEIRA.PDF.O_QUE_MUDOU') }}
          </summary>
          <OQueMudou marca="mudanca-da-historia" :linhas="passo.tabela" />
        </details>
        <div v-if="passo.acao === 'ver_proposta'">
          <Button
            link
            size="lg"
            data-carteira="ver-proposta"
            :label="th('VER_PROPOSTA')"
            @click="emit('verProposta', passo)"
          />
        </div>
      </li>
    </ol>
  </section>
</template>
