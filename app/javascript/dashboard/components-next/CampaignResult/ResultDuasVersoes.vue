<script setup>
// #3099 (F3 do épico #3095) — o resultado das duas versões da mensagem, em linguagem simples. Fica no Resultado da
// campanha (abaixo dos números de envio) e no histórico da Automação livre (`naAutomacao`).
//
// Uma frase diz em que pé está ("Testando. A melhor vai para as outras 1.080 pessoas hoje, às 15:40", "Escolha qual
// vai para as outras 1.080 pessoas", "A versão 2 foi para as outras 1.080 pessoas"), com a hora no fuso da conta;
// outra diz quem foi melhor e quanto ("A versão 2 teve o dobro de respostas", vencedora.js). Teste que não chegou a
// ninguém é falha: faixa âmbar, sem vencedora. Cada versão num cartão (CartaoDaVersao). Enquanto o teste roda ou espera a pessoa, quem pode disparar
// escolhe à mão; a confirmação fica no próprio cartão.
//
// `teste`: { estado: 'testando' | 'esperando_voce' | 'escolhida' | 'todos', criterio, escolhe_em (epoch),
//   vencedora (1 | 2 | null), escolhida_por ('sistema' | 'voce' | 'empate' | 'sem_envio'), escolhida_em (epoch), resto,
//   sem_envio_ate (epoch: ninguém do teste recebeu; a hora em que a versão 1 vai para o resto),
//   vai_sozinha_em (epoch: "eu escolho" esperando; a hora em que a versão 1 vai sozinha para o resto),
//   faltam e espera em horas (automação), versoes: [{ numero, texto, receberam, responderam, compraram, valor: [{ currency, cents }] | null }] }
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import CartaoDaVersao from './CartaoDaVersao.vue';
import { wonValueText } from './resultMetrics';
import { diaFalado, quandoFalado, useFusoDaConta } from './quandoNaConta';
import { compararVersoes, deCadaCem, fraseDoCriterio } from './vencedora';
import {
  MINIMO_POR_VERSAO,
  esperaPadrao,
} from 'dashboard/components-next/CampaignJourney/duasVersoes';

const props = defineProps({
  teste: { type: Object, default: null },
  naAutomacao: { type: Boolean, default: false },
  podeEscolher: { type: Boolean, default: false },
  carregando: { type: Boolean, default: false },
  // O número da versão que está indo para o resto (depois do "Sim, mandar"), enquanto a resposta não chega.
  enviando: { type: Number, default: null },
});
const emit = defineEmits(['escolher', 'recarregar']);

const NS = 'DUAS_VERSOES.RESULTADO';
const NS_AUTO = `${NS}.AUTOMACAO`;
const { t, locale } = useI18n();
const fuso = useFusoDaConta();
const idioma = computed(() => locale.value.replace('_', '-'));
const inteiro = numero =>
  new Intl.NumberFormat(idioma.value).format(numero ?? 0);

const estado = computed(() => props.teste?.estado);
const criterio = computed(() => props.teste?.criterio || 'respostas');
const versoes = computed(() => props.teste?.versoes || []);
const resto = computed(() => inteiro(props.teste?.resto));
const escolhida = computed(() => estado.value === 'escolhida');
const vencedora = computed(() => props.teste?.vencedora ?? 1);
const daParaEscolher = computed(() =>
  ['testando', 'esperando_voce'].includes(estado.value)
);
// O teste não chegou a ninguém (passada a espera, ou a versão 1 já foi por isso): é falha, não vitória.
const semEnvio = computed(
  () =>
    (estado.value === 'testando' && Boolean(props.teste?.sem_envio_ate)) ||
    (escolhida.value && props.teste?.escolhida_por === 'sem_envio')
);

const comparacao = computed(() =>
  compararVersoes(versoes.value[0], versoes.value[1], criterio.value)
);
const fraseDaComparacao = computed(() => {
  const { chave, melhor, vezes } = comparacao.value;
  const frase = t(`${NS}.FRASE.${fraseDoCriterio(criterio.value)}.${chave}`, {
    n: melhor,
    vezes,
  });
  if (estado.value !== 'testando') return frase;
  // "Até agora, a versão 2…": a frase entra no meio, com a inicial minúscula.
  const meio = frase.charAt(0).toLocaleLowerCase(idioma.value) + frase.slice(1);
  return t(`${NS}.ATE_AGORA`, { frase: meio });
});
// No empate já escolhido, a faixa já diz que as duas ficaram parecidas: a frase grande repetiria. Sem envio no
// teste, não há o que comparar.
const mostraComparacao = computed(
  () =>
    !semEnvio.value &&
    !(escolhida.value && props.teste?.escolhida_por === 'empate')
);

const quando = epoch =>
  quandoFalado(epoch, { fuso: fuso.value, locale: locale.value, t });
const dia = epoch =>
  diaFalado(epoch, { fuso: fuso.value, locale: locale.value });

const situacaoDaCampanha = () => {
  const euEscolho = criterio.value === 'eu_escolho';
  if (estado.value === 'testando' && props.teste.sem_envio_ate)
    return t(`${NS}.TESTANDO_SEM_ENVIO`, {
      quando: quando(props.teste.sem_envio_ate),
      resto: resto.value,
    });
  if (estado.value === 'testando')
    return t(euEscolho ? `${NS}.TESTANDO_EU_ESCOLHO` : `${NS}.TESTANDO`, {
      quando: quando(props.teste.escolhe_em),
      resto: resto.value,
    });
  if (estado.value === 'esperando_voce')
    return t(`${NS}.ESPERANDO_VOCE`, { resto: resto.value });
  if (escolhida.value) {
    const por = { voce: 'VOCE', empate: 'EMPATE', sem_envio: 'SEM_ENVIO' }[
      props.teste.escolhida_por
    ];
    return t(`${NS}.ESCOLHIDA_${por || 'SISTEMA'}`, {
      n: vencedora.value,
      resto: resto.value,
    });
  }
  return t(`${NS}.TODOS`);
};
const horas = n => t('DUAS_VERSOES.REGRA.HORAS', { n: inteiro(n) }, n);
const situacaoDaAutomacao = () => {
  if (estado.value === 'testando')
    return t(
      criterio.value === 'eu_escolho'
        ? `${NS_AUTO}.TESTANDO_EU_ESCOLHO`
        : `${NS_AUTO}.TESTANDO`,
      {
        minimo: inteiro(MINIMO_POR_VERSAO),
        horas: horas(props.teste.espera ?? esperaPadrao(criterio.value)),
      }
    );
  if (estado.value === 'esperando_voce') return t(`${NS_AUTO}.ESPERANDO_VOCE`);
  const empate = props.teste.escolhida_por === 'empate';
  return t(empate ? `${NS_AUTO}.ESCOLHIDA_EMPATE` : `${NS_AUTO}.ESCOLHIDA`, {
    data: dia(props.teste.escolhida_em),
    n: vencedora.value,
  });
};
const situacao = computed(() =>
  props.naAutomacao ? situacaoDaAutomacao() : situacaoDaCampanha()
);
const faltam = computed(() => props.teste?.faltam ?? 0);
// Na campanha, o "eu escolho" esperando diz até quando: depois, a versão 1 vai sozinha (o servidor manda a hora).
const sozinha = computed(() =>
  !props.naAutomacao &&
  estado.value === 'esperando_voce' &&
  props.teste?.vai_sozinha_em
    ? t(`${NS}.SOZINHA`, { quando: quando(props.teste.vai_sozinha_em) })
    : ''
);
// A versão mais longe do mínimo: é por ela que o teste espera.
const versaoQueFalta = computed(
  () =>
    [...versoes.value].sort(
      (a, b) => (a.receberam ?? 0) - (b.receberam ?? 0)
    )[0]?.numero ?? 1
);

// O teste dura horas: relógio, não um ícone girando de "carregando".
const ICONES = {
  testando: 'i-lucide-clock',
  esperando_voce: 'i-lucide-hand',
  escolhida: 'i-lucide-circle-check',
  todos: 'i-lucide-users',
};
const FAIXAS = {
  esperando_voce: 'bg-n-amber-2 text-n-amber-12',
  escolhida: 'bg-n-teal-2 text-n-teal-12',
};
const FAIXA_DE_FALHA = 'bg-n-amber-2 text-n-amber-12';
const faixa = computed(() =>
  semEnvio.value
    ? FAIXA_DE_FALHA
    : FAIXAS[estado.value] || 'bg-n-alpha-1 text-n-slate-12'
);
const icone = computed(() =>
  semEnvio.value ? 'i-lucide-triangle-alert' : ICONES[estado.value]
);

const respostasCem = computed(() =>
  deCadaCem(versoes.value[0], versoes.value[1], 'respostas')
);
const comprasCem = computed(() =>
  deCadaCem(versoes.value[0], versoes.value[1], 'compras')
);
const mostraCompras = computed(
  () =>
    criterio.value === 'compras' ||
    versoes.value.some(versao => (versao.compraram ?? 0) > 0)
);
const deCada = (cem, numero) =>
  t(`${NS}.DE_CADA`, { escala: inteiro(cem.escala), n: inteiro(cem[numero]) });

// Na campanha, os cartões contam só o teste (135), e o topo mostra o público inteiro (1.350).
const rotuloReceberam = computed(() =>
  props.naAutomacao || estado.value === 'todos'
    ? t(`${NS}.RECEBERAM`)
    : t(`${NS}.RECEBERAM_NO_TESTE`)
);
// Ninguém recebeu esta versão: "0 de cada 100" não diz nada. Testando sem falha, ainda pode chegar.
const ninguemRecebeu = computed(() =>
  estado.value === 'testando' && !semEnvio.value
    ? t(`${NS}.NINGUEM_RECEBEU_AINDA`)
    : t(`${NS}.NINGUEM_RECEBEU`)
);
const linhasDa = versao => {
  if (!versao.receberam) return [];
  const linhas = [
    {
      chave: 'receberam',
      rotulo: rotuloReceberam.value,
      valor: inteiro(versao.receberam),
    },
    {
      chave: 'responderam',
      rotulo: t(`${NS}.RESPONDERAM`),
      valor: inteiro(versao.responderam),
      apoio: deCada(respostasCem.value, versao.numero),
      forte: criterio.value !== 'compras',
    },
  ];
  if (!mostraCompras.value) return linhas;
  const dinheiro = wonValueText(versao.valor, idioma.value);
  // Cada apoio numa linha: o valor em R$ não quebra espremido embaixo do número.
  const apoio = [
    deCada(comprasCem.value, versao.numero),
    dinheiro && t(`${NS}.VALOR`, { valor: dinheiro }),
  ].filter(Boolean);
  return [
    ...linhas,
    {
      chave: 'compraram',
      rotulo: t(`${NS}.COMPRARAM`),
      valor: inteiro(versao.compraram),
      apoio,
      forte: criterio.value === 'compras',
    },
  ];
};

const seloDa = numero => {
  if (semEnvio.value) return '';
  if (escolhida.value) {
    if (numero !== vencedora.value) return '';
    if (props.naAutomacao) return t(`${NS_AUTO}.FICOU`);
    return props.teste.escolhida_por === 'sistema'
      ? t(`${NS}.GANHOU`)
      : t(`${NS}.FOI_PARA_O_RESTO`);
  }
  return comparacao.value.melhor === numero ? t(`${NS}.NA_FRENTE`) : '';
};

// Troféu só para quem ganhou (pelo sistema) ou ficou (automação); empate e escolha à mão levam o "send".
const iconeDoSelo = computed(() =>
  props.naAutomacao || props.teste?.escolhida_por === 'sistema'
    ? 'i-lucide-trophy'
    : 'i-lucide-send'
);

const cartoes = computed(() =>
  versoes.value.map(versao => ({
    numero: versao.numero,
    texto: versao.texto,
    linhas: linhasDa(versao),
    vazio: versao.receberam ? '' : ninguemRecebeu.value,
    selo: seloDa(versao.numero),
    iconeDoSelo: iconeDoSelo.value,
    destaque:
      !semEnvio.value && escolhida.value && versao.numero === vencedora.value,
    principal:
      !semEnvio.value &&
      !escolhida.value &&
      comparacao.value.melhor === versao.numero,
  }))
);

const botao = computed(() => {
  if (!props.podeEscolher || !daParaEscolher.value) return null;
  const ns = props.naAutomacao ? NS_AUTO : NS;
  return {
    rotulo: t(`${ns}.ESCOLHER`),
    aria: numero => t(`${ns}.ESCOLHER_ARIA`, { n: numero }),
    sim: t(`${ns}.CONFIRMAR_SIM`),
    pergunta: numero => t(`${ns}.CONFIRMAR`, { n: numero, resto: resto.value }),
    aviso: props.naAutomacao ? '' : t(`${NS}.CONFIRMAR_AVISO`),
  };
});
// Quem não pode escolher fica sabendo a quem pedir; testando, só daria para adiantar a escolha.
const semPermissao = computed(() => {
  const ns = props.naAutomacao ? NS_AUTO : NS;
  return estado.value === 'testando'
    ? t(`${ns}.SEM_PERMISSAO_TESTANDO`)
    : t(`${ns}.SEM_PERMISSAO`);
});
</script>

<template>
  <section
    class="flex flex-col gap-5 rounded-2xl border border-n-weak bg-n-solid-1 p-5"
    :aria-busy="carregando"
    data-duas-versoes-resultado
  >
    <h2
      class="m-0 flex items-center gap-2 text-base font-semibold text-n-slate-12"
    >
      <span class="i-lucide-split size-4 text-n-slate-11" aria-hidden="true" />
      {{ t(`${NS}.TITULO`) }}
    </h2>

    <template v-if="carregando">
      <span class="sr-only" role="status">{{ t(`${NS}.CARREGANDO`) }}</span>
      <div class="h-5 w-2/3 animate-pulse rounded-lg bg-n-alpha-2" />
      <div class="grid gap-3 sm:grid-cols-2">
        <div class="h-56 animate-pulse rounded-2xl bg-n-alpha-2" />
        <div class="h-56 animate-pulse rounded-2xl bg-n-alpha-2" />
      </div>
    </template>

    <template v-else-if="teste">
      <div class="flex flex-col gap-2">
        <p
          role="status"
          class="m-0 flex items-start gap-2 rounded-xl px-4 py-3 text-sm"
          :class="faixa"
          :data-situacao="estado"
          :data-sem-envio="semEnvio || null"
        >
          <span
            class="mt-0.5 size-4 shrink-0"
            :class="icone"
            aria-hidden="true"
          />
          <span class="flex flex-col gap-0.5">
            <span>{{ situacao }}</span>
            <span v-if="sozinha" class="text-xs" data-vai-sozinha>
              {{ sozinha }}
            </span>
            <span
              v-if="naAutomacao && estado === 'testando' && faltam > 0"
              class="text-xs text-n-slate-11"
              data-faltam
            >
              {{
                t(
                  `${NS_AUTO}.FALTAM`,
                  { n: inteiro(faltam), versao: versaoQueFalta },
                  faltam
                )
              }}
            </span>
          </span>
        </p>
        <p
          v-if="mostraComparacao"
          class="m-0 text-lg font-semibold text-n-slate-12"
          :data-comparacao="comparacao.chave"
        >
          {{ fraseDaComparacao }}
        </p>
      </div>

      <div class="grid gap-3 sm:grid-cols-2">
        <CartaoDaVersao
          v-for="cartao in cartoes"
          :key="cartao.numero"
          v-bind="cartao"
          :botao="botao?.rotulo || ''"
          :botao-aria="botao ? botao.aria(cartao.numero) : ''"
          :pergunta="botao ? botao.pergunta(cartao.numero) : ''"
          :aviso="botao?.aviso || ''"
          :sim="botao?.sim || ''"
          :enviando="enviando === cartao.numero"
          @escolher="numero => emit('escolher', numero)"
        />
      </div>

      <p
        v-if="daParaEscolher && !podeEscolher"
        class="m-0 text-xs text-n-slate-11"
        data-sem-permissao
      >
        {{ semPermissao }}
      </p>
    </template>

    <div
      v-else
      role="alert"
      class="flex flex-wrap items-center justify-between gap-3 rounded-xl bg-n-alpha-1 px-4 py-3"
      data-erro-duas-versoes
    >
      <p class="m-0 text-sm text-n-slate-12">{{ t(`${NS}.ERRO`) }}</p>
      <Button
        :label="t(`${NS}.TENTAR_DE_NOVO`)"
        icon="i-lucide-refresh-cw"
        variant="ghost"
        size="sm"
        class="!min-h-11"
        @click="emit('recarregar')"
      />
    </div>
  </section>
</template>
