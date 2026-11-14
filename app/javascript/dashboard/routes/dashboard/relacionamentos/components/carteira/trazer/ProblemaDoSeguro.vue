<script setup>
import { computed, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  chaveDoProblemaDoSeguro,
  ehApoliceRepetida,
} from '../../../carteira/segurosDaPlanilha';
import { doCampoDeData } from '../../../carteira/formatosDoSeguro';
import { useTextosDoSeguro } from '../../../carteira/useTextosDoSeguro';
import { SITUACAO_DO_PROBLEMA } from '../../../trazer/contagem';
import { useErroDoCartao } from '../../../trazer/useErroDoCartao';
import LinhaRecolhida from '../../trazer/problema/LinhaRecolhida.vue';
import MolduraDoCartao from '../../trazer/problema/MolduraDoCartao.vue';

// #2897 — uma linha da planilha cujo seguro não pode entrar como está. Fica na
// mesma lista "Precisam de você" das outras linhas (components/trazer/
// PrecisamDeVoce.vue, que escolhe este cartão pelo tipo do problema) e tem as
// mesmas entradas e saídas de ProblemaDaLinha.vue.
// O seguro com dado faltando ou ilegível não se conserta aqui: a frase diz o
// que há e que o conserto é na planilha; a linha só pode ficar de fora (e
// voltar atrás). A apólice que aparece em duas linhas com dados diferentes
// pede a escolha de qual fica: os dois seguros lado a lado, cada um com o que o
// distingue. A escolha já salva.
// A frase nunca repete o que estava escrito na célula com problema.
const props = defineProps({
  problema: { type: Object, required: true },
  ocupado: { type: Boolean, default: false },
  // A planilha já foi apagada do servidor: aqui não muda nada (não há conserto).
  semConserto: { type: Boolean, default: false },
  recusa: { type: Object, default: null },
});
const emit = defineEmits(['guardar', 'deixarDeFora', 'reabrir']);

const { t } = useI18n();
const textos = useTextosDoSeguro();
const BASE = 'RELACIONAMENTOS_CARTEIRA.TRAZER';

const moldura = ref(null);
const idDoErro = useId();
const { erro } = useErroDoCartao({
  recusa: () => props.recusa,
  campo: '',
  raiz: moldura,
  ocupado: () => props.ocupado,
});

const aberto = computed(
  () => props.problema.estado === SITUACAO_DO_PROBLEMA.ABERTO
);
const guardado = computed(
  () => props.problema.estado === SITUACAO_DO_PROBLEMA.GUARDADO
);
const repetida = computed(() => ehApoliceRepetida(props.problema));
// As duas linhas da apólice repetida, a outra primeiro. Sem as duas não há o
// que escolher: a linha só pode ficar de fora.
const duplicadas = computed(() => {
  const { duplicadas: linhas = [], outraLinha, linha } = props.problema;
  const achadas = [outraLinha, linha]
    .map(numero => linhas.find(item => item.linha === numero))
    .filter(Boolean);
  return repetida.value && achadas.length === 2 ? achadas : [];
});
const podeEscolher = computed(
  () => duplicadas.value.length > 0 && !props.semConserto
);

const quem = computed(
  () =>
    props.problema.nome ||
    t(`${BASE}.PRECISAM.QUEM_SEM_NOME`, { linha: props.problema.linha })
);
const chaveDoTexto = computed(() =>
  repetida.value && !aberto.value
    ? `${BASE}.PRECISAM.PROBLEMA.DUPLICADO_ESCOLHIDO`
    : chaveDoProblemaDoSeguro(props.problema)
);
const frases = computed(() => ({
  texto: t(chaveDoTexto.value, {
    quem: quem.value,
    numero: props.problema.numero,
  }),
  apoio:
    repetida.value && props.problema.outraLinha
      ? t('RELACIONAMENTOS_TRAZER.PRECISAM.LINHAS_DA_PLANILHA', {
          linha: props.problema.linha,
          outraLinha: props.problema.outraLinha,
        })
      : t('RELACIONAMENTOS_TRAZER.PRECISAM.LINHA_DA_PLANILHA', {
          linha: props.problema.linha,
        }),
}));

// O que distingue um seguro do outro: quando termina, o valor e o que está
// segurado. Só entra o que a linha tem.
const termina = dia => {
  const segundos = doCampoDeData(dia);
  return segundos === null
    ? ''
    : t(`${BASE}.CONFERIR.TERMINA_EM`, { data: textos.dataInteira(segundos) });
};
const detalhesDa = seguro =>
  [
    termina(seguro.termina),
    seguro.valor === null || seguro.valor === undefined
      ? ''
      : textos.valor(seguro.valor),
    seguro.bem ?? '',
  ].filter(Boolean);
</script>

<template>
  <li
    :data-linha="problema.linha"
    data-carteira="problema-do-seguro"
    :data-problema="problema.tipo"
    class="flex flex-col gap-4 p-5 border rounded-2xl border-n-weak bg-n-solid-1"
  >
    <LinhaRecolhida
      v-if="!aberto"
      :linha="problema.linha"
      :texto="frases.texto"
      :guardada="guardado"
      :ocupado="ocupado"
      :recusa="recusa"
      @reabrir="linha => emit('reabrir', linha)"
    />
    <MolduraDoCartao
      v-else
      ref="moldura"
      :linha="problema.linha"
      :frases="frases"
      :erro="erro"
      :id-do-erro="idDoErro"
      :ocupado="ocupado"
      @deixar-de-fora="linha => emit('deixarDeFora', linha)"
    >
      <div v-if="podeEscolher" class="grid gap-3 sm:grid-cols-2">
        <button
          v-for="seguro in duplicadas"
          :key="seguro.linha"
          type="button"
          :data-opcao="seguro.linha"
          class="flex flex-col items-start w-full gap-1 p-4 border min-h-11 text-start rounded-xl border-n-weak bg-n-alpha-1 hover:enabled:bg-n-alpha-2 disabled:opacity-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
          :disabled="ocupado"
          @click="emit('guardar', problema.linha, seguro.linha)"
        >
          <span class="text-base font-medium break-words text-n-slate-12">
            {{ seguro.seguradora }}
          </span>
          <span
            v-for="detalhe in detalhesDa(seguro)"
            :key="detalhe"
            class="text-sm break-words text-n-slate-11 tabular-nums"
          >
            {{ detalhe }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{
              t('RELACIONAMENTOS_TRAZER.PRECISAM.LINHA_DA_PLANILHA', {
                linha: seguro.linha,
              })
            }}
          </span>
          <span
            data-carteira="ficar-com-este"
            class="flex items-center gap-1 mt-1 text-sm font-medium text-n-blue-11"
          >
            {{ t(`${BASE}.PRECISAM.FICAR_COM_ESTE`) }}
            <span
              class="i-lucide-arrow-right size-4 rtl:rotate-180"
              aria-hidden="true"
            />
          </span>
        </button>
      </div>
      <p
        v-else
        data-carteira="conserto-na-planilha"
        class="m-0 text-base text-n-slate-11"
      >
        {{ t(`${BASE}.PRECISAM.CONSERTO`) }}
      </p>
    </MolduraDoCartao>
  </li>
</template>
