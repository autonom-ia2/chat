<script setup>
import { computed } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

// #1149 (R16) — aqui se escolhe quem atende a caixa. Quem vê o quê no CRM
// (funis, cards e conversas) fica num lugar só: CRM → Caixas no CRM. O aviso
// só aparece com o CRM e a tela nova ligados na conta.
const props = defineProps({
  inboxId: { type: [Number, String], required: true },
});

const store = useStore();
const { t } = useI18n();
// O nome da tela de caixas sai de uma chave só (o título dela).
const lugar = computed(() => t('CRM_CAIXAS.LISTA.TITULO'));
const accountId = computed(() => store.getters.getCurrentAccountId);
const ligado = computed(
  () =>
    window.globalConfig?.CRM_KANBAN_ENABLED === 'true' &&
    store.getters['accounts/getAccount']?.(accountId.value)?.features?.[
      FEATURE_FLAGS.CRM_CONFIGURAR_CAIXAS
    ] === true
);
const destino = computed(() => ({
  name: 'crm_caixa',
  params: { accountId: accountId.value, inboxId: props.inboxId },
}));
</script>

<template>
  <aside
    v-if="ligado"
    data-aviso-quem-ve
    class="mb-6 flex items-start gap-3 rounded-2xl border border-n-blue-6 bg-n-blue-2 p-4"
  >
    <span
      class="i-lucide-eye mt-0.5 size-5 shrink-0 text-n-blue-11"
      aria-hidden="true"
    />
    <div class="flex min-w-0 flex-col gap-1">
      <p class="mb-0 text-sm font-medium text-n-slate-12">
        {{ $t('CRM_CAIXAS.AVISO_AGENTES.TITULO') }}
      </p>
      <p class="mb-0 text-sm text-n-slate-11">
        {{ $t('CRM_CAIXAS.AVISO_AGENTES.TEXTO', { lugar }) }}
      </p>
      <router-link
        :to="destino"
        class="inline-flex min-h-11 w-fit items-center gap-2 text-sm font-medium text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      >
        {{ $t('CRM_CAIXAS.AVISO_AGENTES.LINK', { lugar }) }}
        <span
          class="i-lucide-arrow-right size-4 rtl:rotate-180"
          aria-hidden="true"
        />
      </router-link>
    </div>
  </aside>
</template>
