import { reportarSemDados } from 'dashboard/helper/sentryPrivacy';

// #2898 — o aviso "N seguros entraram em renovação hoje" do sino. Ao clicar,
// marca o aviso como lido e abre a aba Seguros no grupo "Em renovação". Fica
// aqui, e não na lista de avisos do Chatwoot (inbox/InboxList.vue), que só
// chama, e só quando o aviso é deste tipo: os outros avisos nem passam por
// aqui.
export const AVISO_DA_RENOVACAO = 'carteira_renovacao';

export const abrirAvisoDaCarteira = async (aviso, { store, router, meta }) => {
  const { id, primaryActorId, primaryActorType } = aviso;
  try {
    await store.dispatch('notifications/read', {
      id,
      primaryActorId,
      primaryActorType,
      unreadCount: meta.value.unreadCount,
    });
    store.dispatch('notifications/unReadCount');
  } catch (erro) {
    // a tela abre mesmo assim; marcar como lido fica para a próxima. O erro
    // vai para o rastreador sem dado de ninguém, para não sumir calado.
    reportarSemDados(erro, { tela: 'carteira_aviso_da_renovacao' });
  }
  router.push({
    name: 'relationships_home',
    query: { aba: 'seguros', grupo: 'em_renovacao' },
  });
};
