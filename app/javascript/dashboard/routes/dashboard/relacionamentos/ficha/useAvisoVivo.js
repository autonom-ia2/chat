// #2894 — o texto da região viva da ficha (`AvisoVivo`). A região fica na tela
// desde o início; aqui só se troca o texto. Esvazia antes de escrever, para que
// o mesmo aviso dito duas vezes seguidas seja anunciado duas vezes.
import { nextTick, ref } from 'vue';

export const useAvisoVivo = () => {
  const aviso = ref('');

  const anunciar = async texto => {
    aviso.value = '';
    await nextTick();
    aviso.value = texto;
  };

  return { aviso, anunciar };
};
