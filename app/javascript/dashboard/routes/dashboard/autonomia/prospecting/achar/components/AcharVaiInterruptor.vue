<script setup>
import AudienceListSwitch from 'dashboard/components-next/CampaignJourney/AudienceListSwitch.vue';

// #2692 — o interruptor "Vai / Não vai" do cartão da empresa. Envolve o mesmo
// interruptor da busca por conversa de Campanhas (44 px, role=switch) e põe o
// texto visível ao lado, que também alterna. Importar de CampaignJourney/ é
// dívida registrada na v4: o interruptor deve ir para components-next comum
// num PR avisado à sessão de Campanhas.
defineProps({
  vai: { type: Boolean, default: true },
  nome: { type: String, required: true },
});
const emit = defineEmits(['alternar']);
</script>

<template>
  <div class="flex items-center shrink-0" data-vai-interruptor>
    <button
      type="button"
      tabindex="-1"
      aria-hidden="true"
      class="hidden px-1 text-sm font-semibold md:block min-h-11"
      :class="vai ? 'text-n-blue-11' : 'text-n-slate-11'"
      @click="emit('alternar')"
    >
      {{
        vai
          ? $t('PROSPECTING_ACHAR.CONFIRA.VAI')
          : $t('PROSPECTING_ACHAR.CONFIRA.NAO_VAI')
      }}
    </button>
    <AudienceListSwitch
      :on="vai"
      :label="$t('PROSPECTING_ACHAR.CONFIRA.LEVAR', { nome })"
      @toggle="emit('alternar')"
    />
  </div>
</template>
