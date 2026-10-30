<script setup>
import { nextTick, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';

// #2379 — "Mais → Escolher o que aparece": ligar e desligar cada informação e
// mudar a ordem com "Subir" e "Descer" (teclado e toque, sem arrastar). Cada
// mudança vale na hora. Cliente e Próximo passo ficam sempre. Emite a intenção
// (a lista mora em quem chama): dois toques seguidos nunca usam lista velha.
defineProps({
  campos: { type: Array, required: true },
});
const emit = defineEmits(['alternar', 'mover', 'padrao']);

const { t } = useI18n();
const L = 'CRM_LISTA_ACAO.CAMPOS';
const dialogo = useTemplateRef('dialogo');
const lista = useTemplateRef('lista');

const nome = chave => t(`${L}.NOMES.${chave.toUpperCase()}`);

const abrir = () => dialogo.value?.open();
const alternar = chave => emit('alternar', chave);
// O foco segue o botão apertado, que agora está na linha nova do campo.
const mover = async (chave, passo) => {
  emit('mover', chave, passo);
  await nextTick();
  const direcao = passo < 0 ? 'subir' : 'descer';
  const botao = lista.value?.querySelector(
    `[data-campo="${chave}"] [data-${direcao}]`
  );
  if (botao && !botao.disabled) botao.focus();
  else lista.value?.querySelector(`[data-campo="${chave}"] button`)?.focus();
};
const voltarAoPadrao = () => emit('padrao');

defineExpose({ abrir });
</script>

<template>
  <Dialog
    ref="dialogo"
    width="md"
    :title="t(`${L}.TITULO`)"
    :description="t(`${L}.DICA`)"
    :show-cancel-button="false"
    :confirm-button-label="t(`${L}.PRONTO`)"
    @confirm="dialogo?.close()"
  >
    <ul ref="lista" class="-mx-2 mb-0 flex flex-col" data-lista-acao-campos>
      <li
        v-for="(campo, indice) in campos"
        :key="campo.chave"
        :data-campo="campo.chave"
        class="flex items-center gap-1"
      >
        <label
          class="flex min-h-11 flex-1 cursor-pointer items-center gap-3 rounded-xl px-2 text-base text-n-slate-12 hover:bg-n-alpha-2"
        >
          <Checkbox
            :model-value="campo.visivel"
            @update:model-value="alternar(campo.chave)"
          />
          {{ nome(campo.chave) }}
        </label>
        <button
          type="button"
          data-subir
          :disabled="indice === 0"
          :aria-label="t(`${L}.SUBIR`, { nome: nome(campo.chave) })"
          class="grid size-11 place-items-center rounded-xl text-n-slate-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:opacity-40"
          @click="mover(campo.chave, -1)"
        >
          <span class="i-lucide-chevron-up size-5" aria-hidden="true" />
        </button>
        <button
          type="button"
          data-descer
          :disabled="indice === campos.length - 1"
          :aria-label="t(`${L}.DESCER`, { nome: nome(campo.chave) })"
          class="grid size-11 place-items-center rounded-xl text-n-slate-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:opacity-40"
          @click="mover(campo.chave, 1)"
        >
          <span class="i-lucide-chevron-down size-5" aria-hidden="true" />
        </button>
      </li>
    </ul>
    <button
      type="button"
      data-lista-acao-campos-padrao
      class="-mx-2 -mt-3 min-h-11 rounded-xl border-t border-n-weak px-3 text-start text-base font-medium text-n-slate-12 hover:bg-n-alpha-2"
      @click="voltarAoPadrao"
    >
      {{ t(`${L}.PADRAO`) }}
    </button>
  </Dialog>
</template>
