<script setup>
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import NextButton from 'dashboard/components-next/button/Button.vue';

// Aba Agente (PRD §18-19). Nesta entrega é só o ponto de entrada: o Agente de Cotação nasce
// como `agent_type=insurance_quote` no módulo Agentes Autonom.ia (#296), reaproveitando
// builder, vínculo com inbox, versões de instrução e Desempenho. Sem módulo paralelo.
const { t } = useI18n();
const router = useRouter();

const goToBuilder = () => {
  router.push({ name: 'autonomia_agents_builder' });
};

const goToAgents = () => {
  router.push({ name: 'autonomia_agents_index' });
};

const PILLARS = ['COLLECT', 'QUOTE', 'EXPLAIN', 'CRM'];
</script>

<template>
  <div class="flex flex-col gap-6 max-w-3xl">
    <section class="rounded-xl border border-n-weak bg-n-solid-1 px-5 py-5">
      <div class="flex items-start gap-4">
        <span
          class="flex items-center justify-center rounded-lg shrink-0 size-10 bg-n-iris-3 text-n-iris-11"
        >
          <span class="i-lucide-bot size-5" />
        </span>
        <div class="flex flex-col gap-2 min-w-0">
          <h2 class="text-sm font-medium text-n-slate-12">
            {{ t('INSURANCE.AGENT.TITLE') }}
          </h2>
          <p class="text-sm text-n-slate-11">
            {{ t('INSURANCE.AGENT.DESCRIPTION') }}
          </p>
        </div>
      </div>

      <ul class="grid gap-3 mt-5 sm:grid-cols-2">
        <li
          v-for="key in PILLARS"
          :key="key"
          class="flex items-start gap-2 px-3 py-2 rounded-lg bg-n-alpha-1 text-sm"
        >
          <span class="i-lucide-check size-4 mt-0.5 text-n-teal-11 shrink-0" />
          <span class="text-n-slate-12">
            {{ t(`INSURANCE.AGENT.PILLARS.${key}`) }}
          </span>
        </li>
      </ul>

      <p class="mt-5 text-xs text-n-slate-11">
        {{ t('INSURANCE.AGENT.LOCKED_NOTE') }}
      </p>

      <div class="flex flex-wrap items-center gap-2 mt-5">
        <NextButton
          solid
          blue
          icon="i-lucide-sparkles"
          :label="t('INSURANCE.AGENT.ACTIONS.CREATE')"
          @click="goToBuilder"
        />
        <NextButton
          faded
          slate
          icon="i-lucide-list"
          :label="t('INSURANCE.AGENT.ACTIONS.OPEN_AGENTS')"
          @click="goToAgents"
        />
      </div>
    </section>
  </div>
</template>
