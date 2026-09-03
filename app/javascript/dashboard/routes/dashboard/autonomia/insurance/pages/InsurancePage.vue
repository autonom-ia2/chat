<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import InsuranceConnectionsTab from '../components/InsuranceConnectionsTab.vue';
import InsuranceAgentTab from '../components/InsuranceAgentTab.vue';

// Página "Cotação" (PRD §8): um cabeçalho e duas abas — Conexões e Agente. Sem páginas
// adicionais no MVP. Cada aba é uma rota nomeada própria para o sidebar marcar o item ativo.
const props = defineProps({
  tab: {
    type: String,
    default: 'connections',
    validator: value => ['connections', 'agent'].includes(value),
  },
});

const { t } = useI18n();
const router = useRouter();

const tabs = computed(() => [
  {
    key: 'connections',
    route: 'autonomia_insurance_connections',
    icon: 'i-lucide-plug-zap',
    label: t('INSURANCE.TABS.CONNECTIONS'),
  },
  {
    key: 'agent',
    route: 'autonomia_insurance_agent',
    icon: 'i-lucide-bot',
    label: t('INSURANCE.TABS.AGENT'),
  },
]);

const pillClass = key =>
  props.tab === key
    ? 'bg-n-solid-2 text-n-slate-12 shadow-sm'
    : 'text-n-slate-11 hover:text-n-slate-12';

const onTabChanged = item => {
  if (item.key === props.tab) return;
  router.push({ name: item.route });
};
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-hidden bg-n-background">
    <header
      class="flex flex-col flex-shrink-0 gap-4 px-6 py-4 border-b border-n-weak"
    >
      <div class="flex items-center min-w-0 gap-3">
        <span
          class="flex items-center justify-center rounded-lg shrink-0 size-9 bg-n-iris-3 text-n-iris-11"
        >
          <span class="i-lucide-shield-check size-5" />
        </span>
        <div class="flex flex-col min-w-0">
          <h1 class="text-base font-medium leading-tight text-n-slate-12">
            {{ t('INSURANCE.TITLE') }}
          </h1>
          <p class="text-xs truncate text-n-slate-11">
            {{ t('INSURANCE.SUBTITLE') }}
          </p>
        </div>
      </div>

      <div
        role="tablist"
        class="inline-flex self-start items-center gap-1 p-1 rounded-lg bg-n-alpha-1"
      >
        <button
          v-for="item in tabs"
          :key="item.key"
          type="button"
          role="tab"
          :aria-selected="tab === item.key"
          class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-md text-sm font-medium transition-colors"
          :class="pillClass(item.key)"
          @click="onTabChanged(item)"
        >
          <i :class="item.icon" class="size-4" />
          {{ item.label }}
        </button>
      </div>
    </header>

    <div class="flex-1 min-h-0 overflow-y-auto px-6 py-6">
      <InsuranceConnectionsTab v-if="tab === 'connections'" />
      <InsuranceAgentTab v-else />
    </div>
  </div>
</template>
