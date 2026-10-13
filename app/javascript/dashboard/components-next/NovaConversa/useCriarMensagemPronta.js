import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { getUserPermissions } from 'dashboard/helper/permissionsHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { PERMISSOES_PARA_CRIAR } from 'dashboard/routes/dashboard/campaigns/modelos/helpers/usePodeCriarModelo';

// #1459 — "Criar mensagem pronta", só para quem pode: a mesma régua da rota
// de criar modelo (administrador ou função com whatsapp_templates_manage). Com
// a jornada de Modelos ligada, vai direto para criar, já na caixa escolhida;
// sem ela, vai para a lista (que o guarda da rota leva à tela de sempre).
const CRIAR = 'modelos_whatsapp_novo';
const LISTA = 'modelos_whatsapp_lista';

export function useCriarMensagemPronta() {
  const route = useRoute();
  const router = useRouter();
  const usuario = useMapGetter('getCurrentUser');
  const contaId = useMapGetter('getCurrentAccountId');
  const flagLigadaNaConta = useMapGetter('accounts/isFeatureEnabledonAccount');

  const podeCriar = computed(() =>
    getUserPermissions(usuario.value, contaId.value).some(permissao =>
      PERMISSOES_PARA_CRIAR.includes(permissao)
    )
  );
  const direto = computed(
    () =>
      Boolean(
        flagLigadaNaConta.value(
          contaId.value,
          FEATURE_FLAGS.WHATSAPP_TEMPLATES_JOURNEY
        )
      ) && router.hasRoute(CRIAR)
  );

  const irCriar = caixaId => {
    const params = { accountId: route.params.accountId };
    return router.push(
      direto.value
        ? { name: CRIAR, params, query: { caixa: caixaId } }
        : { name: LISTA, params }
    );
  };

  return { podeCriar, irCriar };
}
