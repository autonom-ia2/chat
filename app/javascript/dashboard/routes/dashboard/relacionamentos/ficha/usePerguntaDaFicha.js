import { nextTick, ref } from 'vue';

// #3071 — a pergunta antes de um passo que apaga ou restringe (apagar a pessoa,
// bloquear, marcar "não quer mensagens", apagar uma nota). Um diálogo só
// (components/carteira/DialogoDeConfirmacao.vue), com os textos de cada
// pergunta. `perguntar({ marca, titulo, aviso, confirmar, tipo, agir, erro })`
// (e `empilhado`, para um botão embaixo do outro quando o rótulo é longo):
// `agir()` devolve `true` quando deu certo, e o diálogo fecha; senão a frase
// fica dentro dele (a do servidor, `motivo()`, ou `erro`), e ele continua
// aberto para tentar de novo. `depois()`, opcional, roda com o diálogo já
// fechado: o fechar do diálogo devolve o foco a quem o abriu, e quem quer
// levar o foco a outro lugar (a faixa que apareceu) faz isso aqui.
export const usePerguntaDaFicha = ({ dialogo, motivo }) => {
  const pergunta = ref(null);
  const alerta = ref('');

  const perguntar = async nova => {
    pergunta.value = nova;
    alerta.value = '';
    await nextTick();
    dialogo.value?.abrir();
  };

  const confirmar = async () => {
    const atual = pergunta.value;
    if (!atual) return;
    alerta.value = '';
    if (await atual.agir()) {
      dialogo.value?.fechar();
      await nextTick();
      atual.depois?.();
      return;
    }
    alerta.value = motivo() || atual.erro;
  };

  return { pergunta, alerta, perguntar, confirmar };
};
