// A tela da conversa decide a pele uma vez e a fornece às bolhas e à caixa de
// resposta (#1702). Chave desligada na conta = sem pele = conversa de sempre.
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { fusoDaConta } from 'dashboard/helper/fusoDaConta';
import {
  PELES,
  caixaGravaMarkdown,
  fornecerCaixaEmMarkdown,
  fornecerFuso,
  fornecerPele,
  peleDaCaixa,
} from './pele';
import {
  CAIXA_DE_RESPOSTA,
  FUNDO_DA_CONVERSA,
  TOPO_DA_CONVERSA,
} from './visualWhatsapp';

// A pele da conversa aberta, sem fornecer (o topo da conversa só lê).
export const usePeleDaConversaAberta = () => {
  const conversa = useMapGetter('getSelectedChat');
  const caixaPorId = useMapGetter('inboxes/getInbox');
  const { isCloudFeatureEnabled } = useAccount();

  const pele = computed(() =>
    peleDaCaixa(
      caixaPorId.value(conversa.value?.inbox_id),
      isCloudFeatureEnabled(FEATURE_FLAGS.CONVERSA_CARA_DO_CANAL)
    )
  );
  return pele;
};

export const usePeleDaConversa = () => {
  const pele = usePeleDaConversaAberta();
  fornecerPele(pele);
  const conversa = useMapGetter('getSelectedChat');
  const caixaPorId = useMapGetter('inboxes/getInbox');
  fornecerCaixaEmMarkdown(
    computed(() =>
      caixaGravaMarkdown(caixaPorId.value(conversa.value?.inbox_id))
    )
  );
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
