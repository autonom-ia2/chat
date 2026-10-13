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

  const carregarCanais = async () => {
    const id = contato.value?.id;
    if (!id) return;
    carregandoCanais.value = true;
    erroNosCanais.value = false;
    try {
      const alcancaveis = await fetchContactableInboxes(id);
      // A resposta chegou depois de a pessoa trocar de contato: descarta.
      if (contato.value?.id !== id) return;
      canais.value = ordenarCanais(
        buildContactableInboxesList(
          mergeInboxDetails(alcancaveis, caixas.value)
        )
      );
      // "Começar pronto": o primeiro da ordem já vem marcado.
      canalId.value = canais.value[0]?.id ?? null;
    } catch (error) {
      erroNosCanais.value = true;
    } finally {
      carregandoCanais.value = false;
    }
  };

  const escolherContato = escolhido => {
    contato.value = escolhido;
    canais.value = [];
    canalId.value = null;
    termo.value = '';
    resultados.value = [];
    return carregarCanais();
  };

  const usarContatoDaPagina = id => {
    const daPagina = contatoPorId.value(id);
    return escolherContato({ ...daPagina, id: daPagina.id ?? Number(id) });
  };

  const limparContato = () => {
    contato.value = null;
    canais.value = [];
    canalId.value = null;
  };

  const procurar = debounce(
    async texto => {
      erroNaBusca.value = false;
      try {
        const achados = await buscar(texto);
        // null = pedido cancelado por uma busca mais nova.
        if (achados === null) return;
        resultados.value = achados;
      } catch (error) {
        erroNaBusca.value = true;
      }
      buscando.value = false;
    },
    ESPERA_DA_BUSCA,
    false
  );

  const mudarTermo = texto => {
    termo.value = texto;
    erroAoCriar.value = false;
    buscando.value = texto.trim().length > 1;
    if (!buscando.value) resultados.value = [];
    procurar(texto);
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
