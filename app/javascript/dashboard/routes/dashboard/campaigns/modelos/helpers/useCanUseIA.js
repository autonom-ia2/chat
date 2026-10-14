import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { usePodeCriarModelo } from './usePodeCriarModelo';

// "Criar com IA" e "Melhorar com IA" (#1333): só com a flag do piloto
// (whatsapp_templates_ai, conta 16; Refs #1450) e para quem cria e altera
// modelo (administrador ou whatsapp_templates_manage). Sem a flag, a tela é a
// de sempre, sem IA. Com ela e sem IA configurada, o botão responde com a frase
// simples e o texto continua editável à mão.
export function useCanUseIA() {
  const podeCriar = usePodeCriarModelo();
  const accountId = useMapGetter('getCurrentAccountId');
  const isFeatureEnabledonAccount = useMapGetter(
    'accounts/isFeatureEnabledonAccount'
  );
  return computed(
    () =>
      podeCriar.value &&
      isFeatureEnabledonAccount.value(
        accountId.value,
        FEATURE_FLAGS.WHATSAPP_TEMPLATES_AI
      )
  );
}
