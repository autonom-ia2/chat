<script setup>
import { ref } from 'vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

// #2472: colar a chave. Um campo, três passos de onde achar e um botão. O
// `<dialog>` nativo do Dialog prende o foco enquanto está aberto.
const emit = defineEmits(['salvar']);

const janela = ref(null);
const chave = ref('');
const erro = ref('');
const conferindo = ref(false);
const mostrarPassos = ref(false);

const abrir = () => {
  chave.value = '';
  erro.value = '';
  mostrarPassos.value = false;
  janela.value?.open();
};

const fechar = () => janela.value?.close();

// Quem chama responde com o resultado da conferência: 'ok', 'recusada' ou
// 'sem_credito'. A chave sai daqui e não fica guardada no componente.
const salvar = async () => {
  if (!chave.value.trim()) return;
  conferindo.value = true;
  const resultado = await new Promise(resolve => {
    emit('salvar', { chave: chave.value.trim(), responder: resolve });
  });
  conferindo.value = false;
  if (resultado === 'ok') {
    chave.value = '';
    fechar();
    return;
  }
  erro.value = resultado === 'sem_credito' ? 'SEM_CREDITO' : 'RECUSADA';
};

defineExpose({ abrir });
</script>

<template>
  <Dialog
    ref="janela"
    :title="$t('IA_DA_CONTA.GAVETA.TITULO')"
    :confirm-button-label="$t('IA_DA_CONTA.GAVETA.SALVAR')"
    :cancel-button-label="$t('IA_DA_CONTA.GAVETA.CANCELAR')"
    :disable-confirm-button="!chave.trim()"
    :is-loading="conferindo"
    width="md"
    @confirm="salvar"
  >
    <form class="flex flex-col gap-4" @submit.prevent="salvar">
      <label class="flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ $t('IA_DA_CONTA.GAVETA.CAMPO') }}
        </span>
        <input
          v-model="chave"
          data-foco
          data-campo-chave
          type="password"
          autocomplete="off"
          spellcheck="false"
          :placeholder="$t('IA_DA_CONTA.GAVETA.EXEMPLO')"
          class="w-full px-4 text-base rounded-xl min-h-12 bg-n-alpha-black2 text-n-slate-12 ring-1 ring-inset ring-n-weak focus:ring-2 focus:ring-n-brand !mb-0"
          :aria-invalid="Boolean(erro)"
          aria-describedby="erro-da-chave"
        />
      </label>
      <p
        v-if="erro"
        id="erro-da-chave"
        data-erro-chave
        role="alert"
        class="mb-0 text-sm text-n-ruby-11"
      >
        {{ $t(`IA_DA_CONTA.GAVETA.${erro}`) }}
      </p>
      <button
        type="button"
        data-onde-pego
        class="inline-flex items-center self-start gap-2 text-sm font-medium min-h-11 text-n-blue-11 hover:underline"
        :aria-expanded="mostrarPassos"
        @click="mostrarPassos = !mostrarPassos"
      >
        <span class="i-lucide-circle-help size-4" aria-hidden="true" />
        {{ $t('IA_DA_CONTA.GAVETA.ONDE') }}
      </button>
      <ol
        v-if="mostrarPassos"
        data-passos
        class="flex flex-col gap-2 p-4 m-0 text-sm list-decimal list-inside rounded-xl bg-n-slate-2 text-n-slate-12"
      >
        <li>{{ $t('IA_DA_CONTA.GAVETA.PASSO_1') }}</li>
        <li>{{ $t('IA_DA_CONTA.GAVETA.PASSO_2') }}</li>
        <li>{{ $t('IA_DA_CONTA.GAVETA.PASSO_3') }}</li>
      </ol>
    </form>
  </Dialog>
</template>
