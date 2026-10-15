<script setup>
import { useI18n } from 'vue-i18n';
import CheckCard from 'dashboard/components-next/check-card/CheckCard.vue';
import { ROUTING_ORIGINS } from '../whatsappHybridState';

// chat#1487 — quem pode usar o WhatsApp API depois de 24 horas: um cartão marcável por origem, com um exemplo de
// uma linha. Atendentes e lembretes do CRM levam o selo "Recomendado"; campanhas, o aviso de risco.
const enabled = defineModel({ type: Array, required: true });

const { t } = useI18n();
const R = 'INBOX_MGMT.WHATSAPP_HYBRID.ROUTING.WHO';
// eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
const tw = key => t(`${R}.${key}`);

const toggle = (key, on) => {
  const others = enabled.value.filter(item => item !== key);
  enabled.value = on ? [...others, key] : others;
};
</script>

<template>
  <fieldset class="p-0 m-0 border-0">
    <legend class="mb-3 text-base text-n-slate-12">
      {{ tw('DRAWER_TEXT') }}
    </legend>
    <div class="grid gap-3 sm:grid-cols-2">
      <CheckCard
        v-for="origin in ROUTING_ORIGINS"
        :key="origin.key"
        :data-origin="origin.key"
        :model-value="enabled.includes(origin.key)"
        :icon="origin.icon"
        :title="tw(`ORIGINS.${origin.key.toUpperCase()}.TITLE`)"
        :description="tw(`ORIGINS.${origin.key.toUpperCase()}.EXAMPLE`)"
        @update:model-value="value => toggle(origin.key, value)"
      >
        <template v-if="origin.recommended || origin.risky" #selos>
          <span
            v-if="origin.recommended"
            class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-semibold rounded-lg bg-n-teal-3 text-n-teal-11"
          >
            <span class="i-lucide-thumbs-up size-3.5" aria-hidden="true" />
            {{ tw('RECOMMENDED') }}
          </span>
          <span
            v-if="origin.risky"
            data-risk
            class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-semibold rounded-lg bg-n-amber-3 text-n-amber-11"
          >
            <span class="i-lucide-triangle-alert size-3.5" aria-hidden="true" />
            {{ tw('RISK') }}
          </span>
        </template>
      </CheckCard>
    </div>
  </fieldset>
</template>
