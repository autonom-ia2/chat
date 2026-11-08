// #2101 — o aviso quando criar o lembrete falha. Card arquivado tem motivo
// próprio, que o servidor já manda no idioma da pessoa; o resto fica com o
// aviso genérico (o texto cru do servidor não vai para a tela).
export const avisoAoSalvar = (erro, t) => {
  const resposta = erro?.response?.data;
  if (resposta?.code === 'card_archived' && resposta.message)
    return resposta.message;
  return t('CRM_KANBAN.ALERTS.FOLLOW_UP_SAVE_ERROR');
};
