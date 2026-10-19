<script setup>
import FileUpload from 'vue-upload-component';
import { ALLOWED_FILE_TYPES } from 'shared/constants/messages';
import AttachmentPreviews from 'dashboard/components-next/NewConversation/components/AttachmentPreviews.vue';
import { useAnexarNaNovaConversa } from './useAnexarNaNovaConversa';

// #1459 — "Anexar arquivo", onde já existia (e-mail e site): um botão neutro
// abaixo do campo e a lista do que foi anexado. O envio do arquivo é o mesmo
// da tela antiga (useFileUpload). No e-mail novo (#1809) o "+" da barra o substitui.
const TAMANHO_MAXIMO = 4096 * 4096;

const anexos = defineModel({ type: Array, default: () => [] });

const { onFileUpload } = useAnexarNaNovaConversa(anexos);
</script>

<template>
  <div class="flex flex-col items-start gap-2">
    <FileUpload
      input-id="novaConversaAnexo"
      :size="TAMANHO_MAXIMO"
      :accept="ALLOWED_FILE_TYPES"
      multiple
      :drop-directory="false"
      :data="{
        direct_upload_url: '/rails/active_storage/direct_uploads',
        direct_upload: true,
      }"
      class="rounded-xl has-[:focus-visible]:outline has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-offset-2 has-[:focus-visible]:outline-n-brand [&_label]:cursor-pointer"
      @input-file="onFileUpload"
    >
      <span
        class="inline-flex min-h-11 items-center gap-2 rounded-xl bg-n-alpha-2 px-4 text-sm font-medium text-n-slate-12 transition hover:bg-n-alpha-3"
      >
        <span class="i-lucide-paperclip size-4" aria-hidden="true" />
        {{ $t('NOVA_CONVERSA.MENSAGEM.ANEXAR') }}
      </span>
    </FileUpload>
    <AttachmentPreviews
      v-if="anexos.length"
      v-model:attachments="anexos"
      class="!p-0"
    />
  </div>
</template>
