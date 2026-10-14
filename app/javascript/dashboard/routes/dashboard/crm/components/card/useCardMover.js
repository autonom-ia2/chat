import { ref } from 'vue';

// #1423 — mudar de etapa: na tela Etapa muda na hora; tocando numa coluna do
// quadro "Onde está no funil", pede uma confirmação curta antes.
export const useCardMover = ({ podeMover, movendo, emit }) => {
  const dialogo = ref(null);
  const pedida = ref(null);
  const mover = etapaId =>
    podeMover.value && !movendo.value && emit('move', etapaId);
  const pedir = etapa => {
    if (!etapa || !podeMover.value) return;
    pedida.value = etapa;
    dialogo.value?.open();
  };
  const confirmar = () => {
    dialogo.value?.close();
    if (pedida.value) mover(pedida.value.id);
  };
  return { dialogo, pedida, mover, pedir, confirmar };
};
