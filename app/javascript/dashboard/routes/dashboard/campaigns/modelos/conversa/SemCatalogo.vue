<script setup>
// Modelo de produto num WhatsApp sem catálogo ligado (#1716): o motivo e os
// três passos para ligar. Quando a Meta disse outra coisa (permissão, catálogo
// sumido), o texto dela, já traduzido pelo servidor.
import { useI18n } from 'vue-i18n';

defineProps({
  motivo: { type: String, default: '' },
});

const { t } = useI18n();
const NS = 'MODELOS_WHATSAPP.CONVERSA.SEM_CATALOGO';
</script>

<template>
  <div class="flex flex-col gap-3" data-sem-catalogo>
    <div
      role="alert"
      class="flex gap-3 p-4 text-sm rounded-xl bg-n-amber-2 text-n-slate-12"
    >
      <span
        class="i-lucide-store size-5 shrink-0 text-n-amber-11"
        aria-hidden="true"
      />
      <span>{{ motivo || t(`${NS}.TEXTO`) }}</span>
    </div>
    <ol
      v-if="!motivo"
      class="flex flex-col gap-1 m-0 text-sm list-decimal ps-5 text-n-slate-12"
    >
      <li>{{ t(`${NS}.PASSO_1`) }}</li>
      <li>{{ t(`${NS}.PASSO_2`) }}</li>
      <li>{{ t(`${NS}.PASSO_3`) }}</li>
    </ol>
  </div>
</template>
