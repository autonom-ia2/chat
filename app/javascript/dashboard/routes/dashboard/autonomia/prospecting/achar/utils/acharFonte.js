import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { sendInBatches, CRM_BATCH_SIZE } from '../../utils/crmSend';
import { buscaDoPayload, empresaDoLead } from './acharLead';

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

export const demoPedido = (
  query = {},
  permitida = Boolean(import.meta.env.DEV)
) => {
  const valor = query?.demo;
  return permitida && typeof valor === 'string' && valor ? valor : null;
};

const esperar = ms =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });

const UM_DIA = 24 * 60 * 60 * 1000;
const diasDesde = data =>
  data ? Math.max(0, Math.floor((Date.now() - new Date(data)) / UM_DIA)) : 0;

const KM = 1000;
// "Quais empresas?" vira os filtros que o motor já entende (advancedLeadFilters).
const FILTROS_DE = {
  todas: {},
  conhecidas: { rating_min: '4', reviews_min: '20' },
  telefone: { has_phone: 'yes' },
  abertas: { open_now: 'yes' },
};

export const montarPedido = ({ oQue, lugar, como }) => {
  const centro =
    lugar.latitude && lugar.longitude
      ? { lat: Number(lugar.latitude), lng: Number(lugar.longitude) }
      : null;
  const raio = como.km * KM;
  return {
    query: oQue.trim(),
    requested_limit: como.n,
    location: lugar.rotulo,
    radius: raio,
    area_type: 'radius',
    area_config: {
      center: centro,
      label: lugar.rotulo,
      place_id: lugar.placeId,
      radius: raio,
    },
    metadata: {
      location_place_id: lugar.placeId,
      location_latitude: lugar.latitude,
      location_longitude: lugar.longitude,
      location_label: lugar.rotulo,
      filters: { auto_expand_radius: true },
      // A tela nova ordena sempre pelo modo geral (decisão do Rodrigo, 07/11).
      score_mode: 'general',
      advanced_filters: FILTROS_DE[como.quais] || {},
    },
  };
};

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

const fonteDemo = ({ estado, carregarDemo, atraso }) => {
  const dados = () => carregarDemo();

  return {
    usaDemo: true,
    async porta() {
      const demo = await dados();
      const primeira = estado === 'porta-primeira';
      return {
        lugarSalvo: primeira ? null : demo.LUGAR_SALVO,
        ultimas: primeira ? [] : demo.BUSCAS,
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
      if (ESTADOS_SEM_BUSCAS.includes(estado)) return [];
      // "buscas" é a de quem só vê as próprias; com "Ver buscas de todos"
      // (buscas-equipe, só Ver) vêm as da equipe.
      // Quem só vê não faz busca: só aparecem as de outras pessoas (rodada 3).
      if (estado === 'buscas') return demo.BUSCAS.filter(b => !b.feitaPor);
      if (estado.startsWith('buscas-so-ver')) {
        return demo.BUSCAS.filter(busca => busca.feitaPor);
      }
      return demo.BUSCAS;
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
      if (estado === 'folha-erro') {
        return { created: [], existing: [], failed: ids };
      }
      return { created: ids, existing: [], failed: [] };
    },
    async descartar() {
      await esperar(atraso);
    },
    async naoQuer() {
      await esperar(atraso);
    },
    async guardarLista({ nome, ids }) {
      await esperar(atraso * 2);
      return { nome, n: ids.length };
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

const fonteApi = ({ api, crm }) => ({
  usaDemo: false,
  async porta() {
    const [{ data: ajustes }, { data: buscas }] = await Promise.all([
      api.getSettings(),
      api.getSearches({ page: 1 }),
    ]);
    const lista = (buscas.payload || []).map(search => ({
      ...buscaDoPayload(search),
      diasAtras: diasDesde(search.created_at),
    }));
    const ultima = (buscas.payload || []).find(
      search => search.location_place_id
    );
    return {
      lugarSalvo: ultima
        ? {
            rotulo: ultima.location_label || ultima.location,
            placeId: ultima.location_place_id,
            latitude: ultima.location_latitude,
            longitude: ultima.location_longitude,
          }
        : null,
      ultimas: lista.slice(0, 3),
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
  async buscas() {
    const { data } = await api.getSearches({ page: 1 });
    return (data.payload || []).map(search => ({
      ...buscaDoPayload(search),
      diasAtras: diasDesde(search.created_at),
    }));
  },
  async funis() {
    const { data } = await crm.getPipelines();
    return Promise.all(
      (data.payload || []).map(pipeline => pipelineComEtapas(crm, pipeline))
    );
  },
  // Fase 1 (só front): o card fica com quem manda; a lista de pessoas entra com
  // o backend do dono escolhido na hora (v4, PR 2a).
  async pessoas() {
    return [{ id: 'voce', nome: 'Você', voce: true }];
  },
  async mandarParaFunil({ ids, funilId, etapaId, onProgresso }) {
    const resumo = await sendInBatches(
      ids,
      lote =>
        api.createCrmCards({
          leadIds: lote,
          pipelineId: funilId,
          stageId: etapaId,
        }),
      onProgresso
    );
    return {
      created: resumo.created.map(item => item.lead_id ?? item),
      existing: resumo.existing.map(item => item.lead_id ?? item),
      failed: resumo.failed.map(item => item.lead_id ?? item),
    };
  },
  async descartar({ id, motivo }) {
    await api.discardLeads({ leadIds: [id], reason: motivo });
  },
  async naoQuer({ id }) {
    await api.refuseLeadConsent(id);
  },
  // O Público a partir de empresas é backend novo (v4, fase 3). Até lá o cartão
  // "Guardar para mandar mensagem" não aparece fora da demonstração.
  async guardarLista() {
    throw new Error('publico_de_empresas_indisponivel');
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
} = {}) =>
  demo && carregarDemo
    ? fonteDemo({ estado: demo, carregarDemo, atraso })
    : fonteApi({ api, crm });
