import { ref } from 'vue';
import fonte from './fonte';

// #1428 (protótipo da Fase 2) — "Mudar conversando" conferido: cada pedido vira um item aplicado (✓)
// ou uma dúvida (⚠) com resposta rápida, mais o resultado das perguntas de prova e o Desfazer. A
// conversa fica aqui (não na store do Construtor) porque a resposta vem do adaptador (prototipo/fonte).
export function useMudarConferido() {
  const mensagens = ref([]);
  const pensando = ref(false);
  const erro = ref(false);
  const resultado = ref(null);
  const desfazendo = ref(false);
  const desfeito = ref(false);

  const falar = (role, content) => {
    mensagens.value = [...mensagens.value, { role, content }];
  };

  const responder = async (texto, acao) => {
    falar('user', texto);
    pensando.value = true;
    erro.value = false;
    try {
      const novo = await acao();
      falar('assistant', novo.resposta);
      resultado.value = { itens: novo.itens, prova: novo.prova };
      desfeito.value = false;
    } catch {
      erro.value = true;
    } finally {
      pensando.value = false;
    }
  };

  const enviar = texto => responder(texto, () => fonte.aplicarPedido(texto));

  const responderDuvida = (item, opcao) =>
    responder(opcao.texto, () =>
      fonte.responderDuvida(resultado.value, item.id, opcao.valor)
    );

  const desfazer = async () => {
    if (desfazendo.value) return;
    desfazendo.value = true;
    try {
      await fonte.desfazer();
      desfeito.value = true;
    } catch {
      erro.value = true;
    } finally {
      desfazendo.value = false;
    }
  };

  const limparErro = () => {
    erro.value = false;
  };

  return {
    mensagens,
    pensando,
    erro,
    resultado,
    desfazendo,
    desfeito,
    enviar,
    responderDuvida,
    desfazer,
    limparErro,
  };
}
