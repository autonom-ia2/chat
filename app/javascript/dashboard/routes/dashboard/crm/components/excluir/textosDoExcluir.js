import { cardStatusLabel, countsAsSale } from '../../helpers/cardOutcome';

// Frases das janelas de excluir de vez (#2096). Funções puras, com `t` e o formato de quem chama, para o card, os
// vários cards, o funil e o contato dizerem a mesma coisa do mesmo jeito.

// Venda que conta nos Números: card ganho (ou arquivado depois de ganho, Parte A) num funil de venda.
export const ehVenda = card =>
  countsAsSale(card?.pipeline) &&
  (card?.status === 'won' || card?.desfecho === 'won');

// Soma por moeda: "R$ 3.000" ou "R$ 3.000 + US$ 200". Nunca converte uma moeda na outra.
export const somaDasVendas = (formato, cards) => {
  const porMoeda = cards.reduce((soma, card) => {
    const moeda = card.currency || 'BRL';
    return {
      ...soma,
      [moeda]: (soma[moeda] || 0) + Number(card.value_cents || 0),
    };
  }, {});
  return Object.entries(porMoeda)
    .map(([moeda, centavos]) => formato.dinheiro(centavos, moeda))
    .join(' + ');
};

const PROVEDORES_QUE_AVISAM = ['google', 'microsoft'];

// A reunião futura é cancelada antes de apagar (decisão 10). Google e Microsoft avisam o cliente; marcada pelo
// WhatsApp ou só aqui, ela sai do sistema e o cliente não recebe aviso. `reunioes`: [{ quando, provider? }];
// sem `provider` (a consulta do card não diz), a frase cobre os dois casos.
export const avisoDeReunioes = (t, reunioes) => {
  if (!reunioes?.length) return '';
  const total = reunioes.length;
  const quais =
    total === 1
      ? t('CRM_EXCLUIR.REUNIAO.UMA', { quando: reunioes[0].quando })
      : t('CRM_EXCLUIR.REUNIAO.VARIAS', { count: total }, total);
  const cancela = t('CRM_EXCLUIR.REUNIAO.CANCELA', { count: total }, total);
  const provedores = reunioes.map(reuniao => reuniao.provider);
  let cliente = t('CRM_EXCLUIR.REUNIAO.CLIENTE_DEPENDE');
  if (provedores.every(Boolean)) {
    const avisam = provedores.some(p => PROVEDORES_QUE_AVISAM.includes(p));
    const naoAvisam = provedores.some(p => !PROVEDORES_QUE_AVISAM.includes(p));
    if (avisam && !naoAvisam)
      cliente = t('CRM_EXCLUIR.REUNIAO.CLIENTE_AVISADO');
    if (naoAvisam && !avisam)
      cliente = t('CRM_EXCLUIR.REUNIAO.CLIENTE_SEM_AVISO');
  }
  return [quais, cancela, cliente].join(' ');
};

// Uma linha da lista de cards do contato: "Vendas · Proposta (funil arquivado)", o valor e a situação. O card arquivado
// diz também como estava antes de arquivar ("Arquivado · Ganho"), o desfecho guardado da Parte A (#2094).
const situacaoDoCard = (t, card) => {
  if (card.status === 'open') return '';
  if (card.status !== 'archived')
    return cardStatusLabel(t, card.status, card.pipeline);
  const arquivado = cardStatusLabel(t, 'archived', card.pipeline);
  if (!card.desfecho || card.desfecho === 'open') return arquivado;
  return t('CRM_EXCLUIR.CONTATO.ARQUIVADO_COM', {
    arquivado,
    desfecho: cardStatusLabel(t, card.desfecho, card.pipeline),
  });
};

export const linhaDoCardDoContato = (t, formato, card) => {
  const arquivado = card.pipeline?.status === 'archived';
  const onde = [card.pipeline?.name, card.stage_name]
    .filter(Boolean)
    .join(' · ');
  return {
    onde: arquivado ? t('CRM_EXCLUIR.CONTATO.FUNIL_ARQUIVADO', { onde }) : onde,
    valor:
      countsAsSale(card.pipeline) && Number(card.value_cents)
        ? formato.dinheiro(card.value_cents, card.currency)
        : '',
    situacao: situacaoDoCard(t, card),
  };
};

// Os códigos que o servidor manda ao recusar (Api::V1::Accounts::Crm::*::PermanentDeletionsController). Código que
// não está aqui vira a frase geral, com o código, para ninguém ficar sem motivo.
const MOTIVOS = {
  'crm.permanent_delete.admin_only': 'SO_ADMIN',
  'crm.permanent_delete.not_archived': 'NAO_ARQUIVADO',
  'crm.permanent_delete.confirmation_mismatch': 'CONFIRMACAO',
  'crm.permanent_delete.meeting_cancel_failed': 'REUNIAO',
  'crm.permanent_delete.contact_online': 'CONTATO_ONLINE',
  'crm.permanent_delete.cards_changed': 'MUDOU',
  'crm.permanent_delete.already_deleted': 'JA_EXCLUIDO',
  'crm.permanent_delete.target_unavailable': 'DESTINO',
  'crm.permanent_delete.invalid_target_stage': 'DESTINO',
  'crm.permanent_delete.too_many_cards': 'MUITOS',
  'crm.permanent_delete.contact_cards_choice_required': 'ESCOLHA',
};

const motivoDoCodigo = (t, error) => {
  const codigo = error.response.data?.error;
  const chave = MOTIVOS[codigo];
  if (chave) return t(`CRM_EXCLUIR.ERROS.${chave}`);
  return t('CRM_EXCLUIR.ERROS.RECUSOU', {
    codigo: codigo || error.response.status,
  });
};

// A reunião que o calendário já tinha cancelado antes da recusa fica cancelada (o cliente já foi avisado): a frase diz.
export const motivoDoExcluir = (t, error) => {
  if (!error?.response) return t('CRM_EXCLUIR.ERROS.SEM_CONEXAO');
  const motivo = motivoDoCodigo(t, error);
  const canceladas = (error.response.data?.canceled_meeting_ids || []).length;
  if (!canceladas) return motivo;
  return `${motivo} ${t('CRM_EXCLUIR.ERROS.JA_CANCELADAS', { count: canceladas }, canceladas)}`;
};

// A palavra digitada confere? EXCLUIR aceita minúsculas (quem digita "excluir" quis dizer isso); o nome do funil
// tem de ser igual, só sem espaço sobrando nas pontas, como o servidor confere.
export const confere = (
  digitado,
  palavra,
  { ignorarMaiusculas = false } = {}
) => {
  const limpo = String(digitado || '').trim();
  const alvo = String(palavra || '').trim();
  if (!alvo) return false;
  return ignorarMaiusculas
    ? limpo.toUpperCase() === alvo.toUpperCase()
    : limpo === alvo;
};

export const PALAVRA_DE_CONFIRMAR = 'EXCLUIR';
