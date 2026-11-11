<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFrasesDaMensagem } from '../../lista/useFrasesDaMensagem';
import DialogoDaFicha from './DialogoDaFicha.vue';

// #2894 — "Mandar mensagem" da empresa: o mesmo que o diálogo da lista (quem
// recebe pelo nome, quem fica de fora com o motivo; mesma regra e mesmas
// frases). O botão do cabeçalho abre sempre este diálogo: se ninguém pode
// receber (ou a empresa não tem pessoas), ele só explica e traz um botão "Entendi". Quem escreve a
// mensagem é o passo seguinte, que no protótipo só avisa.
const props = defineProps({
  pessoas: { type: Array, required: true },
});
const emit = defineEmits(['continuar']);

const { t } = useI18n();
const dialogo = ref(null);
const { conta, frases, alguemRecebe } = useFrasesDaMensagem(
  () => props.pessoas
);

defineExpose({
  open: () => dialogo.value?.open(),
  close: () => dialogo.value?.close(),
});
</script>

<template>
  <DialogoDaFicha
    ref="dialogo"
    :titulo="t('RELACIONAMENTOS.LISTA.MENSAGEM.TITULO')"
    :confirmar="t('RELACIONAMENTOS.COMUM.CONTINUAR')"
    :cancelar="t('RELACIONAMENTOS.COMUM.CANCELAR')"
    :so-entendi="conta.recebem === 0"
    :entendi="t('RELACIONAMENTOS_FICHA.EMPRESA.MENSAGEM.ENTENDI')"
    marca-confirmar="mandar-mensagem-continuar"
    @confirm="emit('continuar')"
  >
    <div class="flex flex-col gap-2">
      <p
        data-relacionamentos="dialogo-mensagem"
        class="m-0 text-base text-n-slate-12"
      >
        {{
          pessoas.length
            ? frases.join(' ')
            : t('RELACIONAMENTOS_FICHA.EMPRESA.MENSAGEM.SEM_PESSOAS')
        }}
      </p>
      <p
        v-if="alguemRecebe"
        data-relacionamentos="dialogo-mensagem-proximo"
        class="m-0 text-sm text-n-slate-11"
      >
        {{ t('RELACIONAMENTOS.LISTA.MENSAGEM.PROXIMO_PASSO') }}
      </p>
    </div>
  </DialogoDaFicha>
</template>
