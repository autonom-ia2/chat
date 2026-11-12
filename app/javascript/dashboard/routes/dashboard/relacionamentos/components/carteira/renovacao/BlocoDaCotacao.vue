<script setup>
import { computed, useId, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  COTACAO,
  contarRespostas,
  cotacaoDoCard,
} from '../../../carteira/cotacaoDoCard';
import { variacaoDaProposta } from '../../../carteira/situacaoDoSeguro';
import { useTextosDoSeguro } from '../../../carteira/useTextosDoSeguro';
import DadosQueFaltam from './DadosQueFaltam.vue';
import RespostasDaCotacao from './RespostasDaCotacao.vue';

// #2897 — a cotação dentro da renovação, num estado de cada vez
// (carteira/cotacaoDoCard.js): o que já se sabe em uma ou duas frases. O passo
// da vez (cotar, enviar, pôr o telefone, conversar…) não mora aqui: é o único
// botão azul da gaveta, no rodapé (carteira/passoDaVez.js). Aqui só ficam o
// link discreto do que já existe ("Ver resumo", "Ver proposta"), a escolha da
// seguradora quando várias responderam e os dados que faltam para cotar.
const props = defineProps({
  seguro: { type: Object, required: true },
  // O que a conta cota: { cotaSozinha, tiposQueCota }.
  daConta: { type: Object, default: () => ({}) },
  // A seguradora que o passo da vez escolheu ('' = nenhuma).
  escolhida: { type: String, default: '' },
  // A pessoa resolveu escrever os dados que faltam sem esperar a resposta.
  preenchendo: { type: Boolean, default: false },
  // O nome da ação que está rodando ('' = nenhuma).
  ocupado: { type: String, default: '' },
  agora: { type: Number, default: () => Date.now() },
});
const emit = defineEmits(['fazer', 'verProposta', 'preencher']);

const { t } = useI18n();
const ca = (chave, valores, plural) =>
  t(`RELACIONAMENTOS_CARTEIRA.RENOVACAO.COTACAO.${chave}`, valores, plural);
const tr = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.GAVETA.RENOVACAO.${chave}`, valores);
const textos = useTextosDoSeguro();
const id = useId();
const dados = useTemplateRef('dados');

const estado = computed(() => cotacaoDoCard(props.seguro, props.daConta));
const renovacao = computed(() => props.seguro.renovacao);
const proposta = computed(() => renovacao.value.proposta);
const nome = computed(() => props.seguro.pessoa.name.split(' ')[0]);
const daProposta = () => ({
  seguradora: proposta.value.seguradora ?? props.seguro.seguradora,
  valor: textos.valor(proposta.value.valor),
  periodo: textos.periodo(proposta.value),
});
const doEnvio = () => ({
  nome: proposta.value.enviadaPor,
  data: textos.diaMes(proposta.value.enviadaEm, props.agora),
  hora: textos.hora(proposta.value.enviadaEm),
});
// Antes do prazo, quem falta "ainda não respondeu"; depois, "não respondeu a
// tempo".
const jaResponderam = () => {
  const { deram, faltam } = contarRespostas(renovacao.value.respostas);
  const naoVeio = renovacao.value.passouOPrazo ? 'NAO_A_TEMPO' : 'AINDA_NAO';
  return [
    ca('JA_DERAM', { count: deram }, deram),
    faltam ? ca(naoVeio, { count: faltam }, faltam) : '',
  ];
};
const comONome = chave => () => [ca(chave, { nome: nome.value })];

const FRASES = {
  [COTACAO.ENVIADA_SOZINHA]: () => [ca('ENVIADA_SOZINHA', doEnvio())],
  [COTACAO.ENVIADA_POR_VOCE]: () => [ca('ENVIADA_POR_VOCE', doEnvio())],
  [COTACAO.ENVIADA_POR]: () => [ca('ENVIADA_POR', doEnvio())],
  [COTACAO.SEM_TELEFONE]: comONome('SEM_TELEFONE'),
  [COTACAO.NAO_QUER]: comONome('NAO_QUER'),
  [COTACAO.BLOQUEADO]: comONome('BLOQUEADO'),
  [COTACAO.NAO_SAIU]: () => [ca('NAO_SAIU')],
  [COTACAO.PRECO_SEM_PDF]: () => [
    ca('PRECO_SEM_PDF', daProposta()),
    ca('SEM_PDF_DE_PROPOSTA'),
  ],
  [COTACAO.PRONTA]: () => [
    ca(
      proposta.value.oficial ? 'PRONTA_PROPOSTA' : 'PRONTA_RESUMO',
      daProposta()
    ),
  ],
  [COTACAO.PARCIAL]: jaResponderam,
  [COTACAO.COTANDO]: () => [tr('COTANDO')],
  [COTACAO.AGGER_FORA]: () => [ca('AGGER_FORA')],
  [COTACAO.DEMOROU]: () => [ca('DEMOROU')],
  [COTACAO.FALHOU]: () => [ca('FALHOU')],
  [COTACAO.NAO_COTA]: () => [ca('NAO_COTA')],
  [COTACAO.NAO_COMECOU]: () => [ca('NAO_COMECOU')],
};
const frases = computed(() => (FRASES[estado.value]?.() ?? []).filter(Boolean));

const COM_VARIACAO = [
  COTACAO.ENVIADA_SOZINHA,
  COTACAO.ENVIADA_POR_VOCE,
  COTACAO.ENVIADA_POR,
  COTACAO.PRONTA,
];
const variacao = computed(() => {
  if (!COM_VARIACAO.includes(estado.value)) return '';
  const mudou = variacaoDaProposta(proposta.value);
  return mudou ? tr(mudou.id, { count: mudou.count }) : '';
});

// O link do que já existe: a proposta oficial ou o resumo da cotação.
const LINKS = {
  [COTACAO.ENVIADA_SOZINHA]: 'ver-proposta',
  [COTACAO.ENVIADA_POR_VOCE]: 'ver-proposta',
  [COTACAO.ENVIADA_POR]: 'ver-proposta',
  [COTACAO.PRONTA]: 'ver-proposta',
  [COTACAO.PARCIAL]: 'ver-resumo',
};
const link = computed(() =>
  LINKS[estado.value]
    ? {
        marca: LINKS[estado.value],
        rotulo: ca(proposta.value?.oficial ? 'VER_PROPOSTA' : 'VER_RESUMO'),
      }
    : null
);

const FALTAM_DADOS = [COTACAO.FALTOU_PERGUNTADO, COTACAO.FALTOU_SEM_AGENTE];
const faltamDados = computed(() => FALTAM_DADOS.includes(estado.value));

// O rodapé da gaveta chama: confere os dados escritos e cota com eles.
defineExpose({ cotarComOsDados: () => dados.value?.cotar() });
</script>

<!-- Renovação terminada não tem cotação: o bloco some, e quem usa não precisa saber disso. -->
<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <section
    v-if="estado"
    data-carteira="cotacao"
    :data-cotacao="estado"
    :aria-labelledby="`${id}-titulo`"
    class="flex flex-col gap-3"
  >
    <h3
      :id="`${id}-titulo`"
      class="m-0 text-base font-semibold text-n-slate-12"
    >
      {{ ca('TITULO') }}
    </h3>
    <p
      v-for="frase in frases"
      :key="frase"
      :role="estado === COTACAO.COTANDO ? 'status' : undefined"
      class="m-0 text-base break-words text-n-slate-12"
    >
      {{ frase }}
    </p>
    <p v-if="variacao" class="m-0 text-base text-n-slate-11">{{ variacao }}</p>

    <RespostasDaCotacao
      v-if="estado === COTACAO.PARCIAL"
      :respostas="renovacao.respostas"
      :passou-o-prazo="Boolean(renovacao.passouOPrazo)"
      :escolhida="escolhida"
      :ocupado="ocupado"
      @pedir-proposta="emit('fazer', 'pedirProposta', { seguradora: $event })"
      @cotar-de-novo="emit('fazer', 'cotar')"
    />

    <DadosQueFaltam
      v-if="faltamDados"
      ref="dados"
      :faltou="renovacao.faltou"
      :perguntou="
        estado === COTACAO.FALTOU_PERGUNTADO ? renovacao.perguntou : ''
      "
      :preenchendo="preenchendo"
      @preencher="emit('preencher')"
      @cotar="emit('fazer', 'cotarComDados', { dados: $event })"
    />

    <div v-if="link">
      <Button
        link
        size="lg"
        :data-carteira="link.marca"
        :label="link.rotulo"
        @click="emit('verProposta')"
      />
    </div>
  </section>
</template>
