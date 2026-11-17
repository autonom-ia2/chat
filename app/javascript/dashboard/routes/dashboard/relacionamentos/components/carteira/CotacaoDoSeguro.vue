<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { useIdioma } from '../../ficha/idioma';
import {
  SITUACOES_DA_COTACAO as S,
  emReais,
  equipeFoiAvisada,
  mostraAProposta,
  situacaoDaCotacao,
  variacaoDaCotacao,
} from '../../carteira/cotacaoDaRenovacao';
import { useTextosDoSeguro } from '../../carteira/useTextosDoSeguro';

// #2901 (E8) — "Cotação" na gaveta do seguro (a mesma da lista, da ficha e do
// painel da conversa): em que pé está a cotação da renovação, numa frase de
// gente (nunca o código do servidor), o preço da proposta e quanto ele subiu
// ou caiu em relação ao ano passado. Com a proposta pronta e ainda não
// enviada, quem pode (carteira/cotacaoDaRenovacao.js, `podeEnviarProposta`)
// tem "Enviar proposta": nada vai ao cliente antes desse clique. Quem manda é
// a gaveta, que diz o que houve no rodapé. Só existe no seguro que tem
// cotação.
const props = defineProps({
  seguro: { type: Object, required: true },
  podeEnviar: { type: Boolean, default: false },
  enviando: { type: Boolean, default: false },
});
const emit = defineEmits(['enviar']);

const { t } = useI18n();
const tc = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.COTACAO.${chave}`, valores);
const textos = useTextosDoSeguro();
const idioma = useIdioma();
const idDoTitulo = useId();

const cotacao = computed(() => props.seguro.cotacao);
const situacao = computed(() => situacaoDaCotacao(cotacao.value));
const valor = centavos => textos.valor(emReais(centavos));

// "nascimento do segurado, CEP e placa do veículo", no idioma do painel. Dois
// campos com o mesmo nome em português aparecem uma vez só.
const emLista = nomes =>
  new Intl.ListFormat(idioma.value, { type: 'conjunction' }).format(nomes);
const camposEscritos = ({ campos, outros }) => {
  const nomes = new Set(campos.map(campo => tc(`CAMPOS.${campo}`)));
  if (outros) nomes.add(tc('OUTROS_DADOS'));
  return emLista([...nomes]);
};

const daProposta = (chave, { premioCentavos, seguradora }) =>
  seguradora
    ? tc(chave, { valor: valor(premioCentavos), seguradora })
    : tc(`${chave}_SEM_SEGURADORA`, { valor: valor(premioCentavos) });

const FRASES = {
  [S.PERGUNTA_NAO_SAIU]: () => tc('SITUACAO.PERGUNTA_NAO_SAIU'),
  [S.FALTAM]: s => tc('SITUACAO.FALTAM', { campos: camposEscritos(s) }),
  [S.NAO_SAIU]: s => tc(`MOTIVO.${s.motivo.toUpperCase()}`),
  [S.PRONTA]: s => daProposta('SITUACAO.PRONTA', s),
  [S.ENVIADA]: s =>
    tc('SITUACAO.ENVIADA', { data: textos.dataInteira(s.enviadaEm) }),
  [S.ENVIADA_SOZINHA]: s =>
    tc('SITUACAO.ENVIADA_SOZINHA', { data: textos.dataInteira(s.enviadaEm) }),
};
const frase = computed(() => {
  const escrever = FRASES[situacao.value.id];
  return escrever
    ? escrever(situacao.value)
    : tc(`SITUACAO.${situacao.value.id}`);
});

// A pergunta "Algo mudou?" que não saiu diz por quê, quando a tela sabe.
const porQueNaoSaiu = computed(() =>
  situacao.value.id === S.PERGUNTA_NAO_SAIU && situacao.value.motivo
    ? tc(`ENVIO.${situacao.value.motivo.toUpperCase()}`)
    : ''
);
const proposta = computed(() =>
  mostraAProposta(cotacao.value) ? daProposta('PROPOSTA', cotacao.value) : ''
);
const variacao = computed(() => {
  const achada = variacaoDaCotacao(cotacao.value);
  return achada
    ? tc(`VARIACAO.${achada.id}`, {
        percentual: textos.percentual(achada.percentual),
      })
    : '';
});
const avisada = computed(() => equipeFoiAvisada(situacao.value));
</script>

<template>
  <section
    v-if="situacao"
    data-carteira="cotacao-do-seguro"
    :data-etapa="cotacao.etapa"
    :aria-labelledby="idDoTitulo"
    class="flex flex-col gap-3"
  >
    <h3 :id="idDoTitulo" class="m-0 text-base font-semibold text-n-slate-12">
      {{ tc('TITULO') }}
    </h3>
    <p
      data-carteira="situacao-da-cotacao"
      class="m-0 text-base break-words text-n-slate-12"
    >
      {{ frase }}
    </p>
    <p
      v-if="porQueNaoSaiu"
      data-carteira="por-que-nao-saiu"
      class="m-0 text-base break-words text-n-slate-11"
    >
      {{ porQueNaoSaiu }}
    </p>
    <p
      v-if="proposta"
      data-carteira="proposta-da-cotacao"
      class="m-0 text-base break-words text-n-slate-11"
    >
      {{ proposta }}
    </p>
    <p
      v-if="variacao"
      data-carteira="variacao-da-cotacao"
      class="m-0 text-base break-words text-n-slate-11"
    >
      {{ variacao }}
    </p>
    <p
      v-if="avisada"
      data-carteira="equipe-avisada"
      class="m-0 text-sm break-words text-n-slate-11"
    >
      {{ tc('AVISADA') }}
    </p>
    <div v-if="podeEnviar" class="flex flex-col items-start gap-2">
      <!-- `faded`, como os botões das outras partes da gaveta: o único azul
           cheio é o do rodapé. -->
      <Button
        faded
        size="lg"
        icon="i-lucide-send"
        class="w-full sm:w-auto"
        data-carteira="enviar-proposta"
        :is-loading="enviando"
        :label="tc('ENVIAR')"
        @click="emit('enviar')"
      />
      <p class="m-0 text-sm text-n-slate-11">{{ tc('ENVIAR_APOIO') }}</p>
    </div>
  </section>
</template>
