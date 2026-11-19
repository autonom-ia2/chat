import { computed, ref } from 'vue';

// #3071 — o aviso com "Desfazer" da ficha da pessoa (o mesmo desenho do aviso
// da lista e da carteira, components/carteira/AvisoComDesfazer.vue). Depois de
// bloquear, de marcar "não quer mensagens" ou de mudar as etiquetas, a página
// mostra a frase (`mostrar(frase, desfazer)`). `desfazer` é uma função que
// devolve { certo, frase }: deu certo, a frase diz e o botão some; falhou, a
// frase diz e o botão fica para tentar de novo. O aviso fica até a próxima
// ação (`limpar`): desfazer não tem prazo.
export const useDesfazerNaFicha = () => {
  const texto = ref('');
  const acao = ref(null);
  const desfazendo = ref(false);

  const mostrar = (frase, desfazer = null) => {
    texto.value = frase;
    acao.value = desfazer;
  };

  const limpar = () => mostrar('');

  const desfazer = async () => {
    if (desfazendo.value || !acao.value) return;
    desfazendo.value = true;
    try {
      const { certo, frase } = await acao.value();
      texto.value = frase;
      if (certo) acao.value = null;
    } finally {
      desfazendo.value = false;
    }
  };

  return {
    texto,
    podeDesfazer: computed(() => Boolean(acao.value)),
    desfazendo,
    mostrar,
    limpar,
    desfazer,
  };
};
