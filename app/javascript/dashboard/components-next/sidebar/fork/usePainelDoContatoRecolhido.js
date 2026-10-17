import { computed, watch } from 'vue';

// Painel do contato recolhido ao entrar numa conversa (#1781), inclusive no carregamento. A pessoa pode abrir;
// ao trocar de conversa, ou sair e voltar, recolhe de novo. Montado pelo menu novo, então só vale com a flag.
export function usePainelDoContatoRecolhido({
  route,
  uiSettings,
  updateUISettings,
}) {
  const conversaAberta = computed(() => {
    if (route.params?.conversation_id) return route.params.conversation_id;
    return route.name === 'inbox_view_conversation' ? route.params?.id : null;
  });

  watch(
    conversaAberta,
    conversa => {
      if (!conversa || !uiSettings.value?.is_contact_sidebar_open) return;
      updateUISettings({ is_contact_sidebar_open: false });
    },
    { immediate: true }
  );
}
