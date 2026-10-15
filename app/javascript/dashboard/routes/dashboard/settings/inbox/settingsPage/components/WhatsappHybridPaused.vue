<script setup>
import Button from 'dashboard/components-next/button/Button.vue';

// chat#1487 — WhatsApp API pausado: uma ação só, retomar.
defineProps({
  isBusy: { type: Boolean, default: false },
});

const emit = defineEmits(['resume']);
</script>

<template>
  <div class="flex flex-col items-start gap-3">
    <span
      class="i-lucide-circle-pause size-8 text-n-slate-10"
      aria-hidden="true"
    />
    <h2 class="m-0 text-lg font-semibold text-n-slate-12">
      {{ $t('INBOX_MGMT.WHATSAPP_HYBRID.PAUSE.PAUSED_TITLE') }}
    </h2>
    <p class="mb-0 text-base leading-relaxed text-n-slate-12">
      {{ $t('INBOX_MGMT.WHATSAPP_HYBRID.PAUSE.PAUSED_HELP') }}
    </p>
    <Button
      data-resume
      :is-loading="isBusy"
      icon="i-lucide-play"
      size="lg"
      class="w-full mt-1 !min-h-12 !rounded-xl sm:w-auto"
      :label="$t('INBOX_MGMT.WHATSAPP_HYBRID.PAUSE.RESUME')"
      @click="emit('resume')"
    />
  </div>
</template>
