<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// chat#1067 — últimos 7 dias pelo WhatsApp API, por quem enviou. A tabela rola de lado no celular.
const props = defineProps({
  stats: { type: Object, default: () => ({}) },
});

const { t } = useI18n();
const originLabel = origin =>
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  t(`INBOX_MGMT.WHATSAPP_HYBRID.ORIGINS.${origin.toUpperCase()}`);

const ORIGINS = ['human', 'bot', 'automation', 'crm_follow_up', 'campaign'];
const DEFAULT_DAYS = 7;

const rows = computed(() => {
  const byOrigin = props.stats?.by_origin || {};
  return ORIGINS.map(origin => {
    const row = byOrigin[origin] || {};
    return {
      origin,
      sent: row.sent || 0,
      failed:
        (row.failed || 0) + (row.uncertain || 0) + (row.disconnected || 0),
      waited: row.throttled || 0,
      fallback: row.fallback || 0,
    };
  });
});
const hasStats = computed(() =>
  rows.value.some(row => row.sent || row.failed || row.waited)
);
</script>

<template>
  <section
    data-hybrid-stats
    class="flex flex-col gap-3 p-5 sm:p-6 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
  >
    <h2 class="m-0 text-lg font-semibold text-n-slate-12">
      {{
        $t('INBOX_MGMT.WHATSAPP_HYBRID.STATS.TITLE', {
          days: stats?.days || DEFAULT_DAYS,
        })
      }}
    </h2>
    <p v-if="!hasStats" class="mb-0 text-sm text-n-slate-11">
      {{ $t('INBOX_MGMT.WHATSAPP_HYBRID.STATS.EMPTY') }}
    </p>
    <div v-else class="-mx-1 overflow-x-auto">
      <table class="w-full text-sm min-w-[22rem]">
        <thead>
          <tr class="text-left text-n-slate-11">
            <th scope="col" class="px-1 py-2 font-normal">
              {{ $t('INBOX_MGMT.WHATSAPP_HYBRID.STATS.WHO') }}
            </th>
            <th scope="col" class="px-1 py-2 font-normal text-right">
              {{ $t('INBOX_MGMT.WHATSAPP_HYBRID.STATS.SENT') }}
            </th>
            <th scope="col" class="px-1 py-2 font-normal text-right">
              {{ $t('INBOX_MGMT.WHATSAPP_HYBRID.STATS.FAILED') }}
            </th>
            <th scope="col" class="px-1 py-2 font-normal text-right">
              {{ $t('INBOX_MGMT.WHATSAPP_HYBRID.STATS.WAITED') }}
            </th>
            <th scope="col" class="px-1 py-2 font-normal text-right">
              {{ $t('INBOX_MGMT.WHATSAPP_HYBRID.STATS.FALLBACK') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in rows"
            :key="row.origin"
            class="border-t border-n-weak text-n-slate-12"
          >
            <th scope="row" class="px-1 py-2 font-normal text-left">
              {{ originLabel(row.origin) }}
            </th>
            <td class="px-1 py-2 text-right tabular-nums">{{ row.sent }}</td>
            <td class="px-1 py-2 text-right tabular-nums">{{ row.failed }}</td>
            <td class="px-1 py-2 text-right tabular-nums">{{ row.waited }}</td>
            <td class="px-1 py-2 text-right tabular-nums">
              {{ row.fallback }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </section>
</template>
