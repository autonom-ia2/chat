<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import PreviewFrame from 'dashboard/components-next/preview-frame/PreviewFrame.vue';

// chat#1487 — a prévia muda com as escolhas: dois casos concretos (um lembrete do CRM e uma resposta da equipe) e o
// ritmo. Quem não está marcado só manda mensagem pronta pelo número oficial.
const props = defineProps({
  routingOn: { type: Boolean, default: true },
  enabled: { type: Array, default: () => [] },
  rate: { type: Number, required: true },
});

const { t } = useI18n();
const V = 'INBOX_MGMT.WHATSAPP_HYBRID.ROUTING.PREVIEW';
// eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
const tv = (key, params) => t(`${V}.${key}`, params);

const viaApi = key => props.routingOn && props.enabled.includes(key);

const cases = computed(() => [
  {
    key: 'crm_follow_up',
    icon: 'i-lucide-bell-ring',
    web: viaApi('crm_follow_up'),
    text: viaApi('crm_follow_up')
      ? tv('FOLLOW_UP_WEB')
      : tv('FOLLOW_UP_TEMPLATE'),
  },
  {
    key: 'human',
    icon: 'i-lucide-headset',
    web: viaApi('human'),
    text: viaApi('human') ? tv('AGENT_WEB') : tv('AGENT_TEMPLATE'),
  },
]);
</script>

<template>
  <PreviewFrame data-routing-preview :badge="tv('BADGE')" :title="tv('TITLE')">
    <ul class="flex flex-col gap-3 p-0 m-0 list-none" aria-live="polite">
      <li
        v-for="item in cases"
        :key="item.key"
        :data-case="item.key"
        :data-web="item.web"
        class="flex items-start gap-3 p-4 text-sm leading-relaxed rounded-2xl ring-1 ring-inset text-n-slate-12"
        :class="
          item.web ? 'bg-n-teal-2 ring-n-teal-6' : 'bg-n-slate-2 ring-n-slate-6'
        "
      >
        <span
          class="size-5 mt-0.5 shrink-0"
          :class="[item.icon, item.web ? 'text-n-teal-11' : 'text-n-slate-11']"
          aria-hidden="true"
        />
        <span>{{ item.text }}</span>
      </li>
      <li
        v-if="routingOn"
        data-case="pace"
        class="flex items-start gap-3 px-1 text-sm text-n-slate-11"
      >
        <span
          class="i-lucide-gauge size-4 mt-0.5 shrink-0"
          aria-hidden="true"
        />
        <span>{{ tv('PACE', { n: rate }) }}</span>
      </li>
    </ul>
  </PreviewFrame>
</template>
