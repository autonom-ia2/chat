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
  chamadas: item.called || 0,
  enviada: item.locked === true,
});

export const doMembro = (item = {}) => ({
  contatoId: item.contact_id,
  linha: item.row_number,
  nome: item.name || '',
  empresa: item.company_name || '',
  whatsapp: item.whatsapp === true,
  email: item.email === true,
  noCrm: item.in_crm === true,
  chamada: item.called === true,
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

export const listasDaApi = api => ({
  async listas() {
    const { data } = await api.getAudiences({ page: 1 });
    return (data.payload || []).map(daLista);
  },
  async lista(id, pagina = 1) {
    const { data } = await api.getAudience(id, { page: pagina });
    const payload = data.payload || {};
    return {
      lista: daLista(payload),
      membros: (payload.members || []).map(doMembro),
      total: data.meta?.total_count || 0,
      porPagina: data.meta?.per_page || 25,
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
  async copiarLista(listaId) {
    const { data } = await api.copyAudience(listaId);
    return daLista(data.payload);
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
      if (estado === 'listas-vazio') return [];
      return demo.LISTAS.map(daLista);
    },
    async lista(id) {
      const demo = await dados();
      const item = demo.LISTAS.find(lista => String(lista.id) === String(id));
      if (!item || estado === 'lista-erro') throw falha();
      return {
        lista: daLista(item),
        membros: demo.MEMBROS.map(doMembro),
        total: demo.MEMBROS.length,
        porPagina: 25,
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
      return daLista({
        ...item,
        id: demo.COPIA_ID,
        name: `${item.name} (cópia)`,
        locked: false,
      });
    },
    async listasDaEmpresa() {
      const demo = await dados();
      if (estado === 'gaveta-sem-lista') return [];
      return demo.LISTAS_DA_EMPRESA;
    },
  };
};
