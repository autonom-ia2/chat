// #2898 — o aviso "N seguros entraram em renovação hoje" do sino. Ao clicar,
// marca o aviso como lido e abre a aba Seguros no grupo "Em renovação". Fica
// aqui, e não na lista de avisos do Chatwoot (inbox/InboxList.vue), que só
// chama: `true` quando o aviso era da carteira e já foi aberto; `false` para
// todo outro aviso, que segue o caminho de sempre.
export const AVISO_DA_RENOVACAO = 'carteira_renovacao';

export const abrirAvisoDaCarteira = async (aviso, { store, router, meta }) => {
  if (aviso.notificationType !== AVISO_DA_RENOVACAO) return false;

  const { id, primaryActorId, primaryActorType } = aviso;
  try {
    await store.dispatch('notifications/read', {
      id,
      primaryActorId,
      primaryActorType,
      unreadCount: meta.value.unreadCount,
    });
    store.dispatch('notifications/unReadCount');
  } catch {
    // a tela abre mesmo assim; marcar como lido fica para a próxima
  }
  router.push({
    name: 'relationships_home',
    query: { aba: 'seguros', grupo: 'em_renovacao' },
  });
  return true;
};
