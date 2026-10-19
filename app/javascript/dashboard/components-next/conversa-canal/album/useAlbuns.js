// A lista de mensagens calcula os álbuns uma vez (#1702) e conta a cada balão se ele
// abre um álbum. Sem pele, nenhum álbum: a conversa fica como sempre. No mesmo esquema,
// os contatos mandados de uma vez (mesmo sourceId, uma mensagem por contato) viram um
// cartão só, desenhado pela 1ª mensagem.
// Álbum chegando (#1831): a conta usa a hora de agora, e um relógio refaz a conta quando
// a janela do álbum fecha, para o "Recebendo fotos…" sair sozinho. A tela guarda quando
// viu cada marcador pela 1ª vez (relógio do navegador), que limita a janela de um
// relógio atrasado ou adiantado (janelaDoMarcador).
import { computed, inject, onBeforeUnmount, provide, ref, watch } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useFuso, usePele } from '../pele';
import { agruparDaConversa } from './agruparAlbuns';
import { agruparContatos } from '../midia/contatos';

const CHAVE_ALBUNS = Symbol('albunsDaConversa');
const CHAVE_CONTATOS = Symbol('contatosDaConversa');
const CHAVE_CHEGADAS = Symbol('albunsChegando');
const CHAVE_QUADRADOS = Symbol('albunsEmQuadrados');
const CHAVE_ANUNCIADOS = Symbol('albunsAnunciados');

const VAZIO = {
  albuns: new Map(),
  marcadores: new Set(),
  chegadas: new Map(),
  emQuadrados: new Set(),
  anunciados: new Map(),
};

const agoraEmSegundos = () => Date.now() / 1000;
// O relógio dispara logo depois do fim da janela, não no limite exato.
const FOLGA_EM_MS = 50;

// Um relógio só, armado para o fim da janela mais próxima entre os álbuns chegando.
const useRelogioDasChegadas = (chegadas, aoFechar) => {
  let relogio = null;
  const desarmar = () => {
    clearTimeout(relogio);
    relogio = null;
  };
  watch(
    chegadas,
    lista => {
      desarmar();
      const fins = [...lista.values()].map(chegada => chegada.ate);
      if (!fins.length) return;
      const espera = (Math.min(...fins) - agoraEmSegundos()) * 1000;
      relogio = setTimeout(aoFechar, Math.max(0, espera) + FOLGA_EM_MS);
    },
    { immediate: true }
  );
  onBeforeUnmount(desarmar);
};

export const useAlbunsDaConversa = (mensagens, primeiraNaoLida) => {
  const pele = usePele();
  const fuso = useFuso();
  // Muda quando uma janela fecha, só para a conta ser refeita; a hora usada é sempre
  // a de agora (uma mensagem nova também refaz a conta).
  const janelaFechou = ref(0);
  const conversa = useMapGetter('getSelectedChat');
  // id do marcador -> quando esta tela o viu pela 1ª vez (segundos). Só cresce.
  const vistos = new Map();
  const vistoEm = id => {
    if (!vistos.has(id)) vistos.set(id, agoraEmSegundos());
    return vistos.get(id);
  };

  const agrupados = computed(() => {
    if (!pele.value) return VAZIO;
    janelaFechou.value; // eslint-disable-line no-unused-expressions
    return agruparDaConversa(mensagens.value, {
      fuso: fuso.value,
      abreBloco: mensagem => mensagem.id === primeiraNaoLida?.value,
      agora: agoraEmSegundos(),
      vistoEm,
      grupo: conversa.value?.whatsapp_api_group === true,
    });
  });
  const albuns = computed(() => agrupados.value.albuns);
  provide(CHAVE_ALBUNS, albuns);
  const chegadas = computed(() => agrupados.value.chegadas);
  provide(CHAVE_CHEGADAS, chegadas);
  provide(
    CHAVE_QUADRADOS,
    computed(() => agrupados.value.emQuadrados)
  );
  provide(
    CHAVE_ANUNCIADOS,
    computed(() => agrupados.value.anunciados)
  );
  useRelogioDasChegadas(chegadas, () => {
    janelaFechou.value += 1;
  });

  const contatos = computed(() =>
    pele.value ? agruparContatos(mensagens.value) : new Map()
  );
  provide(CHAVE_CONTATOS, contatos);

  // Os itens do álbum não ganham balão próprio: aparecem no mosaico do balão que o
  // desenha (a chave: o 1º item, ou o marcador do WAHA). O marcador da Cloud com fotos
  // também some. Idem os contatos 2, 3… do mesmo envio.
  const escondidas = computed(() => {
    const ids = new Set(agrupados.value.marcadores);
    const esconderOsOutros = (itens, chave) =>
      itens.forEach(item => item.id !== chave && ids.add(item.id));
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

const QUADRADOS_VAZIO = computed(() => new Set());

// O álbum que este balão abre é desenhado em quadrados (veio de um marcador)?
export const useAlbumEmQuadrados = id => {
  const emQuadrados = inject(CHAVE_QUADRADOS, QUADRADOS_VAZIO);
  return computed(() => emQuadrados.value.has(id.value));
};

// O álbum que este balão abre ainda está chegando? { esperados, noMarcador, ate } ou null.
export const useChegadaDoAlbum = id => {
  const chegadas = inject(CHAVE_CHEGADAS, MAPA_VAZIO);
  return computed(() => chegadas.value.get(id.value) || null);
};

// Quantas fotos e vídeos o WAHA anunciou para o álbum que este balão abre, ou null.
export const useAnunciadoDoAlbum = id => {
  const anunciados = inject(CHAVE_ANUNCIADOS, MAPA_VAZIO);
  return computed(() => anunciados.value.get(id.value) ?? null);
};

// As mensagens de contato do mesmo envio que este balão abre (2+), ou null.
export const useContatosDaMensagem = id => {
  const contatos = inject(CHAVE_CONTATOS, MAPA_VAZIO);
  return computed(() => contatos.value.get(id?.value) || null);
};
