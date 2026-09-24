<script setup>
// A IA da prospecção roda só na chave do CRM Kanban AI da conta (#683). Sem ela,
// o enriquecimento traz apenas o que está no site, e a tela precisa dizer isso.
import { useI18n } from 'vue-i18n';
import { CRM_AI_INTEGRATION_ID } from 'dashboard/helper/crmAiKey';

const { t } = useI18n();

const integrationRoute = {
  name: 'settings_applications_integration',
  params: { integration_id: CRM_AI_INTEGRATION_ID },
};
</script>

<template>
  <div
    role="status"
    class="flex items-start gap-3 rounded-md border border-n-amber-5 bg-n-amber-2 p-3 text-sm"
  >
    <span
      class="i-lucide-triangle-alert mt-0.5 size-4 shrink-0 text-n-amber-11"
    />
    <div class="grid gap-1">
      <p class="font-medium text-n-amber-12">
        {{ t('PROSPECTING.AI_CREDENTIAL.MISSING_TITLE') }}
      </p>
      <p class="text-n-amber-11">
        {{ t('PROSPECTING.AI_CREDENTIAL.MISSING_DESCRIPTION') }}
      </p>
      <router-link
        :to="integrationRoute"
        class="w-fit font-medium text-n-blue-11 underline"
      >
        {{ t('PROSPECTING.AI_CREDENTIAL.CONFIGURE') }}
      </router-link>
    </div>
  </div>
</template>
