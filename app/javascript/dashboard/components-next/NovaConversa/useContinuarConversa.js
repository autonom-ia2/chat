import { computed, ref, watch } from 'vue';
import ConversationAPI from 'dashboard/api/inbox/conversation';
import {
  DESTINOS,
  chaveDaEscolha,
  conversaDeDestino,
  conversaDoCanal,
  tipoAoContinuar,
} from './continuarConversa';

// #1505 — continuar a conversa que o contato já tem na caixa. Guarda a
// escolha ("Continuar" ou "Começar conversa nova") e pergunta ao servidor se
// a conversa aceita texto livre (`can_reply`). Trocar de contato ou de canal
// zera a escolha: o padrão volta a "Continuar".
export function useContinuarConversa({ contato, canal }) {
  const destino = ref(DESTINOS.CONTINUAR);
  const podeResponder = ref(false);
  const carregando = ref(false);
  const erro = ref(false);

  const existente = computed(() => conversaDoCanal(canal.value));
  const conversa = computed(() =>
    conversaDeDestino({ canal: canal.value, destino: destino.value })
  );
  const tipo = computed(() =>
    conversa.value
      ? tipoAoContinuar({
          canal: canal.value,
          podeResponder: podeResponder.value,
        })
      : ''
  );
  // Enquanto não se sabe o que a conversa aceita, a mensagem não aparece e o
  // envio fica parado.
  const esperando = computed(
    () => Boolean(conversa.value) && (carregando.value || erro.value)
  );

  // Só o último pedido mexe no estado (mesmo cuidado da lista de canais).
  let ultimoPedido = 0;

  const carregar = async () => {
    ultimoPedido += 1;
    const pedido = ultimoPedido;
    const alvo = existente.value;
    podeResponder.value = false;
    erro.value = false;
    carregando.value = Boolean(alvo);
    if (!alvo) return;
    try {
      const { data } = await ConversationAPI.show(alvo.displayId);
      if (pedido === ultimoPedido)
        podeResponder.value = data?.can_reply === true;
    } catch (error) {
      if (pedido === ultimoPedido) erro.value = true;
    } finally {
      if (pedido === ultimoPedido) carregando.value = false;
    }
  };

  watch(
    () => chaveDaEscolha({ contato: contato.value, canal: canal.value }),
    () => {
      destino.value = DESTINOS.CONTINUAR;
      carregar();
    },
    { immediate: true }
  );

  return {
    destino,
    existente,
    conversa,
    tipo,
    carregando,
    erro,
    esperando,
    carregar,
  };
}
