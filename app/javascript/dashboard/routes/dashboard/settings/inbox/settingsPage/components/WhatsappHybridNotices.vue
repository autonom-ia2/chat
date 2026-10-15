<script setup>
// chat#1487 — avisos de saúde do número na aba WhatsApp API. Só avisam: nada é bloqueado.
// O motor não informa quando o app foi aberto no celular, então o lembrete dos 14 dias é fixo e discreto.
defineProps({
  sameNumberInboxes: { type: Array, default: () => [] },
  showAppReminder: { type: Boolean, default: false },
});
</script>

<template>
  <section
    v-for="name in sameNumberInboxes"
    :key="name"
    data-test="same-number"
    role="status"
    class="flex items-start gap-3 p-4 text-sm leading-relaxed rounded-2xl ring-1 ring-inset bg-n-amber-2 ring-n-amber-6 text-n-slate-12"
  >
    <span
      class="i-lucide-triangle-alert size-5 mt-0.5 shrink-0 text-n-amber-11"
      aria-hidden="true"
    />
    <span>
      {{
        $t('INBOX_MGMT.WHATSAPP_HYBRID.NOTICES.SAME_NUMBER', { inbox: name })
      }}
    </span>
  </section>
  <p
    v-if="showAppReminder"
    data-test="app-reminder"
    class="flex items-start gap-2 px-1 mb-0 text-sm text-n-slate-11"
  >
    <span
      class="i-lucide-smartphone size-4 mt-0.5 shrink-0"
      aria-hidden="true"
    />
    <span>{{
      $t('INBOX_MGMT.WHATSAPP_HYBRID.NOTICES.APP_EVERY_14_DAYS')
    }}</span>
  </p>
</template>
