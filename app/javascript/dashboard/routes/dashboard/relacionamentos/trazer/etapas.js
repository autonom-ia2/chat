// #2894 — a máquina de etapas de "Trazer minha lista", em funções puras:
// enviar -> perguntas (zero ou mais, uma por tela) -> conferir -> trazendo ->
// pronto. `Voltar` anda uma tela para trás. Nada aqui toca em tela ou em fonte.
export const ETAPAS = {
  ENVIAR: 'enviar',
  PERGUNTAS: 'perguntas',
  CONFERIR: 'conferir',
  TRAZENDO: 'trazendo',
  PRONTO: 'pronto',
};

export const EVENTOS = {
  LEU: 'leu',
  CONTINUAR: 'continuar',
  VOLTAR: 'voltar',
  PERGUNTAS_MUDARAM: 'perguntas_mudaram',
  PERGUNTAR: 'perguntar',
  RETOMOU: 'retomou',
  TRAZER: 'trazer',
  TERMINOU: 'terminou',
  RECOMECAR: 'recomecar',
};

// As três etapas que a pessoa vê no topo. Perguntas ainda são "Enviar"; o
// andamento e o fim são "Pronto".
export const ETAPAS_DO_TOPO = [ETAPAS.ENVIAR, ETAPAS.CONFERIR, ETAPAS.PRONTO];

const PRIMEIRA_PERGUNTA = 0;

export const estadoInicial = () => ({
  etapa: ETAPAS.ENVIAR,
  pergunta: PRIMEIRA_PERGUNTA,
  totalDePerguntas: 0,
});

const em = (estado, mudanca) => ({ ...estado, ...mudanca });

const aoLer = (estado, { perguntas = 0 }) => {
  if (estado.etapa !== ETAPAS.ENVIAR) return estado;
  return perguntas > 0
    ? em(estado, {
        etapa: ETAPAS.PERGUNTAS,
        pergunta: PRIMEIRA_PERGUNTA,
        totalDePerguntas: perguntas,
      })
    : em(estado, {
        etapa: ETAPAS.CONFERIR,
        pergunta: PRIMEIRA_PERGUNTA,
        totalDePerguntas: 0,
      });
};

const aoContinuar = estado => {
  if (estado.etapa !== ETAPAS.PERGUNTAS) return estado;
  const ultima = estado.pergunta >= estado.totalDePerguntas - 1;
  return ultima
    ? em(estado, { etapa: ETAPAS.CONFERIR })
    : em(estado, { pergunta: estado.pergunta + 1 });
};

const voltarDasPerguntas = estado =>
  estado.pergunta > PRIMEIRA_PERGUNTA
    ? em(estado, { pergunta: estado.pergunta - 1 })
    : em(estado, { etapa: ETAPAS.ENVIAR });

const voltarDoConferir = estado =>
  estado.totalDePerguntas > 0
    ? em(estado, {
        etapa: ETAPAS.PERGUNTAS,
        pergunta: estado.totalDePerguntas - 1,
      })
    : em(estado, { etapa: ETAPAS.ENVIAR });

const aoVoltar = estado => {
  if (estado.etapa === ETAPAS.PERGUNTAS) return voltarDasPerguntas(estado);
  if (estado.etapa === ETAPAS.CONFERIR) return voltarDoConferir(estado);
  return estado;
};

// #2896 — uma escrita na leitura (trocar uma coluna, responder) pode mudar as
// perguntas: a do telefone some quando a pessoa manda o telefone para outra
// coluna. A conta acompanha, para o Voltar do conferir cair numa pergunta que
// existe. Quem estava numa pergunta que saiu fica na última que sobrou; sem
// nenhuma, vai conferir.
const aoMudarAsPerguntas = (estado, { perguntas = 0 }) => {
  if (estado.etapa === ETAPAS.CONFERIR) {
    return em(estado, { totalDePerguntas: perguntas });
  }
  if (estado.etapa !== ETAPAS.PERGUNTAS) return estado;
  if (perguntas === 0) {
    return em(estado, {
      etapa: ETAPAS.CONFERIR,
      pergunta: PRIMEIRA_PERGUNTA,
      totalDePerguntas: 0,
    });
  }
  return em(estado, {
    pergunta: Math.min(estado.pergunta, perguntas - 1),
    totalDePerguntas: perguntas,
  });
};

// #2896 — no conferir, uma resposta deixou de valer (a pessoa trocou a coluna
// de que ela dependia): a tela volta à pergunta que ficou sem resposta.
const aoPerguntar = (estado, { pergunta }) => {
  const existe =
    Number.isInteger(pergunta) &&
    pergunta >= PRIMEIRA_PERGUNTA &&
    pergunta < estado.totalDePerguntas;
  return estado.etapa === ETAPAS.CONFERIR && existe
    ? em(estado, { etapa: ETAPAS.PERGUNTAS, pergunta })
    : estado;
};

// #2896 — a leitura voltou do servidor fora da ordem das telas (a pessoa
// recarregou a página, ou a planilha foi lida de novo): a tela vai para onde a
// leitura pede. `pergunta` é a posição da primeira sem resposta; com todas
// respondidas (ou sem perguntas), é o conferir. Não vale depois de trazer.
const ANTES_DE_TRAZER = [ETAPAS.ENVIAR, ETAPAS.PERGUNTAS, ETAPAS.CONFERIR];

const aoRetomar = (estado, { perguntas = 0, pergunta }) => {
  if (!ANTES_DE_TRAZER.includes(estado.etapa)) return estado;
  const falta =
    Number.isInteger(pergunta) &&
    pergunta >= PRIMEIRA_PERGUNTA &&
    pergunta < perguntas;
  return falta
    ? em(estado, {
        etapa: ETAPAS.PERGUNTAS,
        pergunta,
        totalDePerguntas: perguntas,
      })
    : em(estado, {
        etapa: ETAPAS.CONFERIR,
        pergunta: PRIMEIRA_PERGUNTA,
        totalDePerguntas: perguntas,
      });
};

const quandoEstiverEm = (etapa, proxima) => estado =>
  estado.etapa === etapa ? em(estado, { etapa: proxima }) : estado;

const TRANSICOES = {
  [EVENTOS.LEU]: aoLer,
  [EVENTOS.CONTINUAR]: aoContinuar,
  [EVENTOS.VOLTAR]: aoVoltar,
  [EVENTOS.PERGUNTAS_MUDARAM]: aoMudarAsPerguntas,
  [EVENTOS.PERGUNTAR]: aoPerguntar,
  [EVENTOS.RETOMOU]: aoRetomar,
  [EVENTOS.TRAZER]: quandoEstiverEm(ETAPAS.CONFERIR, ETAPAS.TRAZENDO),
  [EVENTOS.TERMINOU]: quandoEstiverEm(ETAPAS.TRAZENDO, ETAPAS.PRONTO),
  [EVENTOS.RECOMECAR]: () => estadoInicial(),
};

// Evento fora de hora devolve o mesmo estado (nunca estoura).
export const proximo = (estado, evento) => {
  const transicao = TRANSICOES[evento?.tipo];
  return transicao ? transicao(estado, evento) : estado;
};

export const etapaDoTopo = estado => {
  if (estado.etapa === ETAPAS.PERGUNTAS) return ETAPAS.ENVIAR;
  if (estado.etapa === ETAPAS.TRAZENDO) return ETAPAS.PRONTO;
  return estado.etapa;
};
