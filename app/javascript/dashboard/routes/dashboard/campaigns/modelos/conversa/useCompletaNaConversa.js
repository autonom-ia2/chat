import { computed, unref } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { getUserPermissions } from 'dashboard/helper/permissionsHelper.js';
import {
  PERMISSOES_PARA_CRIAR,
  PERMISSOES_PARA_VER,
} from '../helpers/usePodeCriarModelo';

const WHATSAPP_CLOUD = 'whatsapp_cloud';

// O que a escolha de modelo da conversa consegue completar (#1716), para o
// getter `inboxes/getConversationWhatsAppTemplates`:
// - só no WhatsApp oficial (a caixa que fala com a Meta e tem catálogo);
// - só para quem vê os modelos (WhatsappTemplatePolicy): a galeria de fotos e
//   o catálogo vêm das telas de Modelos;
// - produtos só com a flag whatsapp_campaign_products, como na campanha;
// - foto do computador só para quem cria modelo, com a jornada de Modelos
//   ligada (o mesmo upload de mídia dos Modelos).
export function useCompletaNaConversa(caixa) {
  const usuario = useMapGetter('getCurrentUser');
  const contaId = useMapGetter('getCurrentAccountId');
  const caixaPorId = useMapGetter('inboxes/getInbox');
  const { isCloudFeatureEnabled } = useAccount();

  const permissoes = computed(() =>
    getUserPermissions(usuario.value, contaId.value)
  );
  const tem = lista => permissoes.value.some(item => lista.includes(item));
  const oficial = computed(() => {
    const inbox = caixaPorId.value(unref(caixa)) || {};
    return (
      inbox.channel_type === INBOX_TYPES.WHATSAPP &&
      inbox.provider === WHATSAPP_CLOUD
    );
  });

  const opcoes = computed(() => {
    if (!oficial.value || !tem(PERMISSOES_PARA_VER)) return {};
    return {
      completa: {
        fotos: true,
        produtos: isCloudFeatureEnabled(
          FEATURE_FLAGS.WHATSAPP_CAMPAIGN_PRODUCTS
        ),
      },
    };
  });

  const podeSubirFoto = computed(
    () =>
      tem(PERMISSOES_PARA_CRIAR) &&
      isCloudFeatureEnabled(FEATURE_FLAGS.WHATSAPP_TEMPLATES_JOURNEY)
  );

  return { opcoes, podeSubirFoto };
}
