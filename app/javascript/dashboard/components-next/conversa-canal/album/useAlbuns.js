// A lista de mensagens calcula os álbuns uma vez (#1702) e conta a cada balão se ele
// abre um álbum. Sem pele, nenhum álbum: a conversa fica como sempre.
import { computed, inject, provide } from 'vue';
import { useFuso, usePele } from '../pele';
import { agruparAlbuns } from './agruparAlbuns';

const CHAVE_ALBUNS = Symbol('albunsDaConversa');

export const useAlbunsDaConversa = (mensagens, primeiraNaoLida) => {
  const pele = usePele();
  const fuso = useFuso();

  const albuns = computed(() => {
    if (!pele.value) return new Map();
    return agruparAlbuns(mensagens.value, {
      fuso: fuso.value,
      abreBloco: mensagem => mensagem.id === primeiraNaoLida?.value,
    });
  });
  provide(CHAVE_ALBUNS, albuns);

  // Os itens 2, 3… do álbum não ganham balão próprio: aparecem no mosaico do 1º.
  const dentroDeAlbum = computed(() => {
    const ids = new Set();
    albuns.value.forEach(itens =>
      itens.slice(1).forEach(item => ids.add(item.id))
    );
    return ids;
  });

  return { escondida: id => dentroDeAlbum.value.has(id) };
};

// As mensagens do álbum que este balão abre, ou null.
export const useAlbumDaMensagem = id => {
  const albuns = inject(
    CHAVE_ALBUNS,
    computed(() => new Map())
  );
  return computed(() => albuns.value.get(id.value) || null);
};
