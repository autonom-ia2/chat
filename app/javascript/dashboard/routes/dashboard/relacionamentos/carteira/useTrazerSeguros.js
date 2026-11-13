import { computed, ref, watch } from 'vue';
import { ETAPAS } from '../trazer/etapas';
import { ERROS } from '../trazer/falhasDaTela';
import {
  PERGUNTA_SEGUROS,
  destinosQueFaltam,
  numerosDosSeguros,
  segurosConferidos,
  temSeguros,
} from './segurosDaPlanilha';

// #2897 — o que "Trazer minha lista" ganha na conta que tem a carteira de
// seguros. O estado continua sendo o da tela das listas
// (trazer/useTrazerLista.js): aqui só se decide em que momentos a tela é a da
// carteira (`passo`) e o que ela pede a mais.
//   - COMO: antes de enviar, a pessoa escolhe como quer trazer (hoje, só a
//     planilha);
//   - PERGUNTA: "Esta planilha tem seguros?". A resposta vai junto das outras;
//   - CONFERIR: a planilha tem seguros. Faltando coluna obrigatória, o clique
//     em Trazer não vai ao servidor: a tela diz o que falta (`faltam`);
//   - PRONTO: a lista trouxe seguros. `chegaram` diz quantos e de quantas
//     pessoas (a conta do servidor; sem ela, a do Conferir).
// Fora desses momentos `passo` é nulo e a tela é a das listas. Na conta sem
// carteira (`ligado` falso) é sempre nulo.
export const PASSOS = {
  COMO: 'como',
  PERGUNTA: 'pergunta',
  CONFERIR: 'conferir',
  PRONTO: 'pronto',
};

export const useTrazerSeguros = ({ tela, fonte, ligado }) => {
  // A pessoa já disse como quer trazer.
  const escolheu = ref(false);
  // Quantas vezes pediu para trazer com coluna faltando (cada pedido leva o
  // foco ao aviso de novo).
  const pedidosComFalta = ref(0);
  // Os números do Conferir na hora do trazer: valem se o andamento não os diz.
  const doConferir = ref(null);

  const faltando = computed(() => destinosQueFaltam(tela.leitura.value));

  // Enviar: a escolha vem antes do arquivo, menos quando a tela já está lendo
  // ou tem um erro para dizer.
  const antesDeEnviar = () =>
    !escolheu.value && !tela.lendo.value && tela.erro.value === ERROS.NENHUM;

  const chegaram = computed(() => {
    if (tela.etapa.value !== ETAPAS.PRONTO || !doConferir.value) return null;
    return fonte.chegaram?.() ?? doConferir.value;
  });

  const naPergunta = () => tela.perguntaAtual.value?.id === PERGUNTA_SEGUROS;
  const comSeguros = () => temSeguros(tela.leitura.value);

  // O passo da carteira em cada etapa da tela das listas (falso: não há).
  const DA_ETAPA = {
    [ETAPAS.ENVIAR]: () => antesDeEnviar() && PASSOS.COMO,
    [ETAPAS.PERGUNTAS]: () => naPergunta() && PASSOS.PERGUNTA,
    [ETAPAS.CONFERIR]: () => comSeguros() && PASSOS.CONFERIR,
    [ETAPAS.PRONTO]: () => Boolean(chegaram.value) && PASSOS.PRONTO,
  };

  const passo = computed(() => {
    if (!ligado) return null;
    const etapa = tela.etapa.value;
    // A releitura que parou tem tela própria, a das listas.
    if (etapa !== ETAPAS.ENVIAR && tela.releituraParada.value) return null;
    return DA_ETAPA[etapa]?.() || null;
  });

  // Apontadas as colunas, o aviso do que faltava deixa de valer.
  watch(
    () => faltando.value.length,
    quantas => {
      if (quantas === 0) pedidosComFalta.value = 0;
    }
  );

  // De volta ao começo (a pessoa recomeçou, ou a lista parou no meio): os
  // números da lista anterior não valem para a próxima.
  watch(
    () => tela.etapa.value,
    etapa => {
      if (etapa === ETAPAS.ENVIAR) doConferir.value = null;
    }
  );

  const escolherPlanilha = () => {
    escolheu.value = true;
  };

  // Uma ação só: a resposta já segue para a próxima tela.
  const responder = valor => {
    tela.responder(PERGUNTA_SEGUROS, valor);
    return tela.continuar();
  };

  const trazer = () => {
    if (faltando.value.length > 0) {
      pedidosComFalta.value += 1;
      return undefined;
    }
    const leitura = tela.leitura.value;
    doConferir.value = segurosConferidos(leitura)
      ? numerosDosSeguros(leitura)
      : null;
    return tela.trazer();
  };

  // "Trazer outra lista": a escolha de como trazer volta a ser feita.
  const recomecar = () => {
    escolheu.value = false;
    pedidosComFalta.value = 0;
  };

  return {
    passo,
    // Os destinos obrigatórios sem coluna, depois que a pessoa pediu para
    // trazer; antes disso, nada a dizer.
    faltam: computed(() => (pedidosComFalta.value > 0 ? faltando.value : [])),
    pedidosComFalta,
    chegaram,
    escolherPlanilha,
    responder,
    trazer,
    recomecar,
  };
};
