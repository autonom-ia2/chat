<script setup>
import { computed, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  COTACAO,
  contarRespostas,
  cotacaoDoCard,
} from '../../../carteira/cotacaoDoCard';
import { variacaoDaProposta } from '../../../carteira/situacaoDoSeguro';
import { useTextosDoSeguro } from '../../../carteira/useTextosDoSeguro';

// #2897 — a cotação dentro da renovação, num estado de cada vez
// (carteira/cotacaoDoCard.js): o que já se sabe em uma ou duas frases e, quando
// há o que fazer, UM botão. "Enviar" não mora aqui: é a ação principal da
// gaveta, no rodapé. Nenhum botão fica desligado por falta de preenchimento.
const props = defineProps({
  seguro: { type: Object, required: true },
  cotaSozinha: { type: Boolean, default: false },
  // O nome da ação que está rodando ('' = nenhuma).
  ocupado: { type: String, default: '' },
  agora: { type: Number, default: () => Date.now() },
});
const emit = defineEmits([
  'fazer',
  'verProposta',
  'conversar',
  'porTelefone',
  'entrarNoAgger',
]);

const { t } = useI18n();
const tc = (chave, valores, plural) =>
  t(`RELACIONAMENTOS_CARTEIRA.RENOVACAO.COTACAO.${chave}`, valores, plural);
const tr = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.GAVETA.RENOVACAO.${chave}`, valores);
const textos = useTextosDoSeguro();
const id = useId();

const estado = computed(() =>
  cotacaoDoCard(props.seguro, { cotaSozinha: props.cotaSozinha })
);
const renovacao = computed(() => props.seguro.renovacao);
const proposta = computed(() => renovacao.value.proposta);
const nome = computed(() => props.seguro.pessoa.name.split(' ')[0]);
const daProposta = () => ({
  seguradora: proposta.value.seguradora ?? props.seguro.seguradora,
  valor: textos.valor(proposta.value.valor),
});
const doEnvio = () => ({
  nome: proposta.value.enviadaPor,
  data: textos.diaMes(proposta.value.enviadaEm, props.agora),
  hora: textos.hora(proposta.value.enviadaEm),
});
const faltou = () =>
  tc('FALTOU', {
    dado: tc(`DADO.${renovacao.value.faltou.toUpperCase()}`),
    nome: nome.value,
  });
const jaResponderam = () => {
  const { deram, faltam } = contarRespostas(renovacao.value.respostas);
  return [
    tc('JA_DERAM', { count: deram }, deram),
    faltam ? tc('AINDA_NAO', { count: faltam }, faltam) : '',
  ];
};

const FRASES = {
  [COTACAO.ENVIADA_SOZINHA]: () => [tc('ENVIADA_SOZINHA', doEnvio())],
  [COTACAO.ENVIADA_POR_VOCE]: () => [tc('ENVIADA_POR_VOCE', doEnvio())],
  [COTACAO.ENVIADA_POR]: () => [tc('ENVIADA_POR', doEnvio())],
  [COTACAO.SEM_TELEFONE]: () => [tc('SEM_TELEFONE', { nome: nome.value })],
  [COTACAO.NAO_QUER]: () => [tc('NAO_QUER', { nome: nome.value })],
  [COTACAO.PRECO_SEM_PDF]: () => [tc('PRECO_SEM_PDF', daProposta())],
  [COTACAO.PRONTA]: () => [
    tc(
      proposta.value.oficial ? 'PRONTA_PROPOSTA' : 'PRONTA_RESUMO',
      daProposta()
    ),
  ],
  [COTACAO.PARCIAL]: jaResponderam,
  [COTACAO.COTANDO]: () => [tr('COTANDO')],
  [COTACAO.AGGER_FORA]: () => [tc('AGGER_FORA')],
  [COTACAO.DEMOROU]: () => [tc('DEMOROU')],
  [COTACAO.FALHOU]: () => [tc('FALHOU')],
  [COTACAO.FALTOU_PERGUNTADO]: () => [
    faltou(),
    tc('JA_PERGUNTOU', { agente: renovacao.value.perguntou }),
  ],
  [COTACAO.FALTOU_SEM_AGENTE]: () => [faltou(), tc('PERGUNTE')],
  [COTACAO.NAO_COTA]: () => [tc('NAO_COTA')],
  [COTACAO.NAO_COMECOU]: () => [tc('NAO_COMECOU')],
};
const frases = computed(() => FRASES[estado.value]().filter(Boolean));

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

// ---- o dado que faltou, escrito por quem perguntou à pessoa
const dado = ref('');
const faltaODado = ref(false);
const cotarComDado = () => {
  const valor = dado.value.trim();
  faltaODado.value = !valor;
  if (faltaODado.value) document.getElementById(`${id}-dado`)?.focus();
  else emit('fazer', 'cotarComDado', { valor });
};
watch(dado, () => {
  faltaODado.value = false;
});

// ---- o botão de cada estado (um só)
const verProposta = marca => ({
  marca,
  rotulo: tc(proposta.value?.oficial ? 'VER_PROPOSTA' : 'VER_RESUMO'),
  discreto: true,
  aoClicar: () => emit('verProposta'),
});
const fazer = (marca, chave, nomeDaAcao) => ({
  marca,
  rotulo: tc(chave),
  ocupado: props.ocupado === nomeDaAcao,
  aoClicar: () => emit('fazer', nomeDaAcao),
});
const BOTOES = {
  [COTACAO.ENVIADA_SOZINHA]: () => verProposta('ver-proposta'),
  [COTACAO.ENVIADA_POR_VOCE]: () => verProposta('ver-proposta'),
  [COTACAO.ENVIADA_POR]: () => verProposta('ver-proposta'),
  [COTACAO.PRONTA]: () => verProposta('ver-proposta'),
  [COTACAO.PARCIAL]: () => verProposta('ver-resumo'),
  [COTACAO.SEM_TELEFONE]: () => ({
    marca: 'por-o-telefone',
    rotulo: tc('POR_O_TELEFONE'),
    aoClicar: () => emit('porTelefone'),
  }),
  [COTACAO.NAO_QUER]: () => ({
    marca: 'conversar-sobre-a-proposta',
    rotulo: tc('CONVERSAR'),
    aoClicar: () => emit('conversar'),
  }),
  [COTACAO.PRECO_SEM_PDF]: () => fazer('pedir-pdf', 'PEDIR_PDF', 'pedirPdf'),
  [COTACAO.AGGER_FORA]: () => ({
    marca: 'entrar-no-agger',
    rotulo: tc('ENTRAR_NO_AGGER'),
    aoClicar: () => emit('entrarNoAgger'),
  }),
  [COTACAO.DEMOROU]: () => fazer('cotar-de-novo', 'COTAR_DE_NOVO', 'cotar'),
  [COTACAO.FALHOU]: () => fazer('cotar-de-novo', 'COTAR_DE_NOVO', 'cotar'),
  [COTACAO.FALTOU_SEM_AGENTE]: () => ({
    marca: 'cotar-com-dado',
    rotulo: tc('COTAR_COM_DADO'),
    ocupado: props.ocupado === 'cotarComDado',
    aoClicar: cotarComDado,
  }),
  [COTACAO.NAO_COTA]: () =>
    fazer('anexar-proposta', 'ANEXAR_PROPOSTA', 'anexarProposta'),
  [COTACAO.NAO_COMECOU]: () => ({
    marca: 'cotar-agora',
    rotulo: tr('COTAR_AGORA'),
    ocupado: props.ocupado === 'cotar',
    aoClicar: () => emit('fazer', 'cotar'),
  }),
};
const botao = computed(() => BOTOES[estado.value]?.() ?? null);

const respostas = computed(() =>
  estado.value === COTACAO.PARCIAL ? renovacao.value.respostas : []
);
</script>

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
      {{ tc('TITULO') }}
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

    <ul
      v-if="respostas.length"
      data-carteira="respostas-da-cotacao"
      class="flex flex-col p-0 m-0 list-none divide-y divide-n-weak"
    >
      <li
        v-for="resposta in respostas"
        :key="resposta.nome"
        class="flex flex-col gap-2 py-3"
      >
        <div class="flex flex-wrap items-baseline justify-between gap-x-3">
          <span class="text-base font-medium text-n-slate-12">
            {{ resposta.nome }}
          </span>
          <span class="text-base tabular-nums text-n-slate-11">
            {{
              resposta.valor === null
                ? tc('AINDA_NAO_RESPONDEU')
                : textos.valor(resposta.valor)
            }}
          </span>
        </div>
        <p v-if="resposta.semPdf" class="m-0 text-sm text-n-slate-11">
          {{ tc('SEM_PDF_DE_PROPOSTA') }}
        </p>
        <div v-else-if="resposta.valor !== null">
          <Button
            slate
            faded
            size="lg"
            data-carteira="pedir-proposta"
            :aria-label="tc('PEDIR_PROPOSTA_DE', { seguradora: resposta.nome })"
            :is-loading="ocupado === 'pedirProposta'"
            :label="tc('PEDIR_PROPOSTA')"
            @click="
              emit('fazer', 'pedirProposta', { seguradora: resposta.nome })
            "
          />
        </div>
      </li>
    </ul>

    <div
      v-if="estado === COTACAO.FALTOU_SEM_AGENTE"
      class="flex flex-col gap-2"
    >
      <label :for="`${id}-dado`" class="text-base text-n-slate-12">
        {{
          tc(`ROTULO_DO_DADO.${renovacao.faltou.toUpperCase()}`, {
            nome,
          })
        }}
      </label>
      <input
        :id="`${id}-dado`"
        v-model="dado"
        type="text"
        data-carteira="dado-que-faltou"
        :aria-invalid="faltaODado ? 'true' : undefined"
        :aria-describedby="faltaODado ? `${id}-falta` : undefined"
        class="block w-full px-3 text-base border-0 rounded-lg h-11 reset-base outline outline-1 outline-offset-[-1px] bg-n-alpha-black2 text-n-slate-12 focus:outline-n-brand"
        :class="faltaODado ? 'outline-n-ruby-8' : 'outline-n-weak'"
      />
      <p
        v-if="faltaODado"
        :id="`${id}-falta`"
        role="alert"
        class="m-0 text-base font-medium text-n-ruby-11"
      >
        {{ tc('FALTA_O_DADO') }}
      </p>
    </div>

    <div v-if="botao">
      <Button
        :link="botao.discreto"
        :slate="!botao.discreto"
        :faded="!botao.discreto"
        size="lg"
        :data-carteira="botao.marca"
        :is-loading="Boolean(botao.ocupado)"
        :label="botao.rotulo"
        @click="botao.aoClicar"
      />
    </div>
  </section>
</template>
