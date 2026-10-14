<script setup>
import { computed, ref, watch } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import api from '../api/modelosWhatsapp';
import CampanhasParadas from '../components/CampanhasParadas.vue';

// Na lista de campanhas: as que pararam por causa do modelo, com o motivo, o
// caminho para resolver e "Retomar". Só com a flag whatsapp_templates_journey
// (a conta pode chegar depois da tela, por isso observa a flag). Sem permissão
// para ver as pausas, não aparece.
// Retomou: a lista de campanhas em volta também se atualiza.
const emit = defineEmits(['retomada']);
defineOptions({ inheritAttrs: false });

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

const carregar = async () => {
  if (!ativa.value) {
    campanhas.value = [];
    return;
  }
  try {
    campanhas.value = await api.listarCampanhasParadas();
  } catch {
    campanhas.value = [];
  }
};

watch(ativa, carregar, { immediate: true });

const aoRetomar = campanha => {
  carregar();
  emit('retomada', campanha);
};
</script>

<template>
  <!-- Sem campanha parada, o embrulho não ocupa lugar (display: contents); a classe que a
       lista de campanhas passa vai para o aviso. -->
  <div class="contents">
    <CampanhasParadas
      v-if="campanhas.length"
      v-bind="$attrs"
      :campanhas="campanhas"
      @retomada="aoRetomar"
    />
  </div>
</template>
