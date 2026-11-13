<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ErroComTentarDeNovo from '../comum/ErroComTentarDeNovo.vue';
import EsqueletoDeLista from '../comum/EsqueletoDeLista.vue';
import { PONTO, SEPARADOR } from '../comum/ponto';
import {
  baixarArquivo,
  csvDoHistorico,
  nomeDoArquivoDoHistorico,
} from '../../carteira/exportarHistoria';
import { DETALHES, fraseDoPasso } from '../../carteira/passoDoHistorico';
import { ESTADOS_DA_HISTORIA } from '../../carteira/useSeguroAberto';
import { useTextosDoSeguro } from '../../carteira/useTextosDoSeguro';

// #2897 — o histórico do seguro: tudo o que aconteceu, do mais novo para o
// mais velho. Cada passo diz quando, o que foi e quem fez (sem nome quando foi
// o próprio sistema). Na correção, embaixo vem o que mudou, uma linha por
// informação: "Valor que o cliente paga: era R$ 610,00, ficou R$ 640,00". É
// leitura: nenhuma ação principal mora aqui.
// #2898 — a renovação conta os passos dela (começou e com quem, renovou, não
// renovou e o motivo, desfeito, apólice nova) e, para quem pode exportar
// contatos, "Exportar" baixa o mesmo conteúdo num arquivo que a planilha abre.
// O arquivo é montado aqui mesmo, com o que já está na tela.
const props = defineProps({
  itens: { type: Array, required: true },
  estado: { type: String, default: ESTADOS_DA_HISTORIA.PRONTO },
  podeExportar: { type: Boolean, default: false },
  agora: { type: Number, default: () => Date.now() },
});
const emit = defineEmits(['tentar', 'exportado']);

const { t } = useI18n();
const textos = useTextosDoSeguro();
const th = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.HISTORIA.${chave}`, valores);
const idDoTitulo = useId();

const escrito = (campo, conteudo) =>
  conteudo === null || conteudo === ''
    ? th('NAO_INFORMADO')
    : textos.doCampo(campo, conteudo);

const mudancaEscrita = ({ campo, antes, depois }) =>
  th('MUDOU_DE_PARA', {
    item: t(`RELACIONAMENTOS_CARTEIRA.CAMPOS.${campo.toUpperCase()}`),
    antes: escrito(campo, antes),
    depois: escrito(campo, depois),
  });

// O detalhe de um passo, do jeito que a frase escreve: o motivo pelo nome
// dele, o número da apólice anterior como "nº …", e o motivo escrito e o nome
// de quem cuida como vieram.
const DETALHE_ESCRITO = {
  [DETALHES.CUIDA]: nome => nome,
  [DETALHES.MOTIVO]: motivo =>
    t(
      `RELACIONAMENTOS_CARTEIRA.RENOVACAO.MOTIVO.NA_FRASE.${motivo.toUpperCase()}`
    ),
  [DETALHES.ANTERIOR]: numero => textos.numero({ numero }),
  [DETALHES.TEXTO]: texto => texto,
};
const oQueAconteceu = item => {
  const { chave, detalhe, valor } = fraseDoPasso(item);
  return detalhe
    ? th(chave, { [detalhe]: DETALHE_ESCRITO[detalhe](valor) })
    : th(chave);
};

const passos = computed(() =>
  props.itens.map(item => ({
    tipo: item.tipo,
    dia: textos.diaMes(item.quando, props.agora),
    hora: textos.hora(item.quando),
    oQue: oQueAconteceu(item),
    quem: item.quem?.nome ?? '',
    mudancas: (item.mudancas ?? []).map(mudancaEscrita),
  }))
);
// O que aconteceu e, no fim, quem fez.
const pedacosDe = passo => [passo.oQue, passo.quem].filter(Boolean);

const temOQueExportar = computed(
  () =>
    props.podeExportar &&
    props.estado === ESTADOS_DA_HISTORIA.PRONTO &&
    passos.value.length > 0
);
const exportar = () => {
  const cabecalho = ['DATA', 'HORA', 'O_QUE', 'QUEM'].map(chave =>
    th(`ARQUIVO.${chave}`)
  );
  const linhas = passos.value.map(passo => [
    passo.dia,
    passo.hora,
    [passo.oQue, ...passo.mudancas].join(SEPARADOR),
    passo.quem,
  ]);
  baixarArquivo(
    nomeDoArquivoDoHistorico(),
    csvDoHistorico([cabecalho, ...linhas])
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
    <header class="flex flex-wrap items-center justify-between gap-x-3 gap-y-2">
      <h3 :id="idDoTitulo" class="m-0 text-base font-semibold text-n-slate-12">
        {{ th('TITULO') }}
      </h3>
      <Button
        v-if="temOQueExportar"
        slate
        faded
        size="lg"
        class="whitespace-nowrap"
        icon="i-lucide-download"
        data-carteira="exportar-historico"
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
      <!-- O servidor não manda id do passo: a ordem é a chave. -->
      <li
        v-for="(passo, indice) in passos"
        :key="indice"
        data-carteira="item-da-historia"
        :data-passo="passo.tipo"
        class="flex flex-col min-w-0 gap-1 border-s-2 border-n-weak ps-4"
      >
        <span class="text-sm tabular-nums text-n-slate-11">
          {{ passo.dia }} {{ PONTO }} {{ passo.hora }}
        </span>
        <span class="text-base break-words text-n-slate-12">
          {{ pedacosDe(passo).join(SEPARADOR) }}
        </span>
        <ul
          v-if="passo.mudancas.length"
          class="flex flex-col gap-1 p-0 m-0 list-none"
        >
          <li
            v-for="mudanca in passo.mudancas"
            :key="mudanca"
            data-carteira="mudanca-da-historia"
            class="text-sm break-words text-n-slate-11"
          >
            {{ mudanca }}
          </li>
        </ul>
      </li>
    </ol>
  </section>
</template>
