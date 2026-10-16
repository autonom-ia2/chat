// Para a lista de mensagens com pele (#1702): qual balão abre uma sequência (leva o
// bico) e onde o dia muda (leva a etiqueta do dia). Sem pele, nada muda na lista.
import { computed } from 'vue';
import { fornecerPrimeiras, useFuso, usePele } from './pele';
import { diaDaMensagem } from './dataDaConversa';

export const useSequenciaDaConversa = (mensagens, agrupaComAProxima) => {
  const pele = usePele();
  const fuso = useFuso();

  // A mensagem abre sequência quando a anterior não se agrupa com ela.
  const primeiras = computed(() => {
    if (!pele.value) return new Set();
    const lista = mensagens.value;
    return new Set(
      lista
        .filter((_, i) => i === 0 || !agrupaComAProxima(i - 1, lista))
        .map(mensagem => mensagem.id)
    );
  });
  fornecerPrimeiras(primeiras);

  // Calculado uma vez por mudança na lista (não a cada balão desenhado).
  const quemAbreODia = computed(() => {
    if (!pele.value) return new Set();
    const lista = mensagens.value;
    const dias = lista.map(mensagem =>
      diaDaMensagem(mensagem.createdAt, fuso.value)
    );
    return new Set(
      lista
        .filter((_, i) => i === 0 || dias[i] !== dias[i - 1])
        .map(mensagem => mensagem.id)
    );
  });
  const abreODia = index => quemAbreODia.value.has(mensagens.value[index]?.id);

  return { abreODia, pele };
};
