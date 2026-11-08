<script setup>
// #2717: quem dispara uma campanha de e-mail aberta consente com todo envio futuro. O aviso
// aparece na prontidão e na confirmação do disparo. A jornada ainda não cria a aberta: a escolha
// "Quem recebe" chega com o passo da Automação que põe e tira gente do público (PR-B, #2414).
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
</script>

<template>
  <p
    class="m-0 flex items-start gap-2 rounded-xl bg-n-alpha-1 p-3 text-sm text-n-slate-12"
    data-test="aviso-aberta"
  >
    <span
      class="i-lucide-users size-4 mt-0.5 shrink-0 text-n-slate-11"
      aria-hidden="true"
    />
    {{ t('CAMPAIGN_JOURNEY.NEW_CAMPAIGN.EMAIL.AUDIENCE_MODE_DISPARO') }}
  </p>
</template>
