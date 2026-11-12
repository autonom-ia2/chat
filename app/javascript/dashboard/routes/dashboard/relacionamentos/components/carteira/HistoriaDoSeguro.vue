<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import ErroComTentarDeNovo from '../comum/ErroComTentarDeNovo.vue';
import EsqueletoDeLista from '../comum/EsqueletoDeLista.vue';
import { PONTO, SEPARADOR } from '../comum/ponto';
import { ESTADOS_DA_HISTORIA } from '../../carteira/useSeguroAberto';
import { useTextosDoSeguro } from '../../carteira/useTextosDoSeguro';

// #2897 — o histórico do seguro: tudo o que aconteceu, do mais novo para o
// mais velho. Cada passo diz quando, o que foi e quem fez (sem nome quando foi
// o próprio sistema). Na correção, embaixo vem o que mudou, uma linha por
// informação: "Valor que o cliente paga: era R$ 610,00, ficou R$ 640,00". É
// leitura: nenhuma ação mora aqui.
const props = defineProps({
  itens: { type: Array, required: true },
  estado: { type: String, default: ESTADOS_DA_HISTORIA.PRONTO },
  agora: { type: Number, default: () => Date.now() },
});
const emit = defineEmits(['tentar']);

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

const passos = computed(() =>
  props.itens.map(item => ({
    tipo: item.tipo,
    dia: textos.diaMes(item.quando, props.agora),
    hora: textos.hora(item.quando),
    // O que aconteceu e, no fim, quem fez.
    pedacos: [
      th(`TIPOS.${item.tipo.toUpperCase()}`),
      item.quem?.nome ?? '',
    ].filter(Boolean),
    mudancas: (item.mudancas ?? []).map(mudancaEscrita),
  }))
);
</script>

<template>
  <section
    data-carteira="historia"
    :aria-labelledby="idDoTitulo"
    class="flex flex-col gap-4"
  >
    <h3 :id="idDoTitulo" class="m-0 text-base font-semibold text-n-slate-12">
      {{ th('TITULO') }}
    </h3>
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
          {{ passo.pedacos.join(SEPARADOR) }}
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
