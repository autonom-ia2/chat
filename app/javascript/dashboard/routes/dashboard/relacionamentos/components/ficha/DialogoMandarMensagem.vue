<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { contaDaMensagem } from '../../lista/quemFicaDeFora';
import DialogoDaFicha from './DialogoDaFicha.vue';

// #2894 — "Mandar mensagem" da empresa: diz quem recebe e quem fica de fora
// (a conta é a da lista, `contaDaMensagem`) e só então deixa continuar. Quem
// escreve a mensagem é o passo seguinte, que no protótipo só avisa.
const props = defineProps({
  empresa: { type: Object, required: true },
  pessoas: { type: Array, required: true },
});
const emit = defineEmits(['continuar']);

const { t } = useI18n();
const dialogo = ref(null);
const conta = computed(() => contaDaMensagem(props.pessoas));
const ra = (chave, valores, quantos) =>
  t(`RELACIONAMENTOS_FICHA.EMPRESA.MENSAGEM.${chave}`, valores, quantos);

defineExpose({
  open: () => dialogo.value?.open(),
  close: () => dialogo.value?.close(),
});
</script>

<template>
  <DialogoDaFicha
    ref="dialogo"
    :titulo="ra('TITULO', { nome: empresa.name })"
    :confirmar="ra('CONTINUAR')"
    :cancelar="t('RELACIONAMENTOS.COMUM.CANCELAR')"
    marca-confirmar="mandar-mensagem-continuar"
    @confirm="emit('continuar')"
  >
    <div
      data-relacionamentos="quem-recebe"
      class="flex flex-col gap-1 text-sm text-n-slate-11"
    >
      <p class="m-0 text-base font-medium text-n-slate-12">
        {{ ra('RECEBEM', { n: conta.recebem }, conta.recebem) }}
      </p>
      <p v-if="conta.fora" data-relacionamentos="quem-fica-de-fora" class="m-0">
        {{ ra('FORA', { n: conta.fora }, conta.fora) }}
      </p>
      <p class="m-0">{{ ra('PROXIMO') }}</p>
    </div>
  </DialogoDaFicha>
</template>
