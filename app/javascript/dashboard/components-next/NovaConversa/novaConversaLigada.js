import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

// #1459 — a tela nova de "Nova conversa" fica atrás da flag de conta
// `nova_conversa_tela`. A leitura mora só aqui: os pontos de uso passam pela
// ponte (NovaConversaEntrada) e não sabem da flag. Desligada na conta atual,
// volta o popover antigo.
export function useNovaConversaLigada() {
  const contaId = useMapGetter('getCurrentAccountId');
  const flagLigadaNaConta = useMapGetter('accounts/isFeatureEnabledonAccount');

  return computed(() =>
    Boolean(
      flagLigadaNaConta.value(contaId.value, FEATURE_FLAGS.NOVA_CONVERSA_TELA)
    )
  );
}
