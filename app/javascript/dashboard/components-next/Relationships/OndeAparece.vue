<script setup>
// "Onde aparece" do formulário de campo (FieldConfigurator): uma chave por área
// da tela. Saiu do configurador no #3082, sem mudar o desenho.
import { useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Switch from 'dashboard/components-next/switch/Switch.vue';

defineProps({
  surfaces: { type: Array, default: () => [] },
  displayOn: { type: Array, default: () => [] },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['toggle']);
const { t } = useI18n();
const inputId = useId();
</script>

<template>
  <section class="flex flex-col gap-3 border-t border-n-weak pt-4">
    <h4 class="text-sm font-medium text-n-slate-12">
      {{ t('RELATIONSHIPS.DISPLAY_TITLE') }}
    </h4>
    <div
      v-for="surfaceName in surfaces"
      :key="surfaceName"
      class="flex items-start gap-3 py-1"
    >
      <Switch
        :model-value="displayOn.includes(surfaceName)"
        :disabled="disabled"
        :aria-label="t(`RELATIONSHIPS.SURFACES.${surfaceName}`)"
        :aria-describedby="`${inputId}-${surfaceName}-help`"
        class="mt-1"
        @update:model-value="value => emit('toggle', surfaceName, value)"
      />
      <div class="min-w-0">
        <p class="text-sm font-medium text-n-slate-12">
          {{ t(`RELATIONSHIPS.SURFACES.${surfaceName}`) }}
        </p>
        <p
          :id="`${inputId}-${surfaceName}-help`"
          class="mt-1 text-xs leading-relaxed text-n-slate-11"
        >
          {{ t(`RELATIONSHIPS.SURFACE_HELP.${surfaceName}`) }}
        </p>
      </div>
    </div>
  </section>
</template>
