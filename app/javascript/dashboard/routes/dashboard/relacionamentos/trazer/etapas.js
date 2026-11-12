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

const quandoEstiverEm = (etapa, proxima) => estado =>
  estado.etapa === etapa ? em(estado, { etapa: proxima }) : estado;

const TRANSICOES = {
  [EVENTOS.LEU]: aoLer,
  [EVENTOS.CONTINUAR]: aoContinuar,
  [EVENTOS.VOLTAR]: aoVoltar,
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
