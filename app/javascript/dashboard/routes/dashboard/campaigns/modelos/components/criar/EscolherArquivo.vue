<script setup>
import { ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { guardarArquivo } from '../../api/arquivos';

// Botão "Escolher arquivo": guarda o arquivo até o envio (api/arquivos.js) e
// devolve { arquivo: nome, local: chave }. O arquivo sobe para a Meta no
// "Enviar para aprovação"; o tipo e o tamanho são conferidos no servidor.
defineProps({
  nome: { type: String, default: '' },
  aceita: { type: String, default: '' },
  rotulo: { type: String, default: '' },
});

const emit = defineEmits(['escolhido']);
const seletor = ref(null);

const aoEscolher = evento => {
  const arquivo = evento.target.files?.[0];
  if (!arquivo) return;
  emit('escolhido', { arquivo: arquivo.name, local: guardarArquivo(arquivo) });
  // eslint-disable-next-line no-param-reassign
  evento.target.value = '';
};
</script>

<template>
  <span class="inline-flex max-w-full">
    <Button
      data-escolher-arquivo
      :label="
        rotulo ||
        (nome
          ? $t('MODELOS_WHATSAPP.EXTRAS.TROCAR_ARQUIVO')
          : $t('MODELOS_WHATSAPP.EXTRAS.ESCOLHER_ARQUIVO'))
      "
      icon="i-lucide-upload"
      color="slate"
      variant="faded"
      size="sm"
      class="max-w-full min-h-11"
      @click="seletor?.click()"
    />
    <input
      ref="seletor"
      type="file"
      class="hidden"
      :accept="aceita"
      @change="aoEscolher"
    />
  </span>
</template>
