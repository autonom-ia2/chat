<script setup>
// Aviso no topo de Configurações › Etiquetas (#1823, F1b): de onde vêm as etiquetas
// do WhatsApp do celular e o que acontece quando são renomeadas ou apagadas lá
// (decisão B do Rodrigo: a etiqueta daqui mantém o nome). Só com a flag
// `etiquetas_do_celular`.
import { useNomeDaEtiqueta } from 'dashboard/composables/useNomeDaEtiqueta';

const { celularLigado } = useNomeDaEtiqueta();
</script>

<template>
  <div
    v-if="celularLigado"
    class="flex items-start gap-2 px-3 py-2 mb-4 text-sm border rounded-xl bg-n-teal-3 border-n-teal-4 text-n-teal-11"
  >
    <span class="i-ri-whatsapp-line size-4 mt-0.5 flex-shrink-0" />
    <div class="flex flex-col gap-1">
      <p class="mb-0">{{ $t('LABEL_MGMT.WHATSAPP.NOTICE') }}</p>
      <p class="mb-0">{{ $t('LABEL_MGMT.WHATSAPP.RENAMED_OR_DELETED') }}</p>
    </div>
  </div>
  <template v-else />
</template>
