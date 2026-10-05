import { ref, readonly } from 'vue';
import { useUISettings } from 'dashboard/composables/useUISettings';

// #977 — o canal para outra tela (a Central de Ajuda) mandar uma pergunta pronta
// ao painel do Guia. Uma só para o painel inteiro: quem pede e quem envia são
// componentes diferentes. O texto fica na memória, nunca no endereço — senão
// recarregar a página ou copiar o link mandaria a pergunta de novo.
const pendente = ref('');

export function useGuiaPedido() {
  const { updateUISettings } = useUISettings();

  // Abre o painel, como o "Perguntar ao Guia" da Central sempre fez. Com texto,
  // o painel o envia assim que abrir (com outra pergunta em curso, avisa e
  // descarta, como o campo de digitar); vazio, só abre.
  const pedirAoGuia = texto => {
    const pergunta = (texto || '').trim();
    if (pergunta) pendente.value = pergunta;
    updateUISettings({
      is_autonomia_guide_panel_open: true,
      is_autonomia_copilot_panel_open: false,
      is_contact_sidebar_open: false,
    });
  };

  return { pedirAoGuia };
}

// Para o painel: lê o pedido e o gasta, para ele sair uma vez só.
export function usePedidoPendente() {
  const consumir = () => {
    const texto = pendente.value;
    pendente.value = '';
    return texto;
  };

  return { pedido: readonly(pendente), consumir };
}
