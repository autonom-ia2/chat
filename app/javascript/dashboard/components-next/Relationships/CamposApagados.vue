<script setup>
// #3082 — os campos apagados que a conta guardou escondidos. O que foi escrito
// neles continua nas pessoas e empresas; "Trazer de volta" abre o formulário
// já preenchido, e salvar cria o campo de novo com a mesma chave.
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

defineProps({
  campos: { type: Array, default: () => [] },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['trazer']);
const { t } = useI18n();
</script>

<template>
  <section
    v-if="campos.length"
    data-campos-apagados
    class="flex flex-col gap-3 border-t border-n-weak pt-4"
  >
    <div class="flex flex-col gap-1">
      <h4 class="text-sm font-medium text-n-slate-12">
        {{ t('RELATIONSHIPS.DELETED.TITLE') }}
      </h4>
      <p class="text-xs leading-relaxed text-n-slate-11">
        {{ t('RELATIONSHIPS.DELETED.HELP') }}
      </p>
    </div>
    <div
      v-for="campo in campos"
      :key="`${campo.attribute_model}:${campo.attribute_key}`"
      class="flex items-center gap-3 rounded-lg border border-dashed border-n-weak p-3"
    >
      <Icon icon="i-lucide-archive" class="size-4 shrink-0 text-n-slate-10" />
      <p class="min-w-0 flex-1 break-words text-sm text-n-slate-11">
        {{ campo.attribute_display_name || campo.attribute_key }}
      </p>
      <!-- Alvo de toque de 44 px sem aumentar o desenho. -->
      <Button
        type="button"
        xs
        faded
        slate
        icon="i-lucide-undo-2"
        class="relative before:absolute before:inset-x-0 before:-inset-y-2.5 before:content-['']"
        :disabled="disabled"
        :label="t('RELATIONSHIPS.DELETED.BRING_BACK')"
        @click="emit('trazer', campo)"
      />
    </div>
  </section>
</template>
