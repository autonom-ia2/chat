<script setup>
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';

// chat#1067 — o aceite do risco antes de qualquer envio pelo WhatsApp API, no cartão de confirmação das telas novas
// (o marcado ganha a borda azul).
defineProps({
  accepted: { type: Boolean, default: false },
  isBusy: { type: Boolean, default: false },
});

const emit = defineEmits(['change']);
</script>

<template>
  <section
    data-hybrid-risk
    class="flex flex-col gap-3 p-5 sm:p-6 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
  >
    <h2 class="m-0 text-lg font-semibold text-n-slate-12">
      {{ $t('INBOX_MGMT.WHATSAPP_HYBRID.RISK.TITLE') }}
    </h2>
    <label
      class="flex items-start gap-3 p-4 border cursor-pointer rounded-xl min-h-11 has-[:focus-visible]:outline has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-offset-2 has-[:focus-visible]:outline-n-brand"
      :class="accepted ? 'border-n-brand bg-n-blue-2' : 'border-n-weak'"
    >
      <Checkbox
        class="flex-none mt-1"
        :model-value="accepted"
        :disabled="isBusy"
        @update:model-value="value => emit('change', value)"
      />
      <span class="text-sm text-n-slate-12">
        {{ $t('INBOX_MGMT.WHATSAPP_HYBRID.RISK.TEXT') }}
      </span>
    </label>
  </section>
</template>
