<script setup>
import { nextTick, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

// #2379 — "Mais → Organizar por": uma escolha só. Grupo de opções (radio):
// setas mudam o foco, Enter, Espaço ou toque escolhem e fecham.
const props = defineProps({
  opcoes: { type: Array, required: true },
  modelValue: { type: String, required: true },
});
const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const L = 'CRM_LISTA_ACAO.ORGANIZAR';
const dialogo = useTemplateRef('dialogo');
const grupo = useTemplateRef('grupo');
// As três primeiras separam em grupos; um traço antes das que viram lista.
const SEPARA_ANTES = 'retorno';

const botoes = () => [
  ...(grupo.value?.querySelectorAll('[role="radio"]') || []),
];

const abrir = async () => {
  dialogo.value?.open();
  await nextTick();
  botoes()
    .find(botao => botao.getAttribute('aria-checked') === 'true')
    ?.focus();
};

const escolher = opcao => {
  emit('update:modelValue', opcao);
  dialogo.value?.close();
};

const teclas = event => {
  const passo = { ArrowDown: 1, ArrowRight: 1, ArrowUp: -1, ArrowLeft: -1 }[
    event.key
  ];
  if (!passo) return;
  event.preventDefault();
  const todos = botoes();
  const atual = todos.indexOf(document.activeElement);
  todos[(atual + passo + todos.length) % todos.length]?.focus();
};

defineExpose({ abrir });
</script>

<template>
  <Dialog
    ref="dialogo"
    width="sm"
    :title="t(`${L}.TITULO`)"
    :description="t(`${L}.DICA`)"
    :show-confirm-button="false"
    :cancel-button-label="t(`${L}.FECHAR`)"
  >
    <div
      ref="grupo"
      role="radiogroup"
      :aria-label="t(`${L}.TITULO`)"
      class="-mx-2 flex flex-col"
      data-lista-acao-organizar
      @keydown="teclas"
    >
      <template v-for="opcao in props.opcoes" :key="opcao">
        <div
          v-if="opcao === SEPARA_ANTES"
          role="separator"
          class="my-1 border-t border-n-weak"
        />
        <button
          type="button"
          role="radio"
          :aria-checked="opcao === modelValue"
          :tabindex="opcao === modelValue ? 0 : -1"
          :data-organizar="opcao"
          class="flex min-h-11 w-full items-center gap-3 rounded-xl px-3 text-start text-base text-n-slate-12 hover:bg-n-alpha-2 focus-visible:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="escolher(opcao)"
        >
          <span
            class="grid size-5 shrink-0 place-items-center text-n-blue-11"
            aria-hidden="true"
          >
            <span v-if="opcao === modelValue" class="i-lucide-check size-5" />
          </span>
          {{ t(`${L}.OPCOES.${opcao.toUpperCase()}`) }}
        </button>
      </template>
    </div>
  </Dialog>
</template>
