<script setup>
import { computed } from 'vue';
import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import BasePaywallModal from 'dashboard/routes/dashboard/settings/components/BasePaywallModal.vue';

// O mesmo bloqueio de plano da tela de hoje (CustomRolePaywall), com o texto em pt-BR de FUNCOES_EQUIPE.
const router = useRouter();
const isOnChatwootCloud = useMapGetter('globalConfig/isOnChatwootCloud');
const currentUser = useMapGetter('getCurrentUser');
const currentAccountId = useMapGetter('getCurrentAccountId');

const isSuperAdmin = computed(() => currentUser.value.type === 'SuperAdmin');
const i18nKey = computed(() =>
  isOnChatwootCloud.value ? 'PAYWALL' : 'ENTERPRISE_PAYWALL'
);

const goToBillingSettings = () =>
  router.push({
    name: 'billing_settings_index',
    params: { accountId: currentAccountId.value },
  });
</script>

<template>
  <div data-paywall class="flex justify-center w-full py-10">
    <BasePaywallModal
      feature-prefix="FUNCOES_EQUIPE"
      :i18n-key="i18nKey"
      :is-on-chatwoot-cloud="isOnChatwootCloud"
      :is-super-admin="isSuperAdmin"
      @upgrade="goToBillingSettings"
    />
  </div>
</template>
