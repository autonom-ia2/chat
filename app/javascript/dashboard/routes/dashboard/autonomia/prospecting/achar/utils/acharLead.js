import { priorityValue } from '../../utils/prospectingPriority';
import { chanceDe } from './acharChance';
import { pedidoSalvoDe } from './acharPedido';

// "Não serve": a empresa que alguém tirou (descarte do lead, LeadDiscard). O
// descarte vale para o lead inteiro, sem busca nem data: a tela não diz quando
// nem onde foi tirada. Conta em "você tirou", não em "ficam de fora".
export const MOTIVO_NAO_SERVE = 'nao_serve';

// #2692 — a empresa como a tela nova mostra, venha da API (lead de hoje,
// LeadPayload) ou da demonstração (que já nasce neste formato). A tela não lê o
// lead cru: o adaptador traduz aqui, num lugar só.

const DONO_ACHADO = { confirmed: 'confirmado', possible: 'possivel' };
const SITUACAO_ATIVA = 'ATIVA';
// Estados da pesquisa de empresa e decisor (Research::States): pedida e ainda
// sem desfecho é "procurando"; nunca pedida é "desligada".
const PESQUISA_ANDANDO = ['queued', 'researching', 'waiting_capacity'];
const PESQUISA_NAO_FEITA = [undefined, null, '', 'not_researched'];

// O dono que a tela mostra. Com a pesquisa feita, vale só o decisor dela
// (Research::Payload). Sem pesquisa nenhuma, o nome que a IA achou no
// enriquecimento (lead.decision_name) aparece como "Pode ser o dono".
const donoDe = lead => {
  const research = lead.research || {};
  const decisao = research.decision;
  if (decisao?.name) {
    return {
      estado: DONO_ACHADO[research.decision_status] || 'possivel',
      nome: decisao.name,
      cargo: decisao.role || '',
    };
  }
  if (PESQUISA_ANDANDO.includes(research.company_status)) {
    return { estado: 'procurando', nome: '', cargo: '' };
  }
  if (PESQUISA_NAO_FEITA.includes(research.company_status)) {
    return lead.decision_name
      ? {
          estado: 'possivel',
          nome: lead.decision_name,
          cargo: lead.decision_role || '',
        }
      : { estado: 'desligada', nome: '', cargo: '' };
  }
  return { estado: 'nenhum', nome: '', cargo: '' };
};

// Nome comparado como o servidor compara (Normalization.squish): aparado e com
// os espaços colapsados. Sem expressão regular.
const nomeLimpo = nome =>
  String(nome || '')
    .split(' ')
    .filter(Boolean)
    .join(' ');

// Os outros sócios que a pesquisa achou, sem quem já é o dono atual. O nome
// vai como veio: é ele que o servidor confere em adopt_owner.
const sociosDe = (lead, dono) =>
  (lead.research?.owners || [])
    .map(socio => ({
      nome: socio.name || '',
      cargo: socio.qualification || socio.role || '',
    }))
    .filter(
      socio =>
        socio.nome &&
        nomeLimpo(socio.nome).toLowerCase() !==
          nomeLimpo(dono.nome).toLowerCase()
    );

// verified: tem; queued (na fila da verificação): conferindo; o resto
// (not_whatsapp, failed ou sem verificação) não tem WhatsApp confirmado.
const estadoDoWhatsapp = status => {
  if (status === 'verified') return 'tem';
  if (status === 'queued' || status === 'pending') return 'conferindo';
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
  if (lead.status === 'discarded') {
    return { motivo: MOTIVO_NAO_SERVE, razao: lead.discard_reason || '' };
  }
  const situacao = situacaoDe(lead.research);
  if (situacao && situacao.toUpperCase() !== SITUACAO_ATIVA) {
    return { motivo: 'fechou' };
  }
  return null;
};

export const empresaDoLead = lead => {
  const dono = donoDe(lead);
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
    dono,
    socios: sociosDe(lead, dono),
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

// O cartão da fila "Para chamar" (#2697): a empresa de sempre e quem fez a
// busca de onde ela veio ("Achada por", found_by_name do servidor).
export const cartaoDaFila = lead => ({
  ...empresaDoLead(lead),
  achadoPor: lead.found_by_name || '',
});

export const buscaDoPayload = search => ({
  id: search.id,
  oQue: search.query || '',
  lugar: search.location_label || search.location || '',
  achadas: search.results_count ?? 0,
  noFunil: search.crm_count ?? 0,
  criadaEm: search.created_at || null,
  // Quem fez a busca (search_payload, #2693).
  feitaPor: search.user_name || '',
  feitaPorId: search.user_id ?? null,
  googleParou: Boolean(search.summary?.partial_results),
  // Para refazer a busca ("Buscar de novo", "Procurar mais longe").
  pedido: pedidoSalvoDe(search),
});
