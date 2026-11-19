import ContactAPI from 'dashboard/api/contacts';
import LabelsAPI from 'dashboard/api/labels';
import RelacionamentosAPI from 'dashboard/api/relacionamentos';
import { emFatias } from './emFatias';
import { ATRASO_DA_DEMO_MS, esperar, paramsDoPedido } from './listaFonte';

// #2894 — de onde as ações em grupo da lista de Relacionamentos escrevem (criar
// cards, etiquetar, apagar). Mesmo desenho de listaFonte.js: fora da
// demonstração fala com o servidor; em demonstração (`?demo=`, só em
// desenvolvimento) tudo é inventado e SÓ SIMULA, com atraso curto.
//
// As três escritas recebem { pessoas, aoAndar, deveParar } (mais o que a ação
// pede) e devolvem o mesmo formato nas duas fontes (ver emFatias.js):
//   { criados | aplicadas | tiradas | apagadas, deFora: [{ id, nome, motivo }], faltam, erro }
//
// #3062 — e o que a lista ganhou da lista de contatos de hoje:
//   - etiquetas: várias de uma vez (`etiquetas`), para pôr ou tirar;
//   - exportar(consulta): "Baixar planilha" da lista na tela. Devolve
//     { email }, para onde a planilha vai;
//   - criarPessoa(dados) e salvarPessoa(id, dados): "Nova pessoa" e "Editar"
//     da linha, com `dados` no formato do contato (ficha/informacoes.js). O que
//     o servidor recusa sobe como veio (lista/recusaDoContato.js lê o 422).
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
    tirarEtiqueta: lote => simular(lote, 'tiradas'),
    apagar: lote => simular(lote, 'apagadas'),
    async exportar() {
      await esperar(atraso);
      return { email: 'voce@exemplo.com.br' };
    },
    async criarPessoa({ name }) {
      await esperar(atraso);
      return { id: Date.now(), name };
    },
    async salvarPessoa(id, { name }) {
      await esperar(atraso);
      return { id, name };
    },
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
  // As etiquetas da conta, com a cor, pelo mesmo cliente (com cache) e na
  // mesma ordem que o resto do painel usa (store/modules/labels.js).
  async etiquetas() {
    const { data } = await LabelsAPI.get(true);
    return data.payload
      .map(({ title, color }) => ({ nome: title, cor: color }))
      .sort((a, b) => a.nome.localeCompare(b.nome));
  },
  criarCards: ({ funilId, etapaId, ...lote }) =>
    noServidor(lote, 'criados', ids =>
      RelacionamentosAPI.criarCards({
        pessoa_ids: ids,
        funil_id: funilId,
        etapa_id: etapaId,
      })
    ),
  aplicarEtiqueta: ({ etiquetas, ...lote }) =>
    noServidor(lote, 'aplicadas', ids =>
      RelacionamentosAPI.aplicarEtiqueta({ pessoa_ids: ids, etiquetas })
    ),
  tirarEtiqueta: ({ etiquetas, ...lote }) =>
    noServidor(lote, 'tiradas', ids =>
      RelacionamentosAPI.tirarEtiqueta({ pessoa_ids: ids, etiquetas })
    ),
  apagar: lote =>
    noServidor(lote, 'apagadas', ids =>
      RelacionamentosAPI.apagar({ pessoa_ids: ids })
    ),
  // A consulta da tela sem a página: a planilha leva todo mundo dela.
  async exportar(consulta) {
    const params = paramsDoPedido({ ...consulta, pagina: undefined });
    return (await RelacionamentosAPI.exportarPessoas(params)).data;
  },
  async criarPessoa(dados) {
    const { data } = await ContactAPI.create(dados);
    return data.payload.contact;
  },
  async salvarPessoa(id, dados) {
    const { data } = await ContactAPI.update(id, dados);
    return data.payload;
  },
});

export const acoesDaListaFonte = ({
  demo = null,
  carregarDemo = CARREGAR_DEMO,
  atraso = ATRASO_DA_DEMO_MS,
} = {}) =>
  demo && carregarDemo ? fonteDemo({ carregarDemo, atraso }) : fonteReal();
