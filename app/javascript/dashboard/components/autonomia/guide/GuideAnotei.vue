<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AutonomiaGuideAPI from 'dashboard/api/autonomiaGuide';
import Button from 'dashboard/components-next/button/Button.vue';

// #933 — o que o Guia anotou neste turno, logo abaixo da resposta: "Anotei: …"
// com "Esquecer". Esquecer apaga na hora; o chip some quando o servidor confirma.
const props = defineProps({
  lembranca: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['esqueceu']);

const { t } = useI18n();
const esquecendo = ref(false);

const esquecer = async () => {
  if (esquecendo.value) return;
  esquecendo.value = true;
  try {
    await AutonomiaGuideAPI.apagarMemoria(props.lembranca.id);
    emit('esqueceu', props.lembranca.id);
  } catch {
    useAlert(t('AUTONOMIA_GUIDE.MEMORY.DELETE_FAILED'));
  } finally {
    esquecendo.value = false;
  }
};
</script>

<template>
  <div class="flex flex-wrap items-center gap-x-2" data-anotei>
    <span
      class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-n-iris-3 text-n-iris-11 text-xs max-w-full break-words"
    >
      <span class="i-lucide-sparkles size-3 shrink-0" aria-hidden="true" />
      {{ $t('AUTONOMIA_GUIDE.MEMORY.NOTED', { texto: lembranca.texto }) }}
    </span>
    <Button
      :label="$t('AUTONOMIA_GUIDE.MEMORY.FORGET')"
      :aria-label="
        $t('AUTONOMIA_GUIDE.MEMORY.FORGET_NAMED', { texto: lembranca.texto })
      "
      :is-loading="esquecendo"
      link
      slate
      class="min-h-11"
      @click="esquecer"
    />
  </div>
</template>
