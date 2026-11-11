import {
  ATRASO_DA_DEMO_MS,
  erroFonteRealPendente,
  esperar,
} from './listaFonte';

// #2894 — de onde as ações em grupo da lista de Relacionamentos escrevem (criar
// cards, etiquetar, apagar). Mesmo desenho de listaFonte.js: em demonstração
// (`?demo=`, só em desenvolvimento) tudo é inventado e SÓ SIMULA, com atraso
// curto; fora dela, por enquanto, cada método diz `FONTE_REAL_PENDENTE`.
const CARREGAR_DEMO = import.meta.env.DEV
  ? () => import('../demo/acoesDaLista.js')
  : null;

const fonteDemo = ({ carregarDemo, atraso }) => {
  const dados = async () => {
    await esperar(atraso);
    return carregarDemo();
  };
  const naoSimulaNada = async () => {
    await esperar(atraso);
  };

  return {
    usaDemo: true,
    async funis() {
      return (await dados()).FUNIS;
    },
    async etiquetas() {
      return (await dados()).ETIQUETAS;
    },
    // Quem já tem card no funil fica de fora, com o motivo.
    async criarCards({ pessoas }) {
      const { motivoDeFicarSemCard } = await dados();
      const deFora = pessoas
        .map(pessoa => ({
          id: pessoa.id,
          nome: pessoa.name,
          motivo: motivoDeFicarSemCard(pessoa),
        }))
        .filter(item => item.motivo);
      return { criados: pessoas.length - deFora.length, deFora };
    },
    async aplicarEtiqueta({ pessoas }) {
      await naoSimulaNada();
      return { aplicadas: pessoas.length };
    },
    async apagar({ pessoas }) {
      await naoSimulaNada();
      return { apagadas: pessoas.length };
    },
  };
};

const fonteReal = () => {
  const pendente = async () => {
    throw erroFonteRealPendente();
  };
  return {
    usaDemo: false,
    funis: pendente,
    etiquetas: pendente,
    criarCards: pendente,
    aplicarEtiqueta: pendente,
    apagar: pendente,
  };
};

export const acoesDaListaFonte = ({
  demo = null,
  carregarDemo = CARREGAR_DEMO,
  atraso = ATRASO_DA_DEMO_MS,
} = {}) =>
  demo && carregarDemo ? fonteDemo({ carregarDemo, atraso }) : fonteReal();
