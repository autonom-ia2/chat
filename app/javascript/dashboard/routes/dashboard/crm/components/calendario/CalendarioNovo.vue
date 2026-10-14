<script setup>
// Calendário Ouro — "Novo": o que marcar, em cartões grandes, uma frase cada.
// Lembrete sempre; reunião só com as reuniões ligadas; mensagem marcada só com
// uma caixa de WhatsApp conectada. Cada cartão abre o fluxo que já existe.
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

defineProps({
  opcoes: { type: Array, required: true },
});
const emit = defineEmits(['escolher']);
const { t } = useI18n();
const N = 'CRM_CALENDARIO.NOVO';

const OPCAO = {
  lembrete: {
    chave: 'LEMBRETE',
    icone: 'i-lucide-bell',
    tom: 'bg-n-teal-3 text-n-teal-11',
  },
  reuniao: {
    chave: 'REUNIAO',
    icone: 'i-lucide-video',
    tom: 'bg-n-iris-3 text-n-iris-11',
  },
  mensagem: {
    chave: 'MENSAGEM',
    icone: 'i-lucide-send',
    tom: 'bg-n-blue-3 text-n-blue-11',
  },
};

const dialogo = ref(null);
const escolher = opcao => {
  dialogo.value?.close();
  emit('escolher', opcao);
};
defineExpose({ open: () => dialogo.value?.open() });
</script>

<template>
  <Dialog
    ref="dialogo"
    :title="t(`${N}.TITULO`)"
    :description="t(`${N}.TEXTO`)"
    :show-confirm-button="false"
    width="md"
  >
    <div data-calendario-escolha class="flex flex-col gap-2">
      <button
        v-for="opcao in opcoes"
        :key="opcao"
        type="button"
        :data-escolha="opcao"
        class="flex min-h-16 w-full items-center gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-4 text-start shadow-sm transition hover:border-n-blue-8 hover:shadow-md focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="escolher(opcao)"
      >
        <span
          class="grid size-11 shrink-0 place-items-center rounded-xl"
          :class="OPCAO[opcao].tom"
          aria-hidden="true"
        >
          <span class="size-5" :class="OPCAO[opcao].icone" />
        </span>
        <span class="min-w-0 flex-1">
          <span class="block text-base font-semibold text-n-slate-12">
            {{ t(`${N}.${OPCAO[opcao].chave}`) }}
          </span>
          <span class="block text-sm text-n-slate-11">
            {{ t(`${N}.${OPCAO[opcao].chave}_TEXTO`) }}
          </span>
        </span>
        <span
          class="i-lucide-chevron-right size-5 shrink-0 text-n-slate-9 rtl:rotate-180"
          aria-hidden="true"
        />
      </button>
    </div>
    <template #footer>
      <button
        type="button"
        data-escolha-cancelar
        class="min-h-11 w-full rounded-xl bg-n-alpha-2 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-3"
        @click="dialogo?.close()"
      >
        {{ t(`${N}.CANCELAR`) }}
      </button>
    </template>
  </Dialog>
</template>
