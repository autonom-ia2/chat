import { onBeforeUnmount, ref } from 'vue';

// #1423 — "Sair sem salvar?" (DS-01). A página chama `guardar` ao trocar de
// card ou abrir outra coisa; as telas chamam ao voltar e fechar. Rascunho de
// outra tela só pesa quando a pessoa sai do card. Enquanto algo vai para o
// servidor (`ocupado`), nada fecha nem volta.
export const useCardGuarda = ({
  formato,
  tela,
  editando,
  rascunhos,
  sujoNaTela,
  ocupado,
  descartarTudo,
}) => {
  const dialogo = ref(null);
  const aberto = ref(false);
  const perdas = ref('');
  let depois = null;

  const guardar = (acao, { leaving = false } = {}) => {
    if (ocupado()) return;
    const sujos = rascunhos();
    const daTela = sujoNaTela()[tela.value];
    if (sujos.length && (leaving || daTela || !editando.value)) {
      depois = acao;
      perdas.value = formato.juntar(sujos);
      aberto.value = true;
      dialogo.value?.open();
      return;
    }
    acao();
  };
  const confirmar = () => {
    const acao = depois;
    depois = null;
    descartarTudo();
    dialogo.value?.close();
    acao?.();
  };
  onBeforeUnmount(() => {
    depois = null;
  });
  return { dialogo, aberto, perdas, guardar, confirmar };
};
