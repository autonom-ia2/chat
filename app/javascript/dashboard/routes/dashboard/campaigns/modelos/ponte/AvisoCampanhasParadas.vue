<script setup>
import { computed, ref, watch } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import api from '../api/modelosWhatsapp';
import CampanhasParadas from '../components/CampanhasParadas.vue';

// Na lista de campanhas: as que pararam por causa do modelo, com o motivo e o
// caminho para resolver. Só com a flag whatsapp_templates_journey (a conta pode
// chegar depois da tela, por isso observa a flag).
const accountId = useMapGetter('getCurrentAccountId');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);
const ativa = computed(() =>
  isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.WHATSAPP_TEMPLATES_JOURNEY
  )
);
const campanhas = ref([]);

watch(
  ativa,
  async ligada => {
    if (!ligada) {
      campanhas.value = [];
      return;
    }
    try {
      campanhas.value = await api.listarCampanhasParadas();
    } catch {
      campanhas.value = [];
    }
  },
  { immediate: true }
);
</script>

<template>
  <CampanhasParadas v-if="campanhas.length" :campanhas="campanhas" />
</template>
