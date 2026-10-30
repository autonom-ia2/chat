<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// Arquivar um card (#2095, passo 1 do protótipo; texto da decisão 6): "Arquivar o card de {nome}?". A janela diz o
// que para (os retornos marcados, que não voltam sozinhos ao restaurar) e o que continua (a reunião marcada e, no
// card ganho, a venda nos Números). O slot `depois` deixa outra parte acrescentar uma opção (ex.: Excluir de vez).
const props = defineProps({
  nome: { type: String, required: true },
  retornos: { type: Number, default: 0 },
  avisoDeReuniao: { type: String, default: '' },
  // O valor da venda que continua contando (card ganho de funil de venda), já formatado.
  vendaQueContinua: { type: String, default: '' },
  ocupado: { type: Boolean, default: false },
  erro: { type: String, default: '' },
});
const emit = defineEmits(['confirmar', 'close']);

const { t } = useI18n();
const dialogo = ref(null);

const avisoDeRetornos = computed(() =>
  props.retornos
    ? t(
        'CRM_ARQUIVADOS.ARQUIVAR.RETORNOS',
        { count: props.retornos },
        props.retornos
      )
    : ''
);

defineExpose({
  open: () => dialogo.value?.open(),
  close: () => dialogo.value?.close(),
});
</script>

<template>
  <Dialog
    ref="dialogo"
    data-arquivar-card
    type="alert"
    :title="t('CRM_ARQUIVADOS.ARQUIVAR.TITULO', { nome })"
    :description="t('CRM_ARQUIVADOS.ARQUIVAR.TEXTO')"
    width="md"
    @close="emit('close')"
  >
    <div class="flex flex-col gap-3 empty:hidden">
      <p
        v-if="vendaQueContinua"
        data-arquivar-venda
        class="mb-0 flex items-start gap-2 rounded-xl bg-n-teal-2 px-3 py-2 text-sm text-n-teal-11"
      >
        <span
          class="i-lucide-check mt-0.5 size-4 shrink-0"
          aria-hidden="true"
        />
        {{ t('CRM_ARQUIVADOS.ARQUIVAR.VENDA', { valor: vendaQueContinua }) }}
      </p>
      <p
        v-if="avisoDeRetornos"
        data-arquivar-retornos
        class="mb-0 flex items-start gap-2 rounded-xl bg-n-amber-2 px-3 py-2 text-sm text-n-amber-11"
      >
        <span
          class="i-lucide-clock mt-0.5 size-4 shrink-0"
          aria-hidden="true"
        />
        {{ avisoDeRetornos }}
      </p>
      <p
        v-if="avisoDeReuniao"
        data-aviso-reuniao
        class="mb-0 flex items-start gap-2 rounded-xl bg-n-blue-2 px-3 py-2 text-sm text-n-blue-11"
      >
        <span
          class="i-lucide-calendar mt-0.5 size-4 shrink-0"
          aria-hidden="true"
        />
        {{ avisoDeReuniao }}
      </p>
      <slot name="depois" />
      <p
        v-if="erro"
        role="alert"
        data-arquivar-erro
        class="mb-0 rounded-lg bg-n-ruby-2 px-3 py-2 text-sm text-n-ruby-11"
      >
        {{ erro }}
      </p>
    </div>
    <template #footer>
      <div class="flex flex-wrap justify-end gap-2">
        <Button
          type="button"
          :label="t('CRM_ARQUIVADOS.CANCELAR')"
          slate
          faded
          class="!min-h-11"
          :disabled="ocupado"
          @click="dialogo?.close()"
        />
        <Button
          type="button"
          data-arquivar-confirmar
          :label="t('CRM_ARQUIVADOS.ARQUIVAR.BOTAO')"
          icon="i-lucide-archive"
          ruby
          class="!min-h-11"
          :is-loading="ocupado"
          :disabled="ocupado"
          @click="emit('confirmar')"
        />
      </div>
    </template>
  </Dialog>
</template>
