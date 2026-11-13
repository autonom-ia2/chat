import { computed, ref, watch } from 'vue';
import { ETAPAS } from '../trazer/etapas';
import {
  PERGUNTA_SEGUROS,
  destinosQueFaltam,
  numerosDosSeguros,
  segurosConferidos,
  sugestoesParaConfirmar,
  temSeguros,
} from './segurosDaPlanilha';

// #2897 — o que "Trazer minha lista" ganha na conta que tem a carteira de
// seguros. O estado continua sendo o da tela das listas
// (trazer/useTrazerLista.js): aqui só se decide em que momentos a tela é a da
// carteira (`passo`) e o que ela pede a mais.
//   - PERGUNTA: "Esta planilha tem seguros?". A resposta vai junto das outras;
//   - CONFERIR: a planilha tem seguros. As colunas que o servidor sugere são
//     confirmadas de uma vez (`confirmarColunas`). Faltando coluna obrigatória,
//     o clique em Trazer não vai ao servidor: a tela diz o que falta
//     (`faltam`). Enquanto a lista é trazida a tela continua sendo o Conferir,
//     que diz que está trazendo;
//   - PRONTO: a lista trouxe seguros. `chegaram` diz quantos e de quantas
//     pessoas (a conta do servidor; sem ela, a do Conferir).
// Fora desses momentos `passo` é nulo e a tela é a das listas: o envio da
// planilha é o de sempre (só existe um jeito de trazer, a planilha). Na conta
// sem carteira (`ligado` falso) é sempre nulo.
export const PASSOS = {
  PERGUNTA: 'pergunta',
  CONFERIR: 'conferir',
  PRONTO: 'pronto',
};

export const useTrazerSeguros = ({ tela, fonte, ligado }) => {
  // Quantas vezes pediu para trazer com coluna faltando (cada pedido leva o
  // foco ao aviso de novo).
  const pedidosComFalta = ref(0);
  // A confirmação das colunas sugeridas: em voo, e se parou no meio.
  const conferindo = ref(false);
  const erroAoConferir = ref(false);
  // Os números do Conferir na hora do trazer: valem se o andamento não os diz.
  const doConferir = ref(null);

  const faltando = computed(() => destinosQueFaltam(tela.leitura.value));

  const chegaram = computed(() => {
    if (tela.etapa.value !== ETAPAS.PRONTO || !doConferir.value) return null;
    return fonte.chegaram?.() ?? doConferir.value;
  });

  const naPergunta = () => tela.perguntaAtual.value?.id === PERGUNTA_SEGUROS;
  const comSeguros = () => temSeguros(tela.leitura.value);

  // O passo da carteira em cada etapa da tela das listas (falso: não há).
  const DA_ETAPA = {
    [ETAPAS.PERGUNTAS]: () => naPergunta() && PASSOS.PERGUNTA,
    [ETAPAS.CONFERIR]: () => comSeguros() && PASSOS.CONFERIR,
    // A lista que traz seguros está sendo trazida: a tela não muda no meio.
    [ETAPAS.TRAZENDO]: () => Boolean(doConferir.value) && PASSOS.CONFERIR,
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
  // números e o erro da lista anterior não valem para a próxima.
  watch(
    () => tela.etapa.value,
    etapa => {
      if (etapa !== ETAPAS.ENVIAR) return;
      doConferir.value = null;
      erroAoConferir.value = false;
    }
  );

  // "Está certo": cada coluna sugerida vira a coluna do destino dela, uma
  // escrita de cada vez e na ordem de carteira/segurosDaPlanilha.js. A que não
  // der certo para a fila: as anteriores já estão salvas, e o "Tentar de novo"
  // manda só as que o servidor ainda sugere. Sobrando obrigatório sem coluna (a
  // sugestão não veio para ele), a tela diz qual falta.
  const confirmarColunas = async () => {
    if (conferindo.value || tela.ocupado.value) return;
    conferindo.value = true;
    erroAoConferir.value = false;
    try {
      const guardou = await sugestoesParaConfirmar(tela.leitura.value).reduce(
        async (anteriores, { coluna, destino }) =>
          (await anteriores) && tela.trocarDestino(coluna, destino),
        Promise.resolve(true)
      );
      erroAoConferir.value = !guardou;
      if (guardou && faltando.value.length > 0) pedidosComFalta.value += 1;
    } finally {
      conferindo.value = false;
    }
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

  // "Trazer outra lista": o que a tela dizia da lista anterior deixa de valer.
  const recomecar = () => {
    pedidosComFalta.value = 0;
    erroAoConferir.value = false;
  };

  return {
    passo,
    // Os destinos obrigatórios sem coluna, depois que a pessoa pediu para
    // trazer; antes disso, nada a dizer.
    faltam: computed(() => (pedidosComFalta.value > 0 ? faltando.value : [])),
    pedidosComFalta,
    conferindo,
    erroAoConferir,
    chegaram,
    confirmarColunas,
    responder,
    trazer,
    recomecar,
  };
};
