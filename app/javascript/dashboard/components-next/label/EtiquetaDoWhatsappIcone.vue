<script setup>
// Ícone pequeno do WhatsApp no chip da etiqueta que existe no celular (#1823, F1b).
// Sem a flag `etiquetas_do_celular`, ou etiqueta só daqui: não renderiza nada.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useNomeDaEtiqueta } from 'dashboard/composables/useNomeDaEtiqueta';

const props = defineProps({
  titulo: { type: String, default: '' },
  pequeno: { type: Boolean, default: false },
});

const { t } = useI18n();
const { vinculosDe } = useNomeDaEtiqueta();

const caixas = computed(() =>
  [...new Set(vinculosDe(props.titulo).map(({ caixa }) => caixa))].join(', ')
);
const dica = computed(() =>
  caixas.value
    ? t('LABEL_MGMT.WHATSAPP.CHIP_TOOLTIP', { caixa: caixas.value })
    : ''
);
</script>

<template>
  <span
    v-if="dica"
    v-tooltip.top="dica"
    :aria-label="dica"
    role="img"
    class="i-ri-whatsapp-line flex-shrink-0 text-n-teal-10"
    :class="pequeno ? 'size-3' : 'size-3.5'"
  />
  <template v-else />
</template>
