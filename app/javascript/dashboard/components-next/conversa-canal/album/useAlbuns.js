// A lista de mensagens calcula os álbuns uma vez (#1702) e conta a cada balão se ele
// abre um álbum. Sem pele, nenhum álbum: a conversa fica como sempre. No mesmo esquema,
// os contatos mandados de uma vez (mesmo sourceId, uma mensagem por contato) viram um
// cartão só, desenhado pela 1ª mensagem.
import { computed, inject, provide } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useFuso, usePele } from '../pele';
import { agruparDaConversa } from './agruparAlbuns';
import { agruparContatos } from '../midia/contatos';

const CHAVE_ALBUNS = Symbol('albunsDaConversa');
const CHAVE_CONTATOS = Symbol('contatosDaConversa');

const VAZIO = { albuns: new Map(), marcadores: new Set() };

export const useAlbunsDaConversa = (mensagens, primeiraNaoLida) => {
  const pele = usePele();
  const fuso = useFuso();
  const conversa = useMapGetter('getSelectedChat');

  const agrupados = computed(() => {
    if (!pele.value) return VAZIO;
    return agruparDaConversa(mensagens.value, {
      fuso: fuso.value,
      abreBloco: mensagem => mensagem.id === primeiraNaoLida?.value,
      grupo: conversa.value?.whatsapp_api_group === true,
    });
  });
  const albuns = computed(() => agrupados.value.albuns);
  provide(CHAVE_ALBUNS, albuns);

  const contatos = computed(() =>
    pele.value ? agruparContatos(mensagens.value) : new Map()
  );
  provide(CHAVE_CONTATOS, contatos);

  // Os itens 2, 3… do álbum não ganham balão próprio: aparecem no mosaico do 1º. O
  // marcador do álbum (o "pai" que a Cloud não mostra) também some. Idem os contatos
  // 2, 3… do mesmo envio.
  const escondidas = computed(() => {
    const ids = new Set(agrupados.value.marcadores);
    const esconderOsOutros = itens =>
      itens.slice(1).forEach(item => ids.add(item.id));
    albuns.value.forEach(esconderOsOutros);
    // O grupo de contatos vem na ordem do envio: some todo item que não é o balão
    // que desenha o cartão (a chave do mapa).
    contatos.value.forEach((itens, chave) =>
      itens.forEach(item => item.id !== chave && ids.add(item.id))
    );
    return ids;
  });

  return { escondida: id => escondidas.value.has(id) };
};

const MAPA_VAZIO = computed(() => new Map());

// As mensagens do álbum que este balão abre, ou null.
export const useAlbumDaMensagem = id => {
  const albuns = inject(CHAVE_ALBUNS, MAPA_VAZIO);
  return computed(() => albuns.value.get(id.value) || null);
};

// As mensagens de contato do mesmo envio que este balão abre (2+), ou null.
export const useContatosDaMensagem = id => {
  const contatos = inject(CHAVE_CONTATOS, MAPA_VAZIO);
  return computed(() => contatos.value.get(id?.value) || null);
};
