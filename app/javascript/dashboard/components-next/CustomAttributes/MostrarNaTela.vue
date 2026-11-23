<script setup>
import { useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Switch from 'dashboard/components-next/switch/Switch.vue';

// #2435: ligado (o padrão), o campo aparece no card, no contato, na empresa e
// na conversa. Desligado, ele some dessas telas e continua guardado, nos
// filtros, na automação e nas IAs. A linha inteira é o alvo do toque.
// #3082 — `titulo` e `ajuda` trocam o nome e a explicação no configurador da
// ficha ("Mostrar nas telas"); sem eles, vale o texto de Configurações.
defineProps({
  disabled: { type: Boolean, default: false },
  titulo: { type: String, default: '' },
  ajuda: { type: String, default: '' },
});

const mostrar = defineModel({ type: Boolean, default: true });

const { t } = useI18n();
const id = useId();
</script>

<template>
  <label
    :for="id"
    class="flex items-start gap-3 py-2 min-h-11"
    :class="disabled ? 'cursor-not-allowed opacity-60' : 'cursor-pointer'"
  >
    <Switch
      :id="id"
      v-model="mostrar"
      :disabled="disabled"
      :aria-labelledby="`${id}-titulo`"
      :aria-describedby="`${id}-ajuda`"
      class="mt-1"
    />
    <span class="flex flex-col min-w-0">
      <span :id="`${id}-titulo`" class="text-sm font-medium text-n-slate-12">
        {{ titulo || t('ATTRIBUTES_MGMT.MOSTRAR_NA_TELA.TITULO') }}
      </span>
      <span
        :id="`${id}-ajuda`"
        class="mt-1 text-xs leading-relaxed text-n-slate-11"
      >
        {{ ajuda || t('ATTRIBUTES_MGMT.MOSTRAR_NA_TELA.AJUDA') }}
      </span>
    </span>
  </label>
</template>
