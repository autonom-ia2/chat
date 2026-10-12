<script setup>
import { computed, nextTick, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFlow } from '../composables/useBookingFlow';
import ActionButton from './ActionButton.vue';
import BrandHeader from './BrandHeader.vue';
import ContactRequestForm from './ContactRequestForm.vue';
import WhatsAppButton from './WhatsAppButton.vue';

// "Nenhum horário serve?" (J2-A10): nome e WhatsApp viram pedido de contato no card, em vez de lead perdido. Pelo
// link do cliente não pede de novo o que o convite já sabe (o servidor usa o contato do convite). Pedido enviado: o
// foco vai para o título novo, e o leitor de tela anuncia que deu certo.
const { page, invite, askPhone, isContactRequested, goBack } = useFlow();
const { t } = useI18n();

const agentName = computed(() => page.value.agent_name || '');
const body = computed(() => {
  const suffix = invite.isInvite.value && !askPhone.value ? '_INVITE' : '';
  return agentName.value
    ? t(`BOOKING_V2.NO_SLOT.BODY${suffix}`, { name: agentName.value })
    : t(`BOOKING_V2.NO_SLOT.BODY_NO_NAME${suffix}`);
});

watch(isContactRequested, isDone => {
  if (!isDone) return;
  nextTick(() => document.querySelector('[data-step-heading]')?.focus());
});
</script>

<template>
  <section class="flex flex-col gap-6" aria-labelledby="step-heading">
    <BrandHeader :page="page" />
    <template v-if="isContactRequested">
      <h1
        id="step-heading"
        data-step-heading
        tabindex="-1"
        class="text-2xl font-bold text-bk-strong focus:outline-none"
      >
        {{ t('BOOKING_V2.NO_SLOT.DONE_TITLE') }}
      </h1>
      <p class="text-base text-bk-body">
        {{ t('BOOKING_V2.NO_SLOT.DONE_BODY') }}
      </p>
      <WhatsAppButton :url="page.contact_whatsapp_url" />
    </template>
    <template v-else>
      <h1
        id="step-heading"
        data-step-heading
        tabindex="-1"
        class="text-2xl font-bold text-bk-strong focus:outline-none"
      >
        {{ t('BOOKING_V2.NO_SLOT.TITLE') }}
      </h1>
      <p class="text-base text-bk-body">{{ body }}</p>
      <ContactRequestForm />
      <ActionButton variant="ghost" @click="goBack">
        {{ t('BOOKING_V2.BACK') }}
      </ActionButton>
    </template>
  </section>
</template>
