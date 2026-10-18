// A tela da conversa decide a pele uma vez e a fornece às bolhas e à caixa de
// resposta (#1702). Chave desligada na conta = sem pele = conversa de sempre.
import { computed, toValue } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { fusoDaConta } from 'dashboard/helper/fusoDaConta';
import { PELES, fornecerFuso, fornecerPele, peleDaCaixa } from './pele';
import {
  CAIXA_DE_RESPOSTA,
  FUNDO_DA_CONVERSA,
  TOPO_DA_CONVERSA,
} from './visualWhatsapp';

// A pele de uma caixa: chave da conta ligada e caixa do WhatsApp.
const usePeleDaCaixa = idDaCaixa => {
  const caixaPorId = useMapGetter('inboxes/getInbox');
  const { isCloudFeatureEnabled } = useAccount();

  return computed(() =>
    peleDaCaixa(
      caixaPorId.value(toValue(idDaCaixa)),
      isCloudFeatureEnabled(FEATURE_FLAGS.CONVERSA_CARA_DO_CANAL)
    )
  );
};

// A pele da conversa aberta, sem fornecer (o topo da conversa só lê).
export const usePeleDaConversaAberta = () => {
  const conversa = useMapGetter('getSelectedChat');
  return usePeleDaCaixa(() => conversa.value?.inbox_id);
};

// A pele da caixa de uma mensagem solta, fora da conversa aberta (a última mensagem
// na lista de conversas). Mesmo critério da conversa: sem pele, prévia de sempre.
export const usePeleDaMensagem = mensagem =>
  usePeleDaCaixa(() => toValue(mensagem)?.inbox_id);

export const usePeleDaConversa = () => {
  const pele = usePeleDaConversaAberta();
  fornecerPele(pele);
  const { currentAccount } = useAccount();
  fornecerFuso(computed(() => fusoDaConta(currentAccount.value)));

  const ehWhatsapp = computed(() => pele.value === PELES.WHATSAPP);

  return {
    pele,
    classesDaLista: computed(() => (ehWhatsapp.value ? FUNDO_DA_CONVERSA : '')),
    classesDaBarra: computed(() =>
      ehWhatsapp.value ? CAIXA_DE_RESPOSTA.barra : ''
    ),
  };
};

// O topo da conversa (nome, botões) com a faixa cinza do app.
export const usePeleDoTopo = () => {
  const pele = usePeleDaConversaAberta();
  return computed(() =>
    pele.value === PELES.WHATSAPP ? TOPO_DA_CONVERSA : ''
  );
};
