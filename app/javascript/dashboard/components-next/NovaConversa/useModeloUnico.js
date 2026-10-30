import { watch } from 'vue';
import { TIPOS } from './novaConversa';

// "Começar pronto": quando só dá para enviar mensagem pronta e há uma só aprovada, ela
// já vem marcada. Olha a quantidade, e não a lista, para não marcar de novo depois de a
// pessoa clicar em "Alterar". Usado pela gaveta (NovaConversaMensagem) e pela conversa
// vazia da busca (#2211).
export function useModeloUnico({ modelos, tipo, modelo }) {
  watch(
    () => modelos.value.length,
    quantas => {
      if (tipo.value !== TIPOS.WHATSAPP_PRONTA || quantas !== 1) return;
      if (!modelo.value) [modelo.value] = modelos.value;
    },
    { immediate: true }
  );
}
