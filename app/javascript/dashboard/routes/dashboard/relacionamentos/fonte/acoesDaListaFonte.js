import LabelsAPI from 'dashboard/api/labels';
import RelacionamentosAPI from 'dashboard/api/relacionamentos';
import { emFatias } from './emFatias';
import { ATRASO_DA_DEMO_MS, esperar } from './listaFonte';

// #2894 — de onde as ações em grupo da lista de Relacionamentos escrevem (criar
// cards, etiquetar, apagar). Mesmo desenho de listaFonte.js: fora da
// demonstração fala com o servidor; em demonstração (`?demo=`, só em
// desenvolvimento) tudo é inventado e SÓ SIMULA, com atraso curto.
//
// As três escritas recebem { pessoas, aoAndar, deveParar } (mais o que a ação
// pede) e devolvem o mesmo formato nas duas fontes (ver emFatias.js):
//   { criados | aplicadas | apagadas, deFora: [{ id, nome, motivo }], faltam, erro }
const CARREGAR_DEMO = import.meta.env.DEV
  ? () => import('../demo/acoesDaLista.js')
  : null;

const fonteDemo = ({ carregarDemo, atraso }) => {
  const dados = async () => {
    await esperar(atraso);
    return carregarDemo();
  };
  // Cada fatia espera como uma ida ao servidor: o andamento aparece igual.
  const simular = (lote, contagem, quemFicaDeFora = () => []) =>
    emFatias({
      ...lote,
      contagem,
      mandar: async fatia => {
        await esperar(atraso);
        const deFora = quemFicaDeFora(fatia);
        return { feitas: fatia.length - deFora.length, deFora };
      },
    });

  return {
    usaDemo: true,
    async funis() {
      return (await dados()).FUNIS;
    },
    async etiquetas() {
      return (await dados()).ETIQUETAS;
    },
    // Quem já tem card no funil fica de fora, com o motivo.
    async criarCards(lote) {
      const { motivoDeFicarSemCard } = await carregarDemo();
      return simular(lote, 'criados', fatia =>
        fatia
          .map(pessoa => ({
            id: pessoa.id,
            nome: pessoa.name,
            motivo: motivoDeFicarSemCard(pessoa),
          }))
          .filter(item => item.motivo)
      );
    },
    aplicarEtiqueta: lote => simular(lote, 'aplicadas'),
    apagar: lote => simular(lote, 'apagadas'),
  };
};

// ---- fonte real ------------------------------------------------------------

// `chamar(ids)` faz o POST de uma fatia. O servidor responde a contagem da ação
// e `de_fora`; a tela lê `deFora`.
const noServidor = (lote, contagem, chamar) =>
  emFatias({
    ...lote,
    contagem,
    mandar: async fatia => {
      const { data } = await chamar(fatia.map(({ id }) => id));
      return { feitas: data[contagem], deFora: data.de_fora };
    },
  });

const fonteReal = () => ({
  usaDemo: false,
  // 401 para quem não pode ver o CRM; lista vazia com o CRM desligado.
  async funis() {
    return (await RelacionamentosAPI.funis()).data;
  },
  // As etiquetas da conta, pelo mesmo cliente (com cache) e na mesma ordem que
  // o resto do painel usa (store/modules/labels.js).
  async etiquetas() {
    const { data } = await LabelsAPI.get(true);
    return data.payload
      .map(({ title }) => title)
      .sort((a, b) => a.localeCompare(b));
  },
  criarCards: ({ funilId, etapaId, ...lote }) =>
    noServidor(lote, 'criados', ids =>
      RelacionamentosAPI.criarCards({
        pessoa_ids: ids,
        funil_id: funilId,
        etapa_id: etapaId,
      })
    ),
  aplicarEtiqueta: ({ etiqueta, ...lote }) =>
    noServidor(lote, 'aplicadas', ids =>
      RelacionamentosAPI.aplicarEtiqueta({ pessoa_ids: ids, etiqueta })
    ),
  apagar: lote =>
    noServidor(lote, 'apagadas', ids =>
      RelacionamentosAPI.apagar({ pessoa_ids: ids })
    ),
});

export const acoesDaListaFonte = ({
  demo = null,
  carregarDemo = CARREGAR_DEMO,
  atraso = ATRASO_DA_DEMO_MS,
} = {}) =>
  demo && carregarDemo ? fonteDemo({ carregarDemo, atraso }) : fonteReal();
