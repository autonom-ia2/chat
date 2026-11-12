<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import EsqueletoDeLista from '../comum/EsqueletoDeLista.vue';
import ErroComTentarDeNovo from '../comum/ErroComTentarDeNovo.vue';
import TituloDoDialogo from '../comum/TituloDoDialogo.vue';

// #2894 — o diálogo de Desfazer: mostra ANTES quem sai, quem fica aqui (já
// conversou ou recebeu campanha) e o que volta ao que era. Destrutivo: tocar fora não fecha.
const props = defineProps({
  // O nome da lista que vai ser desfeita, no título.
  arquivo: { type: String, default: '' },
  previa: { type: Object, default: null },
  comErroNaPrevia: { type: Boolean, default: false },
  desfazendo: { type: Boolean, default: false },
});
const emit = defineEmits(['confirmar', 'fechar', 'tentar']);

const { t } = useI18n();
const dialogo = ref(null);

const SEM_PESSOAS = 0;

// Uma frase para quem sai, quem fica e quem volta ao que era; some a que é zero.
const fraseDoQueSai = computed(() => {
  const { tira, ficam, devolve } = props.previa;
  const frases = [];
  if (tira > SEM_PESSOAS) {
    frases.push(
      t('RELACIONAMENTOS_TRAZER.DESFAZER.TIRA', { count: tira }, tira)
    );
  }
  if (ficam > SEM_PESSOAS) {
    frases.push(
      t('RELACIONAMENTOS_TRAZER.DESFAZER.FICAM', { count: ficam }, ficam)
    );
  }
  if (devolve > SEM_PESSOAS) {
    frases.push(
      t('RELACIONAMENTOS_TRAZER.DESFAZER.DEVOLVE', { count: devolve }, devolve)
    );
  }
  return frases.join(' ');
});

const titulo = computed(() =>
  props.arquivo
    ? t('RELACIONAMENTOS_TRAZER.DESFAZER.TITULO_ARQUIVO', {
        arquivo: props.arquivo,
      })
    : t('RELACIONAMENTOS_TRAZER.DESFAZER.TITULO')
);

defineExpose({
  abrir: () => dialogo.value?.open(),
  fechar: () => dialogo.value?.close(),
});
</script>

<template>
  <Dialog
    ref="dialogo"
    type="alert"
    width="md"
    :close-on-outside-click="false"
    @close="emit('fechar')"
    @confirm="emit('confirmar')"
  >
    <div
      data-relacionamentos="dialogo-desfazer"
      class="flex flex-col gap-3 text-sm text-n-slate-11"
      aria-live="polite"
    >
      <TituloDoDialogo :titulo="titulo" />
      <template v-if="previa">
        <p class="m-0 text-n-slate-12">{{ fraseDoQueSai }}</p>
        <p class="m-0">
          {{ t('RELACIONAMENTOS_TRAZER.DESFAZER.NAO_RECEBER') }}
        </p>
      </template>
      <ErroComTentarDeNovo
        v-else-if="comErroNaPrevia"
        :mensagem="t('RELACIONAMENTOS_TRAZER.DESFAZER.ERRO_PREVIA')"
        @tentar="emit('tentar')"
      />
      <EsqueletoDeLista v-else :linhas="2" />
    </div>
    <template #footer>
      <div class="flex items-center justify-between w-full gap-3">
        <Button
          variant="faded"
          color="slate"
          size="lg"
          class="w-full"
          type="button"
          :label="t('RELACIONAMENTOS.COMUM.CANCELAR')"
          @click="dialogo?.close()"
        />
        <Button
          color="ruby"
          size="lg"
          class="w-full"
          type="submit"
          data-relacionamentos="desfazer-confirmar"
          :label="t('RELACIONAMENTOS_TRAZER.DESFAZER.CONFIRMAR')"
          :is-loading="desfazendo"
          :disabled="!previa || desfazendo"
        />
      </div>
    </template>
  </Dialog>
</template>
