<script setup>
import { ref, watch, computed } from 'vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';

// chat#1067 — envio automático: por onde sai cada mensagem, quem pode usar o WhatsApp API depois de 24 horas e a
// velocidade. Cada linha inteira é o alvo do toque (44 px) e dá nome ao interruptor para o leitor de tela.
const props = defineProps({
  state: { type: Object, required: true },
});

const emit = defineEmits(['save']);

const ORIGINS = ['human', 'bot', 'automation', 'crm_follow_up', 'campaign'];
const MIN_RATE = 1;
const MAX_RATE = 120;
const DEFAULT_RATE = 20;

const rateLimit = ref(props.state.rate_limit_per_minute || DEFAULT_RATE);
watch(
  () => props.state.rate_limit_per_minute,
  value => {
    rateLimit.value = value || DEFAULT_RATE;
  }
);

const disabledOrigins = computed(() => props.state.disabled_origins || []);

const toggleOrigin = (origin, enabled) => {
  const others = disabledOrigins.value.filter(item => item !== origin);
  emit('save', { disabled_origins: enabled ? others : [...others, origin] });
};

const saveRateLimit = () => {
  const value = Math.min(
    Math.max(parseInt(rateLimit.value, 10) || MIN_RATE, MIN_RATE),
    MAX_RATE
  );
  rateLimit.value = value;
  emit('save', { rate_limit_per_minute: value });
};
</script>

<template>
  <section
    data-hybrid-routing
    class="flex flex-col gap-5 p-5 sm:p-6 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
  >
    <label class="flex items-start justify-between gap-4 cursor-pointer">
      <span class="flex flex-col gap-1">
        <span class="text-lg font-semibold text-n-slate-12">
          {{ $t('INBOX_MGMT.WHATSAPP_HYBRID.ROUTING.TITLE') }}
        </span>
        <span class="text-sm text-n-slate-11">
          {{ $t('INBOX_MGMT.WHATSAPP_HYBRID.ROUTING.DESCRIPTION') }}
        </span>
      </span>
      <Switch
        class="mt-1.5"
        :model-value="Boolean(state.routing_enabled)"
        @update:model-value="value => emit('save', { routing_enabled: value })"
      />
    </label>

    <dl
      class="grid grid-cols-[1fr_auto] gap-x-6 gap-y-2 px-4 py-3 m-0 text-sm rounded-xl bg-n-alpha-1"
    >
      <dt class="text-n-slate-11">
        {{ $t('INBOX_MGMT.WHATSAPP_HYBRID.ROUTING.INSIDE') }}
      </dt>
      <dd class="m-0 font-semibold text-n-slate-12">
        {{ $t('INBOX_MGMT.WHATSAPP_HYBRID.OFFICIAL') }}
      </dd>
      <dt class="text-n-slate-11">
        {{ $t('INBOX_MGMT.WHATSAPP_HYBRID.ROUTING.OUTSIDE') }}
      </dt>
      <dd data-routing-outside class="m-0 font-semibold text-n-slate-12">
        {{
          state.routing_active
            ? $t('INBOX_MGMT.WHATSAPP_HYBRID.WEB')
            : $t('INBOX_MGMT.WHATSAPP_HYBRID.OFFICIAL')
        }}
      </dd>
      <dt class="text-n-slate-11">
        {{ $t('INBOX_MGMT.WHATSAPP_HYBRID.ROUTING.TEMPLATES') }}
      </dt>
      <dd class="m-0 font-semibold text-n-slate-12">
        {{ $t('INBOX_MGMT.WHATSAPP_HYBRID.OFFICIAL') }}
      </dd>
    </dl>

    <fieldset class="flex flex-col gap-1 p-0 m-0 border-0">
      <legend class="mb-1 text-base font-semibold text-n-slate-12">
        {{ $t('INBOX_MGMT.WHATSAPP_HYBRID.ORIGINS.TITLE') }}
      </legend>
      <label
        v-for="origin in ORIGINS"
        :key="origin"
        :data-origin="origin"
        class="flex items-center justify-between gap-3 cursor-pointer min-h-11"
      >
        <span class="text-sm text-n-slate-12">
          <!-- eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys -->
          {{ $t(`INBOX_MGMT.WHATSAPP_HYBRID.ORIGINS.${origin.toUpperCase()}`) }}
        </span>
        <Switch
          :model-value="!disabledOrigins.includes(origin)"
          @update:model-value="value => toggleOrigin(origin, value)"
        />
      </label>
    </fieldset>

    <div class="flex flex-col gap-2 pt-4 border-t border-n-weak">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <label for="hybrid-rate-limit" class="text-sm text-n-slate-12">
          {{ $t('INBOX_MGMT.WHATSAPP_HYBRID.RATE_LIMIT') }}
        </label>
        <input
          id="hybrid-rate-limit"
          v-model="rateLimit"
          type="number"
          inputmode="numeric"
          :min="MIN_RATE"
          :max="MAX_RATE"
          class="w-24 px-3 mb-0 text-sm border rounded-xl min-h-11 border-n-weak bg-n-alpha-black2 text-n-slate-12"
          @change="saveRateLimit"
        />
      </div>
      <p class="mb-0 text-xs text-n-slate-11">
        {{
          $t('INBOX_MGMT.WHATSAPP_HYBRID.CAMPAIGN_LIMIT', {
            limit: state.campaign_rate_limit_per_minute || 10,
          })
        }}
      </p>
    </div>
  </section>
</template>
