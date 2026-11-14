<script setup>
import { nextTick, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TituloDoDialogo from '../../comum/TituloDoDialogo.vue';
import { MOTIVOS, MOTIVO_ESCRITO } from '../../../carteira/situacaoDaRenovacao';

// #2898 — "Por que não renovou?": quatro motivos, um toque guarda e fecha.
// "Outro motivo" abre uma linha para escrever, e aí aparece o Salvar (sempre
// ligado: sem texto, o clique diz o que falta e leva o foco até lá). Emite
// `escolher` com { motivo } ou { motivo: 'outro', texto }, uma vez só por
// abertura: o segundo toque, com o diálogo ainda fechando, não emite de novo.
const emit = defineEmits(['escolher']);

const { t } = useI18n();
const mo = chave => t(`RELACIONAMENTOS_CARTEIRA.RENOVACAO.MOTIVO.${chave}`);
const id = useId();
const dialogo = ref(null);
const escrevendo = ref(false);
const texto = ref('');
const falta = ref(false);
const escolhido = ref(false);

const focarTexto = () => document.getElementById(`${id}-texto`)?.focus();

const escolher = escolha => {
  if (escolhido.value) return;
  escolhido.value = true;
  dialogo.value?.close();
  emit('escolher', escolha);
};
const escrever = async () => {
  escrevendo.value = true;
  await nextTick();
  focarTexto();
};
const salvar = () => {
  const escrito = texto.value.trim();
  falta.value = !escrito;
  if (falta.value) focarTexto();
  else escolher({ motivo: MOTIVO_ESCRITO, texto: escrito });
};

defineExpose({
  abrir: () => {
    escrevendo.value = false;
    texto.value = '';
    falta.value = false;
    escolhido.value = false;
    dialogo.value?.open();
  },
});
</script>

<template>
  <Dialog
    ref="dialogo"
    width="sm"
    :show-confirm-button="escrevendo"
    :confirm-button-label="mo('SALVAR')"
    :cancel-button-label="mo('VOLTAR')"
    @confirm="salvar"
  >
    <div data-carteira="motivo" class="flex flex-col gap-4">
      <TituloDoDialogo :titulo="mo('TITULO')" />
      <ul class="flex flex-col gap-2 p-0 m-0 list-none">
        <li v-for="motivo in MOTIVOS" :key="motivo">
          <button
            type="button"
            data-carteira="motivo-de-um-toque"
            :data-motivo="motivo"
            class="w-full px-4 text-base font-semibold rounded-xl min-h-11 text-start bg-n-solid-1 text-n-slate-12 ring-1 ring-inset ring-n-weak hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            @click="escolher({ motivo })"
          >
            {{ mo(`NOME.${motivo.toUpperCase()}`) }}
          </button>
        </li>
      </ul>
      <div v-if="escrevendo" class="flex flex-col gap-2">
        <label :for="`${id}-texto`" class="text-base text-n-slate-12">
          {{ mo('QUAL') }}
        </label>
        <input
          :id="`${id}-texto`"
          v-model="texto"
          type="text"
          autocomplete="off"
          data-carteira="motivo-escrito"
          :aria-invalid="falta ? 'true' : undefined"
          :aria-describedby="falta ? `${id}-falta` : undefined"
          class="block w-full px-3 text-base border-0 rounded-lg h-11 reset-base outline outline-1 outline-offset-[-1px] bg-n-alpha-black2 text-n-slate-12 focus:outline-n-brand"
          :class="falta ? 'outline-n-ruby-8' : 'outline-n-weak'"
          @keydown.enter.prevent="salvar"
        />
        <p
          v-if="falta"
          :id="`${id}-falta`"
          role="alert"
          data-carteira="falta-o-motivo"
          class="m-0 text-base font-medium text-n-ruby-11"
        >
          {{ mo('FALTA') }}
        </p>
      </div>
      <div v-else>
        <Button
          link
          size="lg"
          type="button"
          data-carteira="motivo-outro"
          :label="mo('NOME.OUTRO')"
          @click="escrever"
        />
      </div>
    </div>
  </Dialog>
</template>
