import { priorityValue } from '../../utils/prospectingPriority';
import { chanceDe } from './acharChance';

// #2692 — a empresa como a tela nova mostra, venha da API (lead de hoje,
// LeadPayload) ou da demonstração (que já nasce neste formato). A tela não lê o
// lead cru: o adaptador traduz aqui, num lugar só.

const DONO_ACHADO = { confirmed: 'confirmado', possible: 'possivel' };
const SITUACAO_ATIVA = 'ATIVA';

const estadoDoDono = research => {
  if (!research) return 'desligada';
  if (research.decision?.name) {
    return DONO_ACHADO[research.decision_status] || 'possivel';
  }
  if (research.completed_at) return 'nenhum';
  if (research.requested_at) return 'procurando';
  return 'desligada';
};

const estadoDoWhatsapp = status => {
  if (status === 'verified') return 'tem';
  if (!status || status === 'pending') return 'conferindo';
  return 'sem';
};

const situacaoDe = research => research?.company?.registration_status || null;

// Quem fica de fora já vem com o motivo: no funil, não quer receber, tirada em
// outra busca ou fechada no cadastro do governo.
const motivoDeFora = lead => {
  if (lead.crm_presence) {
    return {
      motivo: 'no_funil',
      funil: lead.crm_presence.pipeline_name || null,
    };
  }
  if (lead.consent_refused_at) return { motivo: 'nao_quer' };
  if (lead.status === 'discarded') return { motivo: 'tirou' };
  const situacao = situacaoDe(lead.research);
  if (situacao && situacao.toUpperCase() !== SITUACAO_ATIVA) {
    return { motivo: 'fechou' };
  }
  return null;
};

export const empresaDoLead = lead => {
  const decisao = lead.research?.decision;
  return {
    id: lead.id,
    nome: lead.name,
    categoria: lead.category || '',
    bairro: lead.neighborhood || lead.city || '',
    endereco: lead.address || '',
    latitude: lead.latitude ?? null,
    longitude: lead.longitude ?? null,
    prioridade: priorityValue(lead),
    chance: chanceDe(priorityValue(lead)),
    porque: lead.human_insight || '',
    dono: {
      estado: estadoDoDono(lead.research),
      nome: decisao?.name || '',
      cargo: decisao?.role || '',
    },
    socios: (lead.research?.owners || []).map(socio => ({
      nome: socio.name || socio.nome || '',
      cargo: socio.role || socio.qualification || '',
    })),
    whatsapp: estadoDoWhatsapp(lead.whatsapp_verification_status),
    whatsappUrl: lead.whatsapp_url || null,
    telefone: lead.phone || '',
    site: lead.website || '',
    email: lead.enriched_email || '',
    nota: lead.rating ?? null,
    avaliacoes: lead.reviews_count ?? 0,
    cnpj: lead.enriched_cnpj || lead.research?.company?.cnpj || '',
    situacao: situacaoDe(lead.research),
    noFunil: lead.crm_presence
      ? {
          funil: lead.crm_presence.pipeline_name,
          etapa: lead.crm_presence.stage_name,
          pessoa: lead.crm_presence.owner_name,
          funilId: lead.crm_presence.pipeline_id,
          cardId: lead.crm_presence.card_id,
        }
      : null,
    fora: motivoDeFora(lead),
    temContato: Boolean(lead.phone || lead.enriched_email),
  };
};

export const buscaDoPayload = search => ({
  id: search.id,
  oQue: search.query || '',
  lugar: search.location_label || search.location || '',
  achadas: search.results_count ?? 0,
  noFunil: search.crm_count ?? 0,
  criadaEm: search.created_at || null,
  feitaPor: search.user_name || search.created_by_name || '',
  googleParou: Boolean(search.summary?.partial_results),
});
