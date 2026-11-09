// #2775 — F6, as listas da Prospecção nova na fonte (acharFonte.js), no mesmo
// formato na demonstração e na API. A lista é o Público de Campanhas que a
// Prospecção criou; "enviada" é a lista já usada numa campanha que saiu, que
// não muda mais (a regra é do servidor, CampaignJourney::AudienceUsage).
// Na demonstração nada é gravado: pôr, tirar, devolver e copiar só simulam.
const CARREGAR_DEMO = import.meta.env.DEV
  ? () => import('../demo/acharListasDemo.js')
  : null;

const esperar = ms =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });

export const daLista = (item = {}) => ({
  id: item.id,
  nome: item.name || '',
  empresas: item.companies || 0,
  whatsapp: item.whatsapp || 0,
  email: item.email || 0,
  noCrm: item.in_crm || 0,
  enviada: item.locked === true,
  // Dos leads pedidos (empresaIds), os que já estão nesta lista.
  jaNaLista: item.already_lead_ids || [],
});

export const doMembro = (item = {}) => ({
  contatoId: item.contact_id,
  linha: item.row_number,
  nome: item.name || '',
  empresa: item.company_name || '',
  whatsapp: item.whatsapp === true,
  email: item.email === true,
  noCrm: item.in_crm === true,
  leadId: item.lead_id || null,
});

// Quem ficou de fora ao pôr numa lista, no formato do Guardar lista.
const doFora = (fora = []) =>
  fora.map(item => ({ id: item.lead_id, motivo: item.reason_code }));

// O erro da API leva o código do servidor (audience_locked, too_many_leads,
// no_rows...) e quem ficou de fora, para a tela escolher a frase.
const recusa = (erro, nome) => {
  const dados = erro?.response?.data || {};
  return Object.assign(new Error(nome), {
    codigo: dados.code || null,
    fora: doFora(dados.left_out || []),
  });
};

// Uma página das listas, da mais nova para a mais velha, por cursor: depois é
// { em, id } da última lista já mostrada (null na primeira página). Apagar uma
// lista no meio não faz pular nenhuma. temMais diz se há outra página.
export const listasDaApi = api => ({
  async listas({ depois = null, empresaIds = [] } = {}) {
    const { data } = await api.getAudiences({ depois, leadIds: empresaIds });
    const meta = data.meta || {};
    return {
      listas: (data.payload || []).map(daLista),
      temMais: meta.has_more === true,
      depois: meta.next_before_id
        ? { em: meta.next_before_at, id: meta.next_before_id }
        : null,
    };
  },
  // As empresas vêm por cursor: depois é a linha (row_number) da última
  // empresa já mostrada. Tirar alguém da página aberta não faz a próxima pular
  // ninguém, como faria um número de página.
  async lista(id, { depois = null } = {}) {
    const { data } = await api.getAudience(id, depois ? { after: depois } : {});
    const payload = data.payload || {};
    return {
      lista: daLista(payload),
      membros: (payload.members || []).map(doMembro),
      total: data.meta?.total_count || 0,
      depois: data.meta?.next_after ?? null,
      temMais: data.meta?.has_more === true,
    };
  },
  async acrescentarNaLista({ listaId, ids }) {
    try {
      const { data } = await api.addLeadsToAudience(listaId, { leadIds: ids });
      const payload = data.payload || {};
      const lista = daLista(payload.audience);
      return {
        publicoId: lista.id,
        nome: lista.nome,
        n: (payload.entered_lead_ids || []).length,
        lista,
        fora: doFora(payload.left_out),
      };
    } catch (erro) {
      throw recusa(erro, 'lista');
    }
  },
  async tirarDaLista({ listaId, contatoIds = [], empresaIds = [] }) {
    try {
      const { data } = await api.removeFromAudience(listaId, {
        contactIds: contatoIds,
        leadIds: empresaIds,
      });
      return {
        lista: daLista(data.payload?.audience),
        tirados: data.payload?.removed_contact_ids || [],
      };
    } catch (erro) {
      throw recusa(erro, 'tirar');
    }
  },
  async devolverNaLista({ listaId, contatoIds }) {
    try {
      const { data } = await api.restoreToAudience(listaId, {
        contactIds: contatoIds,
      });
      return { lista: daLista(data.payload?.audience) };
    } catch (erro) {
      throw recusa(erro, 'devolver');
    }
  },
  // deFora: quantos da original não foram para a cópia (pediram para não
  // receber ou ficaram sem telefone e sem e-mail desde então).
  async copiarLista(listaId) {
    try {
      const { data } = await api.copyAudience(listaId);
      return {
        lista: daLista(data.payload),
        deFora: (data.payload?.skipped_contact_ids || []).length,
      };
    } catch (erro) {
      throw recusa(erro, 'copiar');
    }
  },
  async listasDaEmpresa(empresaId) {
    const { data } = await api.getLeadAudiences(empresaId);
    return (data.payload || []).map(item => ({
      id: item.id,
      nome: item.name || '',
      enviada: item.locked === true,
    }));
  },
});

export const listasDaDemo = ({
  estado,
  atraso,
  carregarDemo = CARREGAR_DEMO,
}) => {
  const dados = async () => (carregarDemo ? carregarDemo() : { LISTAS: [] });
  const falha = () =>
    Object.assign(new Error('demo'), { codigo: null, fora: [] });
  return {
    async listas() {
      const demo = await dados();
      if (estado === 'listas-erro') throw falha();
      if (estado === 'listas-vazio') {
        return { listas: [], temMais: false, depois: null };
      }
      return { listas: demo.LISTAS.map(daLista), temMais: false, depois: null };
    },
    async lista(id) {
      const demo = await dados();
      const item = demo.LISTAS.find(lista => String(lista.id) === String(id));
      if (!item || estado === 'lista-erro') throw falha();
      return {
        lista: daLista(item),
        membros: demo.MEMBROS.map(doMembro),
        total: demo.MEMBROS.length,
        depois: null,
        temMais: false,
      };
    },
    async acrescentarNaLista({ listaId, ids }) {
      const demo = await dados();
      await esperar(atraso * 2);
      const item = demo.LISTAS.find(lista => lista.id === listaId) || {};
      const lista = daLista({
        ...item,
        companies: (item.companies || 0) + ids.length,
      });
      return { publicoId: lista.id, nome: lista.nome, n: ids.length, lista };
    },
    async tirarDaLista() {
      await esperar(atraso);
      return { lista: null, tirados: [] };
    },
    async devolverNaLista() {
      await esperar(atraso);
      return { lista: null };
    },
    async copiarLista(listaId) {
      const demo = await dados();
      await esperar(atraso);
      const item = demo.LISTAS.find(lista => lista.id === listaId) || {};
      const lista = daLista({
        ...item,
        id: demo.COPIA_ID,
        name: `${item.name} (cópia)`,
        locked: false,
      });
      return { lista, deFora: 0 };
    },
    async listasDaEmpresa() {
      const demo = await dados();
      if (estado === 'gaveta-sem-lista') return [];
      return demo.LISTAS_DA_EMPRESA;
    },
  };
};
