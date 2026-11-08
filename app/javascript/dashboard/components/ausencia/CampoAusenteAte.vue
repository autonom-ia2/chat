<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { paraCampo, paraEnvio } from './ausencia';

// #2414 G23 (#2737) — "Ausente até": férias, licença. Usado na edição da pessoa (Equipe) e no perfil. Passada a data, a
// pessoa volta a contar como presente sozinha. A Automação livre lê "responsável está ausente".
const props = defineProps({
  // ISO da API, ou null.
  modelValue: { type: String, default: null },
});

const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();

const valor = computed(() => paraCampo(props.modelValue));
// Data pela metade chega vazia do navegador: não apaga a ausência. Só o botão "Não está ausente" limpa.
const mudar = novo => {
  if (novo) emit('update:modelValue', paraEnvio(novo));
};
const limpar = () => emit('update:modelValue', null);
</script>

<template>
  <div class="flex flex-col gap-1.5" data-campo-ausente-ate>
    <Input
      data-ausente-ate
      type="datetime-local"
      :model-value="valor"
      :label="t('AUSENCIA.CAMPO.LABEL')"
      :message="t('AUSENCIA.CAMPO.DICA')"
      wrap-message
      @update:model-value="mudar"
    />
    <Button
      v-if="valor"
      data-ausente-limpar
      ghost
      slate
      sm
      type="button"
      icon="i-lucide-x"
      class="w-fit"
      :label="t('AUSENCIA.CAMPO.LIMPAR')"
      @click="limpar"
    />
  </div>
</template>
