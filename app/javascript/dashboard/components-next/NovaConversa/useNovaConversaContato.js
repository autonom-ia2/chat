import { computed, ref } from 'vue';
import { debounce } from '@chatwoot/utils';
import { useMapGetter } from 'dashboard/composables/store';
import {
  buildContactableInboxesList,
  createContactSearcher,
  createNewContact,
  fetchContactableInboxes,
  mergeInboxDetails,
} from 'dashboard/components-next/NewConversation/helpers/composeConversationHelper';
import { ordenarCanais } from './novaConversa';

// #1459 — "Para quem" e "Por onde": a busca de contato, o contato escolhido e
// os canais em que ele pode ser alcançado (sempre perguntados ao servidor,
// que é quem diz se o WhatsApp aceita texto livre).
const ESPERA_DA_BUSCA = 400;

export function useNovaConversaContato() {
  const buscar = createContactSearcher();
  const caixas = useMapGetter('inboxes/getInboxes');
  const contatoPorId = useMapGetter('contacts/getContactById');

  const contato = ref(null);
  const canais = ref([]);
  const canalId = ref(null);
  const carregandoCanais = ref(false);
  const erroNosCanais = ref(false);

  const termo = ref('');
  const resultados = ref([]);
  const buscando = ref(false);
  const erroNaBusca = ref(false);
  const criando = ref(false);
  const erroAoCriar = ref(false);

  const canal = computed(
    () => canais.value.find(item => item.id === canalId.value) || null
  );

  // Cada pedido de canais leva um número. Só o último pedido pode mexer no
  // estado: resposta, erro ou "carregando" de um pedido antigo (de outro
  // contato, ou do mesmo, pedido antes) são descartados.
  let ultimoPedido = 0;

  const receberCanais = alcancaveis => {
    canais.value = ordenarCanais(
      buildContactableInboxesList(mergeInboxDetails(alcancaveis, caixas.value))
    );
    // "Começar pronto": o primeiro da ordem já vem marcado. Recarregando os
    // canais do mesmo contato, o que a pessoa escolheu continua escolhido.
    const mantem = canais.value.some(item => item.id === canalId.value);
    if (!mantem) canalId.value = canais.value[0]?.id ?? null;
  };

  const carregarCanais = async () => {
    const id = contato.value?.id;
    if (!id) return;
    ultimoPedido += 1;
    const pedido = ultimoPedido;
    carregandoCanais.value = true;
    erroNosCanais.value = false;
    try {
      const alcancaveis = await fetchContactableInboxes(id);
      if (pedido === ultimoPedido) receberCanais(alcancaveis);
    } catch (error) {
      if (pedido === ultimoPedido) erroNosCanais.value = true;
    } finally {
      if (pedido === ultimoPedido) carregandoCanais.value = false;
    }
  };

  // A busca espera um instante antes de sair (debounce). Cada tecla ganha um
  // número; a busca que acordar com número antigo não faz nada.
  let ultimaBusca = 0;

  const encerrarBusca = () => {
    ultimaBusca += 1;
    // Chamar o buscador sem texto cancela o pedido que estiver no ar.
    buscar('');
    termo.value = '';
    resultados.value = [];
    buscando.value = false;
    erroNaBusca.value = false;
  };

  const soltarCanais = () => {
    // Invalida o pedido de canais que estiver no ar.
    ultimoPedido += 1;
    canais.value = [];
    canalId.value = null;
    carregandoCanais.value = false;
    erroNosCanais.value = false;
  };

  const escolherContato = escolhido => {
    const mesmo = String(contato.value?.id ?? '') === String(escolhido.id);
    encerrarBusca();
    if (!mesmo) soltarCanais();
    contato.value = escolhido;
    return carregarCanais();
  };

  const usarContatoDaPagina = id => {
    const daPagina = contatoPorId.value(id);
    return escolherContato({ ...daPagina, id: daPagina.id ?? Number(id) });
  };

  const limparContato = () => {
    contato.value = null;
    soltarCanais();
  };

  const procurar = debounce(
    async (texto, busca) => {
      if (busca !== ultimaBusca) return;
      erroNaBusca.value = false;
      try {
        const achados = await buscar(texto);
        // null = pedido cancelado; número antigo = a pessoa já seguiu adiante.
        if (achados === null || busca !== ultimaBusca) return;
        resultados.value = achados;
      } catch (error) {
        if (busca !== ultimaBusca) return;
        erroNaBusca.value = true;
      }
      buscando.value = false;
    },
    ESPERA_DA_BUSCA,
    false
  );

  const mudarTermo = texto => {
    ultimaBusca += 1;
    termo.value = texto;
    erroAoCriar.value = false;
    buscando.value = texto.trim().length > 1;
    if (!buscando.value) resultados.value = [];
    procurar(texto, ultimaBusca);
  };

  const criarContato = async () => {
    criando.value = true;
    erroAoCriar.value = false;
    try {
      await escolherContato(await createNewContact(termo.value.trim()));
    } catch (error) {
      erroAoCriar.value = true;
    } finally {
      criando.value = false;
    }
  };

  return {
    contato,
    canais,
    canalId,
    canal,
    carregandoCanais,
    erroNosCanais,
    termo,
    resultados,
    buscando,
    erroNaBusca,
    criando,
    erroAoCriar,
    carregarCanais,
    escolherContato,
    usarContatoDaPagina,
    limparContato,
    mudarTermo,
    criarContato,
  };
}
