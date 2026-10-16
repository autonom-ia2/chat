<script setup>
// #1702: a mensagem respondida, dentro do balão, como no WhatsApp: faixa colorida à
// esquerda, o nome de quem escreveu na mesma cor, o texto em até três linhas e a
// miniatura da foto à direita. Verde para a empresa, roxo para o cliente. A prévia
// pode trazer link: ele não abre daqui, o toque na citação leva à mensagem.
import { computed } from 'vue';
import { MESSAGE_TYPES } from '../message/constants';

const props = defineProps({
  mensagem: { type: Object, required: true },
  previa: { type: String, default: '' },
});
const emit = defineEmits(['ir']);

const doCliente = computed(
  () => props.mensagem.messageType === MESSAGE_TYPES.INCOMING
);
// Sem nome (sistema, robô sem cadastro), a citação fica só com o texto.
const nome = computed(() => props.mensagem.sender?.name || '');
const foto = computed(() => {
  const anexo = props.mensagem.attachments?.[0];
  const tipo = anexo?.fileType ?? anexo?.file_type;
  if (tipo !== 'image') return '';
  return anexo.thumbUrl ?? anexo.thumb_url ?? anexo.dataUrl ?? anexo.data_url;
});
</script>

<template>
  <div
    role="button"
    tabindex="0"
    class="flex w-full min-w-0 mb-1 overflow-hidden text-start rounded-[7.5px] border-s-4 bg-[#000]/[0.05] dark:bg-[#000]/20 cursor-pointer"
    :class="
      doCliente
        ? 'border-s-[#5E44D8] dark:border-s-[#B3A1FF]'
        : 'border-s-[#1A6B42] dark:border-s-[#6FD07E]'
    "
    @click="emit('ir')"
    @keydown.enter.prevent="emit('ir')"
    @keydown.space.prevent="emit('ir')"
  >
    <span class="flex-1 min-w-0 px-2 py-1.5">
      <span
        v-if="nome"
        class="block text-[12.8px] leading-[20px] font-medium truncate"
        :class="
          doCliente
            ? 'text-[#5E44D8] dark:text-[#B3A1FF]'
            : 'text-[#1A6B42] dark:text-[#6FD07E]'
        "
      >
        {{ nome }}
      </span>
      <span
        v-dompurify-html="previa"
        class="block text-[13px] leading-[18px] text-[#666666] dark:text-[#A7A8A8] line-clamp-3 [&_p]:m-0 [&_a]:pointer-events-none"
      />
    </span>
    <img
      v-if="foto"
      :src="foto"
      alt=""
      class="size-[60px] object-cover shrink-0"
    />
  </div>
</template>
