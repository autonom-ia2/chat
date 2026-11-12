import CrmKanbanAPI from 'dashboard/api/crmKanban';

// #2414 F6.3/F6.5 e #2710 — de onde as telas de automação no CRM tiram os dados.
// Protótipo: a fonte falsa devolve dados fictícios e realistas no mesmo formato
// que a API vai devolver; as telas não sabem de onde vem. Trocar pela API é
// trocar este arquivo (as funções e o formato ficam):
// - automacoesDoCard(card)   → [{ id, nome, estado: 'espera'|'resposta'|'agora', ate? }]
// - pararNoCard(card, item)  → true
// - automacoesDaEtapa(id)    → [{ id, origem: 'etapa'|'motor', nome, quando: 'entra'|'sai', faz, ligada, rota? }]
//   (as regras antigas da etapa e as automações novas com gatilho nesta etapa, numa lista só)
// - reuniaoDoCard(card)      → { inicio, nome } | null (só no card ganho)
// - atividadesDoCard(card)   → linhas extras da linha do tempo, no formato de Crm::Activity
// - jaCliente(card)          → { comprouEm, contatoId } | null (o card aberto de quem já comprou)
// - cardGanho(jaCliente)     → id do card ganho | null
// `?demo=vazio` deixa tudo vazio, para ver os estados vazios.

// Datas fixas: os prints saem iguais em qualquer dia. Sem "Z": hora local.
export const DATAS_DO_ENSAIO = {
  esperaAte: '2026-11-15T12:00:00',
  ligarEm: '2026-11-13T09:00:00',
  comprouEm: '2026-11-03T15:30:00',
  reuniao: '2026-11-15T10:00:00',
  marcouEm: '2026-11-12T09:14:00',
};

export const EVENTO_REUNIAO_PELO_EMAIL = 'booking_client_booked_from_email';

const D = 'AUTOMACAO_NO_CRM.DEMO';

const primeiroNome = (nome, t) =>
  String(nome || '')
    .trim()
    .split(' ')[0] || t(`${D}.CLIENTE`);

const ehGanho = card => card?.status === 'won';

export const criarFonteFalsa = ({ t, vazio = false }) => {
  const automacoesDoCard = async card => {
    if (vazio || !card?.id) return [];
    return [
      {
        id: 'motor-41',
        nome: t(`${D}.LEMBRETE_PROPOSTA`),
        estado: 'espera',
        ate: DATAS_DO_ENSAIO.esperaAte,
      },
      {
        id: 'motor-42',
        nome: t(`${D}.CLIENTE_SUMIU`),
        estado: 'resposta',
      },
      {
        id: 'etapa-11',
        nome: t(`${D}.LIGAR_NO_DIA_SEGUINTE`),
        estado: 'espera',
        ate: DATAS_DO_ENSAIO.ligarEm,
      },
    ];
  };

  const automacoesDaEtapa = async etapaId => {
    if (vazio || !etapaId) return [];
    // Amanhã: a nova abre no editor (automacoes_livre_editar); no ensaio, na lista.
    const rota = { name: 'automacoes_lista' };
    return [
      {
        id: 'etapa-11',
        origem: 'etapa',
        nome: t(`${D}.LIGAR_NO_DIA_SEGUINTE`),
        quando: 'entra',
        faz: t(`${D}.FAZ_TAREFA`),
        ligada: true,
      },
      {
        id: 'motor-41',
        origem: 'motor',
        nome: t(`${D}.LEMBRETE_PROPOSTA`),
        quando: 'entra',
        faz: t(`${D}.FAZ_LEMBRETE`),
        ligada: true,
        rota,
      },
      {
        id: 'motor-42',
        origem: 'motor',
        nome: t(`${D}.CLIENTE_SUMIU`),
        quando: 'sai',
        faz: t(`${D}.FAZ_AVISO`),
        ligada: false,
        rota,
      },
    ];
  };

  const reuniaoDoCard = async card => {
    if (vazio || !ehGanho(card)) return null;
    return {
      inicio: DATAS_DO_ENSAIO.reuniao,
      nome: primeiroNome(card.contact?.name, t),
    };
  };

  const atividadesDoCard = card => {
    if (vazio || !ehGanho(card)) return [];
    return [
      {
        id: 'ensaio-2710',
        event_type: EVENTO_REUNIAO_PELO_EMAIL,
        actor_type: 'contact',
        created_at: DATAS_DO_ENSAIO.marcouEm,
        payload: { by: 'client', starts_at: DATAS_DO_ENSAIO.reuniao },
        labels: { contact_name: primeiroNome(card.contact?.name, t) },
      },
    ];
  };

  const jaCliente = card => {
    const contato = card?.contact;
    if (vazio || card?.status !== 'open' || !contato?.id) return null;
    if (contato.contact_type !== 'customer') return null;
    return { comprouEm: DATAS_DO_ENSAIO.comprouEm, contatoId: contato.id };
  };

  // O selo procura o card ganho na API de hoje (perfil do contato), que já
  // respeita quem pode ver cada card.
  const cardGanho = async cliente => {
    if (!cliente?.contatoId) return null;
    const { data } = await CrmKanbanAPI.getContactOpportunities(
      String(cliente.contatoId),
      { result: 'won' }
    );
    return data?.payload?.[0]?.id || null;
  };

  return {
    automacoesDoCard,
    pararNoCard: async () => true,
    automacoesDaEtapa,
    reuniaoDoCard,
    atividadesDoCard,
    jaCliente,
    cardGanho,
  };
};

// A linha do tempo chega da mais nova para a mais velha; as linhas extras
// entram no lugar delas pela data.
export const juntarAtividades = (doCard, extras) =>
  extras.length
    ? [...doCard, ...extras].sort(
        (a, b) => new Date(b.created_at) - new Date(a.created_at)
      )
    : doCard;
