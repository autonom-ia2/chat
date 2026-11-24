import { onBeforeUnmount, ref, watch } from 'vue';

// #3192 — telas cujo botão de enviar mora no canto de baixo à direita, o mesmo
// da bolinha do Guia no celular. A tela avisa enquanto o canto é dela, e a
// bolinha some. Só a tela sabe: a criação de agente (rota /agents/new) mostra
// primeiro a escolha do modelo, sem caixa de envio, onde a bolinha fica.
export const cantoOcupadoPelaTela = ref(false);

export const useOcuparCantoDaBolinha = ocupado => {
  watch(
    ocupado,
    valor => {
      cantoOcupadoPelaTela.value = valor;
    },
    { immediate: true }
  );
  onBeforeUnmount(() => {
    cantoOcupadoPelaTela.value = false;
  });
};
