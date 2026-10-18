<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useBranding } from 'shared/composables/useBranding';
import { getUserPermissions } from 'dashboard/helper/permissionsHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { PERMISSOES_PARA_CRIAR } from 'dashboard/routes/dashboard/campaigns/modelos/helpers/usePodeCriarModelo';
import AutorizacaoResumo from 'dashboard/routes/dashboard/campaigns/modelos/components/AutorizacaoResumo.vue';

// Avisos do WhatsApp oficial Cloud (#1612): no lugar do antigo "Criar os
// modelos na Meta", o que vale agora. Com a autorização do dono ligada, o
// sistema pede à Meta os modelos v2 dos avisos (NoticeTemplateEnsureJob). O
// resumo da autorização, com o caminho para ver ou mudar, só para quem a vê na
// tela de Modelos: a mesma régua da rota (administrador ou
// whatsapp_templates_manage, com a jornada de Modelos ligada na conta).
const { t } = useI18n();
const { installationName } = useBranding();
const usuario = useMapGetter('getCurrentUser');
const contaId = useMapGetter('getCurrentAccountId');
const flagLigadaNaConta = useMapGetter('accounts/isFeatureEnabledonAccount');

const marca = computed(() => installationName.value || 'Chat2You');
const podeVerAutorizacao = computed(
  () =>
    getUserPermissions(usuario.value, contaId.value).some(permissao =>
      PERMISSOES_PARA_CRIAR.includes(permissao)
    ) &&
    Boolean(
      flagLigadaNaConta.value(
        contaId.value,
        FEATURE_FLAGS.WHATSAPP_TEMPLATES_JOURNEY
      )
    )
);
</script>

<template>
  <div data-notice-autorizacao class="flex flex-col gap-3">
    <p class="m-0 text-base text-n-slate-11">
      {{ t('BOOKING.NOTICES.AUTO.SYSTEM_TEMPLATES_HINT', { marca }) }}
    </p>
    <AutorizacaoResumo v-if="podeVerAutorizacao" />
  </div>
</template>
