<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { guardarArquivo } from '../../api/arquivos';

// Botão "Escolher arquivo": guarda o arquivo até o envio (api/arquivos.js) e
// devolve { arquivo: nome, local: chave }. O arquivo sobe para a Meta no
// "Enviar para aprovação". Tipo e tamanho são conferidos já aqui, com os mesmos
// limites do servidor: arquivo errado nem entra, e o motivo fica embaixo.
defineProps({
  nome: { type: String, default: '' },
  aceita: { type: String, default: '' },
  rotulo: { type: String, default: '' },
});

const emit = defineEmits(['escolhido']);
const { t } = useI18n();
const seletor = ref(null);
const erro = ref('');

const MB = 1024 * 1024;
const LIMITES = {
  'image/jpeg': { maximo: 5 * MB, tipo: 'foto' },
  'image/png': { maximo: 5 * MB, tipo: 'foto' },
  'video/mp4': { maximo: 16 * MB, tipo: 'video' },
  'application/pdf': { maximo: 100 * MB, tipo: 'documento' },
};

const problemaDo = (arquivo, aceita) => {
  const tipos = aceita.split(',');
  const limite = LIMITES[arquivo.type];
  const tipoAceito = LIMITES[tipos[0]]?.tipo || 'foto';
  if (!tipos.includes(arquivo.type) || !limite) {
    return t(`MODELOS_WHATSAPP.EXTRAS.ARQUIVO_ERRADO.${tipoAceito}`);
  }
  if (arquivo.size > limite.maximo) {
    return t(`MODELOS_WHATSAPP.EXTRAS.ARQUIVO_GRANDE.${limite.tipo}`);
  }
  return '';
};

const aoEscolher = (evento, aceita) => {
  const arquivo = evento.target.files?.[0];
  if (!arquivo) return;
  erro.value = problemaDo(arquivo, aceita);
  if (!erro.value) {
    emit('escolhido', {
      arquivo: arquivo.name,
      local: guardarArquivo(arquivo),
    });
  }
  // eslint-disable-next-line no-param-reassign
  evento.target.value = '';
};
</script>

<template>
  <span class="inline-flex flex-col max-w-full gap-1">
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
      @change="evento => aoEscolher(evento, aceita)"
    />
    <span
      v-if="erro"
      data-arquivo-erro
      role="alert"
      class="text-sm text-n-ruby-11"
    >
      {{ erro }}
    </span>
  </span>
</template>
