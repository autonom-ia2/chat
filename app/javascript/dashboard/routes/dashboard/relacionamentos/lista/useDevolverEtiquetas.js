import { computed, ref } from 'vue';

// #3062 — o aviso de "Tirar etiquetas" com "Desfazer". Depois de tirar, a
// página mostra a frase do que foi feito (`mostrar`) e guarda, para cada
// etiqueta, quem a tinha. "Desfazer" (`desfazer`) recoloca cada etiqueta nas
// mesmas pessoas, uma etiqueta depois da outra, pela mesma ação de colocar da
// lista; deu certo, a frase diz que voltaram e o botão some; falhou, a frase diz
// e o botão fica para tentar de novo. O aviso fica até a próxima ação
// (`limpar`), como o da carteira: desfazer não tem prazo.
export const useDevolverEtiquetas = ({ acoes, t, aoDevolver }) => {
  const ET = 'RELACIONAMENTOS.LISTA.ETIQUETA';
  const texto = ref('');
  const devolver = ref([]);
  const desfazendo = ref(false);

  const mostrar = ({ frase, devolver: quem }) => {
    texto.value = frase;
    devolver.value = quem;
  };

  const limpar = () => {
    texto.value = '';
    devolver.value = [];
  };

  // Uma etiqueta por vez; a primeira que falha para o resto.
  const recolocar = () =>
    devolver.value.reduce(
      (cadeia, { etiqueta, ids }) =>
        cadeia.then(async () => {
          const feito = await acoes.aplicarEtiqueta({
            pessoas: ids.map(id => ({ id })),
            etiquetas: [etiqueta],
          });
          if (feito.erro) throw feito.erro;
        }),
      Promise.resolve()
    );

  const desfazer = async () => {
    if (desfazendo.value || !devolver.value.length) return;
    desfazendo.value = true;
    try {
      await recolocar();
      mostrar({ frase: t(`${ET}.DEVOLVIDAS`), devolver: [] });
      aoDevolver();
    } catch {
      texto.value = t(`${ET}.ERRO_AO_DEVOLVER`);
    } finally {
      desfazendo.value = false;
    }
  };

  return {
    texto,
    podeDesfazer: computed(() => devolver.value.length > 0),
    desfazendo,
    mostrar,
    limpar,
    desfazer,
  };
};
