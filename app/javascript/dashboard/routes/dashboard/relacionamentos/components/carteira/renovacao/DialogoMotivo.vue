<script setup>
import { nextTick, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TituloDoDialogo from '../../comum/TituloDoDialogo.vue';

// #2897 — "Por que não renovou?": quatro motivos, um toque guarda e fecha.
// "Outro motivo" abre uma linha para escrever, com Salvar (sempre ligado: sem
// texto, o clique diz o que falta e leva o foco até lá).
const emit = defineEmits(['escolher']);

const { t } = useI18n();
const tm = chave => t(`RELACIONAMENTOS_CARTEIRA.RENOVACAO.MOTIVO.${chave}`);
const id = useId();
const dialogo = ref(null);
const escrevendo = ref(false);
const texto = ref('');
const falta = ref(false);

const MOTIVOS = [
  { id: 'achou_caro', marca: 'motivo-caro', chave: 'ACHOU_CARO' },
  { id: 'outra_corretora', marca: 'motivo-outra', chave: 'OUTRA_CORRETORA' },
  { id: 'vendeu_o_bem', marca: 'motivo-vendeu', chave: 'VENDEU_O_BEM' },
  {
    id: 'nao_respondeu',
    marca: 'motivo-nao-respondeu',
    chave: 'NAO_RESPONDEU',
  },
];
const MOTIVO_ESCRITO = 'outro';

const escolher = motivo => {
  dialogo.value?.close();
  emit('escolher', motivo);
};
const escrever = async () => {
  escrevendo.value = true;
  await nextTick();
  document.getElementById(`${id}-texto`)?.focus();
};
const salvar = () => {
  const escrito = texto.value.trim();
  falta.value = !escrito;
  if (falta.value) document.getElementById(`${id}-texto`)?.focus();
  else escolher({ motivo: MOTIVO_ESCRITO, texto: escrito });
};

defineExpose({
  abrir: () => {
    escrevendo.value = false;
    texto.value = '';
    falta.value = false;
    dialogo.value?.open();
  },
});
</script>

<template>
  <Dialog ref="dialogo" width="sm" @confirm="salvar">
    <div data-carteira="motivo" class="flex flex-col gap-4">
      <TituloDoDialogo :titulo="tm('TITULO')" />
      <ul class="flex flex-col gap-2 p-0 m-0 list-none">
        <li v-for="motivo in MOTIVOS" :key="motivo.id">
          <button
            type="button"
            :data-carteira="motivo.marca"
            class="w-full px-4 text-base font-semibold rounded-xl min-h-11 text-start bg-n-solid-1 text-n-slate-12 ring-1 ring-inset ring-n-weak hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            @click="escolher({ motivo: motivo.id })"
          >
            {{ tm(`NOME.${motivo.chave}`) }}
          </button>
        </li>
      </ul>
      <div v-if="escrevendo" class="flex flex-col gap-2">
        <label :for="`${id}-texto`" class="text-base text-n-slate-12">
          {{ tm('QUAL') }}
        </label>
        <input
          :id="`${id}-texto`"
          v-model="texto"
          type="text"
          data-carteira="motivo-escrito"
          :aria-invalid="falta ? 'true' : undefined"
          :aria-describedby="falta ? `${id}-falta` : undefined"
          class="block w-full px-3 text-base border-0 rounded-lg h-11 reset-base outline outline-1 outline-offset-[-1px] bg-n-alpha-black2 text-n-slate-12 focus:outline-n-brand"
          :class="falta ? 'outline-n-ruby-8' : 'outline-n-weak'"
        />
        <p
          v-if="falta"
          :id="`${id}-falta`"
          role="alert"
          class="m-0 text-base font-medium text-n-ruby-11"
        >
          {{ tm('FALTA') }}
        </p>
      </div>
      <div v-else>
        <Button
          link
          size="lg"
          type="button"
          data-carteira="motivo-outro"
          :label="tm('OUTRO')"
          @click="escrever"
        />
      </div>
    </div>
    <template #footer>
      <div class="flex items-center justify-between w-full gap-3">
        <Button
          variant="faded"
          color="slate"
          class="w-full"
          type="button"
          :label="tm('FECHAR')"
          @click="dialogo?.close()"
        />
        <Button
          v-if="escrevendo"
          data-carteira="salvar-motivo"
          class="w-full"
          type="submit"
          :label="tm('SALVAR')"
        />
      </div>
    </template>
  </Dialog>
</template>
