<script setup>
import { useI18n } from 'vue-i18n';

// Passo a passo fixo, sem IA: o Guia da Plataforma só funciona DEPOIS da chave,
// então este passo precisa se sustentar sozinho. O texto vem do que mais
// trava o cliente nas chamadas de onboarding — crédito, recarga automática,
// validade da chave e a cópia única.
const { t } = useI18n();

const PASSOS = [
  'ACCOUNT',
  'BILLING',
  'AUTO_RECHARGE',
  'CREATE_KEY',
  'COPY_NOW',
  'PASTE_HERE',
];

const AVISOS = ['SUBSCRIPTION', 'CARD'];

const LINK_CHAVES = 'https://platform.openai.com/api-keys';
const LINK_BILLING =
  'https://platform.openai.com/settings/organization/billing/overview';
</script>

<template>
  <section
    class="outline outline-n-container outline-1 bg-n-card rounded-xl p-6 flex flex-col gap-4"
  >
    <div class="flex flex-col gap-1">
      <h3 class="mb-0 text-heading-2 text-n-slate-12">
        {{ t('INTEGRATION_APPS.OPENAI_KEY_GUIDE.TITLE') }}
      </h3>
      <p class="mb-0 text-body-main text-n-slate-11">
        {{ t('INTEGRATION_APPS.OPENAI_KEY_GUIDE.SUBTITLE') }}
      </p>
    </div>

    <ol class="flex flex-col gap-3 m-0 p-0 list-none">
      <li
        v-for="(passo, indice) in PASSOS"
        :key="passo"
        class="flex items-start gap-3"
      >
        <span
          class="shrink-0 size-6 rounded-full bg-n-alpha-2 text-n-slate-12 text-xs font-medium flex items-center justify-center tabular-nums"
        >
          {{ indice + 1 }}
        </span>
        <p class="mb-0 text-body-main text-n-slate-12">
          {{ t(`INTEGRATION_APPS.OPENAI_KEY_GUIDE.STEPS.${passo}`) }}
        </p>
      </li>
    </ol>

    <ul class="flex flex-col gap-2 m-0 p-0 list-none">
      <li
        v-for="aviso in AVISOS"
        :key="aviso"
        class="flex items-start gap-2 rounded-lg bg-n-amber-3 px-3 py-2"
      >
        <span
          class="i-lucide-triangle-alert shrink-0 mt-0.5 size-4 text-n-amber-11"
        />
        <p class="mb-0 text-sm text-n-slate-12">
          {{ t(`INTEGRATION_APPS.OPENAI_KEY_GUIDE.WARNINGS.${aviso}`) }}
        </p>
      </li>
    </ul>

    <div class="flex flex-wrap gap-4">
      <a
        :href="LINK_BILLING"
        target="_blank"
        rel="noopener noreferrer"
        class="text-sm font-medium text-n-blue-text hover:underline"
      >
        {{ t('INTEGRATION_APPS.OPENAI_KEY_GUIDE.LINKS.BILLING') }}
      </a>
      <a
        :href="LINK_CHAVES"
        target="_blank"
        rel="noopener noreferrer"
        class="text-sm font-medium text-n-blue-text hover:underline"
      >
        {{ t('INTEGRATION_APPS.OPENAI_KEY_GUIDE.LINKS.KEYS') }}
      </a>
    </div>
  </section>
</template>
