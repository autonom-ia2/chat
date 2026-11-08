import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { sendInBatches, CRM_BATCH_SIZE } from '../../utils/crmSend';
import { buscaDoPayload, empresaDoLead } from './acharLead';
import { montarPedido, pedidoDeNovo, pedidoSalvoDe } from './acharPedido';
import { demoPedido } from './acharRotas';

// #2692 — de onde a Prospecção nova lê (molde: agentes/utils/desempenhoFonte.js).
// A tela recebe sempre o mesmo formato (acharLead.js), venha de onde vier:
//   1. API de hoje (autonomiaProspecting.js), o padrão;
//   2. demonstração: com `?demo=<estado>` no endereço e só no ambiente de
//      desenvolvimento. Os dados são inventados (demo/acharDemo.js) e nada é
//      gravado: mandar ao funil e guardar a lista só simulam.
// O `import.meta.env.DEV` vira `false` no build de produção: o ramo some, a
// demonstração nem entra no pacote e o `?demo=` é ignorado.
const CARREGAR_DEMO = import.meta.env.DEV
  ? () => import('../demo/acharDemo.js')
  : null;

// Quem decide se o ?demo= vale mora em acharRotas.js (a rota da fila também
// usa, sem puxar a fonte para o pacote das rotas).
export { demoPedido };

const esperar = ms =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });

const UM_DIA = 24 * 60 * 60 * 1000;
const diasDesde = data =>
  data ? Math.max(0, Math.floor((Date.now() - new Date(data)) / UM_DIA)) : 0;

const ESTADOS_SEM_BUSCAS = ['buscas-vazio', 'buscas-so-ver-vazio'];
const ESTADOS_SEM_FILA = ['fila-vazia', 'fila-vazia-so-ver'];
const ESTADOS_COM_DOIS_FUNIS = ['folha-sem-destino', 'folha-para-onde'];
// Antes de a pessoa tirar alguém, a lista vem inteira; da jornada em diante
// (confira-tirou, gaveta, folha, pronto) as 2 tiradas ficam em "Não vai".
const ANTES_DE_TIRAR = ['buscando', 'chegando', 'confira', 'leitura'];
const comTiradas = estado =>
  estado === 'confira-tirou' ||
  !ANTES_DE_TIRAR.some(
    prefixo => estado === prefixo || estado.startsWith(`${prefixo}-`)
  );

// Na demonstração, a 2ª empresa tem o contato dividido com outra e a 5ª já
// tinha contato com outro nome; as outras trocam o contato.
const RESULTADO_DA_DEMO = {
  2: 'shared_with_other_lead',
  5: 'kept_existing_contact',
};

const salvarArquivo = (blob, nome) => {
  const link = document.createElement('a');
  link.href = URL.createObjectURL(blob);
  link.download = nome;
  link.click();
  URL.revokeObjectURL(link.href);
};

// O resumo do envio ao funil, igual na demonstração e na API: quem entrou
// (created) e quem já estava (existing) com o card; quem falhou com o motivo.
const doEnvio = ({ created = [], existing = [], failed = [] }) => ({
  created: created.map(item => ({ id: item.lead_id, cardId: item.card_id })),
  existing: existing.map(item => ({ id: item.lead_id, cardId: item.card_id })),
  failed: failed.map(item => ({
    id: item.lead_id,
    motivo: item.reason_code,
    codigo: item.code || null,
  })),
});

// O Público guardado (#2695), igual na demonstração e na API: o id para abrir
// a Nova campanha com ele, quantas pessoas entraram e quem ficou de fora.
const doPublico = ({ audience = {}, left_out: fora = [] }) => ({
  publicoId: audience.id || null,
  nome: audience.name || '',
  n: audience.count || 0,
  fora: fora.map(item => ({ id: item.lead_id, motivo: item.reason_code })),
});

const comDias = search => ({
  ...buscaDoPayload(search),
  diasAtras: diasDesde(search.created_at),
});

const fonteDemo = ({ estado, carregarDemo, atraso, usuarioId }) => {
  const dados = () => carregarDemo();
  // Na demonstração, a busca sem "feitaPor" é de quem está vendo a tela: ela
  // ganha o id do usuário, e a tela usa a mesma regra da API (feitaPorId).
  const comDono = busca =>
    busca.feitaPor ? busca : { ...busca, feitaPorId: usuarioId };

  return {
    usaDemo: true,
    async porta() {
      const demo = await dados();
      const primeira = estado === 'porta-primeira';
      return {
        lugarSalvo: primeira ? null : demo.LUGAR_SALVO,
        ultimas: primeira ? [] : demo.BUSCAS.map(comDono),
        googlePronto: estado !== 'porta-sem-google',
        emTeste: estado === 'porta-teste',
        preenchido: demo.PORTA[estado] || demo.PORTA.porta,
        modelos: demo.PORTA[estado]?.modelos ? demo.MODELOS : [],
        limite: demo.LIMITE,
      };
    },
    async sugestoesDeLugar() {
      const demo = await dados();
      await esperar(atraso);
      if (estado === 'porta-lugar-nao-achado') return [];
      return estado === 'porta-uma-sugestao'
        ? demo.SUGESTAO_UNICA
        : demo.SUGESTOES;
    },
    async detalheDoLugar(sugestao) {
      return { ...sugestao, latitude: -22.9056, longitude: -47.0608 };
    },
    async criarBusca() {
      if (estado === 'porta-erro') throw new Error('demo');
      return { searchId: 'demo' };
    },
    async busca() {
      const demo = await dados();
      // Antes de mandar, a busca ainda não tem as 14 no funil.
      const busca = {
        ...demo.BUSCAS[0],
        noFunil: demo.NUMEROS.jaNoFunil,
        googleParou: false,
        // Busca por raio de 3 km: "Procurar mais longe" aparece.
        pedido: pedidoSalvoDe({
          query: demo.BUSCAS[0].oQue,
          location: demo.BUSCAS[0].lugar,
          radius: 3000,
          area_type: 'radius',
        }),
      };
      if (estado === 'confira-erro') {
        throw Object.assign(new Error('demo'), { busca });
      }
      if (['confira-vazia', 'leitura-vazia'].includes(estado)) {
        return { busca: { ...busca, achadas: 0 }, empresas: [] };
      }
      if (estado === 'confira-nome') {
        const empresas = demo.empresasMuitas();
        return { busca: { ...busca, achadas: empresas.length }, empresas };
      }
      if (estado === 'confira-google-parou') {
        const empresas = demo.empresasGoogleParou();
        return {
          busca: { ...busca, achadas: empresas.length, googleParou: true },
          empresas,
        };
      }
      return {
        busca,
        empresas:
          estado === 'chegando' ? demo.empresasChegando() : demo.empresas(),
        final: estado === 'chegando' ? demo.empresas() : null,
        tiradas: comTiradas(estado) ? demo.TIRADAS_NA_JORNADA : [],
      };
    },
    async buscas() {
      const demo = await dados();
      if (estado === 'buscas-erro') throw new Error('demo');
      const nada = { buscas: [], temMais: false };
      if (ESTADOS_SEM_BUSCAS.includes(estado)) return nada;
      // "buscas" é a de quem só vê as próprias; com "Ver buscas de todos"
      // (buscas-equipe, só Ver) vêm as da equipe.
      // Quem só vê não faz busca: só aparecem as de outras pessoas (rodada 3).
      const todas = demo.BUSCAS.map(comDono);
      const dele = busca => busca.feitaPorId === usuarioId;
      if (estado === 'buscas') return { ...nada, buscas: todas.filter(dele) };
      if (estado.startsWith('buscas-so-ver')) {
        return { ...nada, buscas: todas.filter(busca => !dele(busca)) };
      }
      return { ...nada, buscas: todas };
    },
    async repetirBusca() {
      await esperar(atraso);
      return { searchId: 'demo' };
    },
    async funis() {
      const demo = await dados();
      if (ESTADOS_COM_DOIS_FUNIS.includes(estado)) {
        return [...demo.FUNIS, demo.FUNIL_REVENDA];
      }
      return demo.FUNIS;
    },
    async pessoas() {
      return (await dados()).PESSOAS;
    },
    async mandarParaFunil({ ids, onProgresso = () => {} }) {
      const passos = Math.ceil(ids.length / CRM_BATCH_SIZE) + 2;
      await Array.from({ length: passos }).reduce(
        (anterior, _, indice) =>
          anterior.then(async () => {
            await esperar(atraso);
            onProgresso(
              Math.min(
                ids.length,
                Math.ceil((ids.length / passos) * (indice + 1))
              )
            );
          }),
        Promise.resolve()
      );
      const resposta =
        estado === 'folha-erro'
          ? { failed: ids.map(id => ({ lead_id: id, reason_code: 'demo' })) }
          : { created: ids.map(id => ({ lead_id: id, card_id: 9000 + id })) };
      return doEnvio(resposta);
    },
    async descartar() {
      await esperar(atraso);
    },
    async naoQuer() {
      await esperar(atraso);
    },
    // "Usar esta pessoa": a demonstração não grava. Cada empresa devolve um
    // dos três desfechos do servidor (RESULTADO_DA_DEMO), para dar para ver as
    // três frases.
    async usarPessoa({ empresa, nome }) {
      await esperar(atraso);
      const socio = empresa.socios.find(item => item.nome === nome);
      const resultado = RESULTADO_DA_DEMO[empresa.id] || 'updated';
      return {
        empresa: {
          ...empresa,
          dono: { estado: 'confirmado', nome, cargo: socio?.cargo || '' },
          socios: [
            ...empresa.socios.filter(item => item.nome !== nome),
            ...(empresa.dono.nome
              ? [{ nome: empresa.dono.nome, cargo: empresa.dono.cargo }]
              : []),
          ],
        },
        resultado,
        outra: resultado === 'shared_with_other_lead' ? 'Lima Contábil' : null,
      };
    },
    async procurarDono({ empresa }) {
      await esperar(atraso);
      return {
        ...empresa,
        dono: { estado: 'procurando', nome: '', cargo: '' },
      };
    },
    async apagarBusca() {
      await esperar(atraso);
    },
    async baixarBusca() {
      await esperar(atraso);
    },
    async guardarLista({ nome, ids }) {
      await esperar(atraso * 2);
      return doPublico({ audience: { name: nome, count: ids.length } });
    },
    async fila() {
      const demo = await dados();
      if (ESTADOS_SEM_FILA.includes(estado)) return { cartoes: [], fim: null };
      return { cartoes: demo.FILA, fim: demo.FIM_DO_DIA };
    },
    async configuracoes() {
      return { padrao: null };
    },
  };
};

const pipelineComEtapas = async (crm, pipeline) => {
  if (!pipeline.counts_as_sale) {
    return { id: pipeline.id, nome: pipeline.name, venda: false, etapas: [] };
  }
  const { data } = await crm.getStages(pipeline.id);
  return {
    id: pipeline.id,
    nome: pipeline.name,
    venda: true,
    etapas: (data.payload || []).map(etapa => ({
      id: etapa.id,
      nome: etapa.name,
    })),
  };
};

const fonteApi = ({ api, crm, usuarioId, usuarioNome }) => ({
  usaDemo: false,
  async porta() {
    const [{ data: ajustes }, { data: buscas }] = await Promise.all([
      api.getSettings(),
      api.getSearches({ page: 1 }),
    ]);
    const payload = buscas.payload || [];
    // O lugar salvo é o da última busca da própria pessoa; quem não fez
    // nenhuma ainda fica com o da última da equipe.
    const comLugar = payload.filter(search => search.location_place_id);
    const ultima =
      comLugar.find(search => search.user_id === usuarioId) || comLugar[0];
    return {
      lugarSalvo: ultima
        ? {
            rotulo: ultima.location_label || ultima.location,
            placeId: ultima.location_place_id,
            latitude: ultima.location_latitude,
            longitude: ultima.location_longitude,
          }
        : null,
      // A tela escolhe quais mostrar (as próprias ou as da equipe).
      ultimas: payload.map(comDias),
      googlePronto:
        ajustes.payload?.platform_google_places_configured !== false,
      emTeste: ajustes.payload?.mock_provider === true,
    };
  },
  async sugestoesDeLugar(texto) {
    const { data } = await api.getLocationSuggestions(texto);
    return (data.payload || []).map(sugestao => ({
      placeId: sugestao.place_id,
      rotulo: sugestao.label || sugestao.text,
    }));
  },
  async detalheDoLugar(sugestao) {
    const { data } = await api.getLocationDetails(sugestao.placeId);
    const lugar = data.payload || {};
    return {
      rotulo: lugar.label || sugestao.rotulo,
      placeId: lugar.place_id || sugestao.placeId,
      latitude: lugar.latitude,
      longitude: lugar.longitude,
    };
  },
  async criarBusca(pedido) {
    const { data } = await api.createSearch(montarPedido(pedido));
    return { searchId: data.payload?.search?.id };
  },
  async busca(id) {
    const { data } = await api.getSearch(id);
    const payload = data.payload || {};
    return {
      busca: buscaDoPayload(payload),
      empresas: (payload.leads || []).map(empresaDoLead),
      final: null,
      tiradas: [],
    };
  },
  async buscas(pagina = 1) {
    const { data } = await api.getSearches({ page: pagina });
    return {
      buscas: (data.payload || []).map(comDias),
      temMais: data.meta?.has_more === true,
    };
  },
  // A busca salva de novo, sem cache (fresh): "Buscar de novo" e "Procurar
  // mais longe" (o raio dobra, até o teto).
  async repetirBusca({ busca, maisLonge = false }) {
    const { data } = await api.createSearch(
      pedidoDeNovo(busca.pedido, { maisLonge })
    );
    return { searchId: data.payload?.search?.id };
  },
  async funis() {
    const { data } = await crm.getPipelines();
    return Promise.all(
      (data.payload || []).map(pipeline => pipelineComEtapas(crm, pipeline))
    );
  },
  // Com quem fica (#2694): "você" no topo e as pessoas da conta que enxergam o
  // funil (leads/crm_owners). Sem funil (ou sem poder trocar, quando a tela
  // não pede a lista), só "você".
  async pessoas({ funilId = null } = {}) {
    if (!funilId) return [{ id: 'voce', nome: usuarioNome || '', voce: true }];
    const { data } = await api.getCrmOwners(funilId);
    const lista = data.payload || [];
    const eu = lista.find(pessoa => pessoa.id === usuarioId);
    return [
      { id: 'voce', nome: eu?.name || usuarioNome || '', voce: true },
      ...lista
        .filter(pessoa => pessoa.id !== usuarioId)
        .map(pessoa => ({ id: pessoa.id, nome: pessoa.name })),
    ];
  },
  // donoId: com quem ficam os cards (#2694); sem ele, com quem manda.
  async mandarParaFunil({ ids, funilId, etapaId, donoId = null, onProgresso }) {
    const resumo = await sendInBatches(
      ids,
      lote =>
        api.createCrmCards({
          leadIds: lote,
          pipelineId: funilId,
          stageId: etapaId,
          ownerId: donoId,
        }),
      onProgresso
    );
    return doEnvio(resumo);
  },
  async descartar({ id, motivo }) {
    await api.discardLeads({ leadIds: [id], reason: motivo });
  },
  async naoQuer({ id }) {
    await api.refuseLeadConsent(id);
  },
  // Um dos outros sócios vira com quem falar (adopt_owner, #680). O servidor
  // devolve o lead e o que aconteceu com o contato (contact_outcome).
  async usarPessoa({ empresa, nome }) {
    const { data } = await api.adoptOwner(empresa.id, nome);
    return {
      empresa: empresaDoLead(data.payload),
      resultado: data.contact_outcome,
      outra: data.shared_lead_name || null,
    };
  },
  // "Buscar de novo" do dono não achado: a pesquisa de empresa e decisor de
  // novo (force), em fila; o lead volta com a pesquisa andando.
  async procurarDono({ empresa }) {
    const { data } = await api.researchLead(empresa.id, { force: true });
    return empresaDoLead(data.payload?.lead);
  },
  async apagarBusca(id) {
    await api.deleteSearch(id);
  },
  async baixarBusca(id) {
    const { data } = await api.exportSearch(id, { format: 'xlsx' });
    salvarArquivo(data, `prospeccao-${id}.xlsx`);
  },
  // "Guardar para mandar mensagem" (#2695): as empresas viram um Público de
  // Campanhas. Na recusa, o erro leva o código do servidor e quem ficou de fora.
  async guardarLista({ nome, ids }) {
    try {
      const { data } = await api.createAudience({ leadIds: ids, name: nome });
      return doPublico(data.payload || {});
    } catch (erro) {
      const recusa = erro?.response?.data || {};
      throw Object.assign(new Error('publico'), {
        codigo: recusa.code || null,
        fora: doPublico({ left_out: recusa.left_out || [] }).fora,
      });
    }
  },
  // A fila "Para chamar" pede leads#index com view=queue (v4, fase 5).
  async fila() {
    return { cartoes: [], fim: null };
  },
  async configuracoes() {
    const { data } = await api.getSettings();
    const ajustes = data.payload || {};
    return {
      podeFunil: ajustes.can_send_to_crm === true,
      padrao: ajustes.default_crm_pipeline_id
        ? {
            funilId: ajustes.default_crm_pipeline_id,
            etapaId: ajustes.default_crm_stage_id,
          }
        : null,
    };
  },
});

export const criarFonte = ({
  demo = null,
  carregarDemo = CARREGAR_DEMO,
  api = AutonomiaProspectingAPI,
  crm = CrmKanbanAPI,
  atraso = 400,
  usuarioId = null,
  usuarioNome = '',
} = {}) =>
  demo && carregarDemo
    ? fonteDemo({ estado: demo, carregarDemo, atraso, usuarioId })
    : fonteApi({ api, crm, usuarioId, usuarioNome });
