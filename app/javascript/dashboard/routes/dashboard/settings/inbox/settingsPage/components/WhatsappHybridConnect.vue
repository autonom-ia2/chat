<script setup>
import Button from 'dashboard/components-next/button/Button.vue';

// chat#1487 — antes de conectar: a ordem certa, em três passos curtos, e uma ação só.
defineProps({
  isBusy: { type: Boolean, default: false },
});

const emit = defineEmits(['connect']);

const STEPS = ['STEP_1', 'STEP_2', 'STEP_3'];
</script>

<template>
  <div class="flex flex-col items-start gap-4">
    <h2 class="m-0 text-lg font-semibold text-n-slate-12">
      {{ $t('INBOX_MGMT.WHATSAPP_HYBRID.STATE.NOT_CONNECTED_TITLE') }}
    </h2>
    <p class="mb-0 text-sm font-medium text-n-slate-11">
      {{ $t('INBOX_MGMT.WHATSAPP_HYBRID.CONNECT_ORDER.TITLE') }}
    </p>
    <ol data-connect-order class="flex flex-col gap-3 p-0 m-0 list-none">
      <li
        v-for="(step, index) in STEPS"
        :key="step"
        class="flex items-center gap-3 text-base text-n-slate-12"
      >
        <span
          class="grid text-sm font-semibold rounded-full size-7 shrink-0 place-items-center bg-n-blue-3 text-n-blue-11"
          aria-hidden="true"
        >
          {{ index + 1 }}
        </span>
        <!-- eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys -->
        {{ $t(`INBOX_MGMT.WHATSAPP_HYBRID.CONNECT_ORDER.${step}`) }}
      </li>
    </ol>
    <Button
      data-connect
      :is-loading="isBusy"
      icon="i-lucide-qr-code"
      size="lg"
      class="w-full !min-h-12 !rounded-xl sm:w-auto"
      :label="$t('INBOX_MGMT.WHATSAPP_HYBRID.CONNECT')"
      @click="emit('connect')"
    />
  </div>
</template>
