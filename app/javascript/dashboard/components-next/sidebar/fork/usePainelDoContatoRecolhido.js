import { computed, ref, watch } from 'vue';

// Painel do contato recolhido ao entrar numa conversa (#1781), inclusive no carregamento. A pessoa pode abrir;
// ao trocar de conversa, ou sair e voltar, recolhe de novo. Filtro ou âncora na mesma conversa não fecham.
// Montado pelo menu novo, então só vale com a flag.
export function usePainelDoContatoRecolhido({
  route,
  uiSettings,
  updateUISettings,
  // Preferências da pessoa já chegaram do servidor: antes disso, não dá para saber se o painel está aberto.
  carregado = ref(true),
}) {
  const conversaAberta = computed(() => {
    if (route.params?.conversation_id) return route.params.conversation_id;
    return route.name === 'inbox_view_conversation' ? route.params?.id : null;
  });

  // Uma vez por entrada na conversa: depois disso, abrir é escolha da pessoa.
  let recolhidoPara = null;
  watch(
    [conversaAberta, carregado],
    ([conversa, pronto]) => {
      if (!conversa) {
        recolhidoPara = null;
        return;
      }
      if (!pronto || recolhidoPara === conversa) return;
      recolhidoPara = conversa;
      if (uiSettings.value?.is_contact_sidebar_open) {
        updateUISettings({ is_contact_sidebar_open: false });
      }
    },
    { immediate: true }
  );
}
