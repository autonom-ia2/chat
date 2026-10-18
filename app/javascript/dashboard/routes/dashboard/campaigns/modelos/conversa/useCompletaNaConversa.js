import { computed, unref } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

const WHATSAPP_CLOUD = 'whatsapp_cloud';

// O que a escolha de modelo da conversa consegue completar (#1716), para o
// getter `inboxes/getConversationWhatsAppTemplates`. Decisão do Rodrigo
// (16/10/2026): vale para quem atende a caixa, sem a tela de Modelos
// (Whatsapp::Templates::ConversationAssetsPolicy no servidor):
// - só no WhatsApp oficial (a caixa que fala com a Meta e tem catálogo);
// - só numa caixa que a pessoa atende (a lista de caixas da tela já é a dela;
//   o servidor confere de novo);
// - produtos só com a flag whatsapp_campaign_products, como na campanha.
export function useCompletaNaConversa(caixa) {
  const caixaPorId = useMapGetter('inboxes/getInbox');
  const { isCloudFeatureEnabled } = useAccount();

  const oficial = computed(() => {
    const inbox = caixaPorId.value(unref(caixa)) || {};
    return (
      inbox.channel_type === INBOX_TYPES.WHATSAPP &&
      inbox.provider === WHATSAPP_CLOUD
    );
  });

  const opcoes = computed(() => {
    if (!oficial.value) return {};
    return {
      completa: {
        fotos: true,
        produtos: isCloudFeatureEnabled(
          FEATURE_FLAGS.WHATSAPP_CAMPAIGN_PRODUCTS
        ),
      },
    };
  });

  // Quem atende a caixa também manda a foto do computador para um cartão.
  const podeSubirFoto = oficial;

  return { opcoes, podeSubirFoto };
}
