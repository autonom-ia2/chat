import { computed, onBeforeUnmount, ref, watch } from 'vue';
import BuscaDaListaAPI from 'dashboard/api/buscaDaLista';
import { emitter } from 'shared/helpers/mitt';
import {
  BUSCA_DESATUALIZADA,
  ESPERA_DA_DIGITACAO_MS,
  prontoParaBuscar,
} from './buscaDaLista';

// #2211 — o estado da busca da lista: busca a cada letra, 300 ms depois da última, a partir de 2
// letras (telefone a partir de 4 dígitos). A resposta de um texto antigo não sobrescreve a do texto
// novo: o pedido anterior é cancelado.
const VAZIO = {
  conversas: [],
  mensagens: [],
  pessoas: [],
  telefoneNovo: null,
  emailNovo: null,
  textoLivreNasCaixas: [],
  caixasParaComecar: [],
  parcial: false,
};

export function useBuscaDaLista() {
  const texto = ref('');
  const resultado = ref(VAZIO);
  const buscado = ref('');
  const carregando = ref(false);
  const erro = ref(false);
  let espera = null;
  let pedido = null;

  const ativa = computed(() => prontoParaBuscar(texto.value));

  const cancelar = () => {
    clearTimeout(espera);
    pedido?.abort();
    pedido = null;
  };

  const buscar = async () => {
    cancelar();
    const q = texto.value.trim();
    if (!prontoParaBuscar(q)) return;
    pedido = new AbortController();
    const { signal } = pedido;
    carregando.value = true;
    erro.value = false;
    try {
      const { data } = await BuscaDaListaAPI.buscar(q, { signal });
      const { payload } = data;
      resultado.value = {
        conversas: payload.conversations || [],
        mensagens: payload.messages || [],
        pessoas: payload.contacts || [],
        telefoneNovo: payload.telefone_novo || null,
        // E-mail que ainda não é de ninguém: quem decide que é e-mail é o servidor; sem o campo, nada.
        emailNovo: payload.email_novo || null,
        // #2257: caixas em que o telefone novo já pode receber texto livre (Híbrido).
        textoLivreNasCaixas: payload.texto_livre_nas_caixas || [],
        // Caixas em que dá para começar conversa com o telefone ou o e-mail novo (InboxPolicy#show?).
        caixasParaComecar: payload.caixas_para_comecar || [],
        // Seção que passou do tempo no servidor volta vazia: a tela avisa.
        parcial: Boolean(payload.parcial?.length),
      };
      buscado.value = q;
    } catch (falha) {
      if (signal.aborted) return;
      erro.value = true;
    }
    carregando.value = false;
  };

  watch(texto, () => {
    clearTimeout(espera);
    if (!ativa.value) {
      cancelar();
      resultado.value = VAZIO;
      buscado.value = '';
      carregando.value = false;
      erro.value = false;
      return;
    }
    carregando.value = true;
    espera = setTimeout(buscar, ESPERA_DA_DIGITACAO_MS);
  });

  const limpar = () => {
    texto.value = '';
  };

  // Enviou pela conversa vazia: quem era "sem conversa" (ou o telefone novo) agora tem conversa.
  const refazer = () => {
    if (ativa.value) buscar();
  };
  emitter.on(BUSCA_DESATUALIZADA, refazer);

  onBeforeUnmount(() => {
    cancelar();
    emitter.off(BUSCA_DESATUALIZADA, refazer);
  });

  return { texto, ativa, resultado, buscado, carregando, erro, buscar, limpar };
}
