// #3165 — a conversa lida ao lado, no card do CRM. Busca a conversa e as últimas
// mensagens pela mesma API do painel, sem tocar na conversa aberta do painel; as
// antigas chegam de 20 em 20 ao rolar. Só lê: nada aqui marca como lida.
import { computed, ref, toValue, watch } from 'vue';
import ConversationAPI from 'dashboard/api/inbox/conversation';
import MessageApi from 'dashboard/api/inbox/message';

const PAGINA = 20;

const emOrdem = mensagens =>
  [...mensagens].sort(
    (uma, outra) => uma.created_at - outra.created_at || uma.id - outra.id
  );

// Os anexos das mensagens carregadas, no formato da galeria do painel.
const anexosDas = mensagens =>
  mensagens.flatMap(mensagem =>
    (mensagem.attachments || []).map(anexo => ({
      ...anexo,
      message_id: mensagem.id,
      created_at: mensagem.created_at,
      sender: mensagem.sender,
    }))
  );

export const useVisorDaConversa = numero => {
  const conversa = ref(null);
  const mensagens = ref([]);
  const carregando = ref(false);
  const carregandoAntigas = ref(false);
  const erro = ref(false);
  const erroAntigas = ref(false);
  const temAntigas = ref(false);
  // Trocar de conversa no meio da busca descarta a resposta da anterior.
  let vez = 0;

  const carregar = async () => {
    vez += 1;
    const minha = vez;
    const id = toValue(numero);
    conversa.value = null;
    mensagens.value = [];
    erro.value = false;
    erroAntigas.value = false;
    carregandoAntigas.value = false;
    temAntigas.value = false;
    if (!id) return;
    carregando.value = true;
    try {
      const [{ data: dados }, { data: lista }] = await Promise.all([
        ConversationAPI.show(id),
        MessageApi.getPreviousMessages({ conversationId: id }),
      ]);
      if (minha !== vez) return;
      const recebidas = lista?.payload || [];
      conversa.value = dados;
      mensagens.value = emOrdem(recebidas);
      temAntigas.value = recebidas.length >= PAGINA;
    } catch {
      if (minha === vez) erro.value = true;
    } finally {
      if (minha === vez) carregando.value = false;
    }
  };

  const carregarAntigas = async () => {
    const id = toValue(numero);
    const primeira = mensagens.value[0];
    if (!id || !primeira || !temAntigas.value || carregandoAntigas.value) {
      return false;
    }
    const minha = vez;
    carregandoAntigas.value = true;
    erroAntigas.value = false;
    try {
      const { data } = await MessageApi.getPreviousMessages({
        conversationId: id,
        before: primeira.id,
      });
      if (minha !== vez) return false;
      const recebidas = data?.payload || [];
      mensagens.value = emOrdem([...recebidas, ...mensagens.value]);
      temAntigas.value = recebidas.length >= PAGINA;
      return recebidas.length > 0;
    } catch {
      if (minha === vez) erroAntigas.value = true;
      return false;
    } finally {
      if (minha === vez) carregandoAntigas.value = false;
    }
  };

  watch(() => toValue(numero), carregar, { immediate: true });

  return {
    conversa: computed(() =>
      conversa.value ? { ...conversa.value, messages: mensagens.value } : null
    ),
    mensagens,
    anexos: computed(() => anexosDas(mensagens.value)),
    carregando,
    carregandoAntigas,
    erro,
    erroAntigas,
    temAntigas,
    carregarAntigas,
    recarregar: carregar,
  };
};
