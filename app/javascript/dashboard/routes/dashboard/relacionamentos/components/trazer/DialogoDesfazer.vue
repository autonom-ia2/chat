<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import EsqueletoDeLista from '../comum/EsqueletoDeLista.vue';
import ErroComTentarDeNovo from '../comum/ErroComTentarDeNovo.vue';

// #2894 — o diálogo de Desfazer: mostra ANTES o que sai e o que volta ao que
// era, e se alguém já recebeu campanha. Destrutivo: tocar fora não fecha.
const props = defineProps({
  previa: { type: Object, default: null },
  comErroNaPrevia: { type: Boolean, default: false },
  desfazendo: { type: Boolean, default: false },
});
const emit = defineEmits(['confirmar', 'fechar', 'tentar']);

const { t } = useI18n();
const dialogo = ref(null);

const SEM_PESSOAS = 0;

const fraseDoQueSai = computed(() => {
  const { tira, devolve } = props.previa;
  if (tira > SEM_PESSOAS) {
    const parte = t(
      'RELACIONAMENTOS_TRAZER.DESFAZER.TIRA',
      { count: tira },
      tira
    );
    if (devolve === SEM_PESSOAS) return `${parte}.`;
    return `${parte} ${t('RELACIONAMENTOS_TRAZER.DESFAZER.DEVOLVE_JUNTO', { count: devolve }, devolve)}.`;
  }
  return `${t('RELACIONAMENTOS_TRAZER.DESFAZER.DEVOLVE_SOZINHO', { count: devolve }, devolve)}.`;
});

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
    :title="t('RELACIONAMENTOS_TRAZER.DESFAZER.TITULO')"
    :close-on-outside-click="false"
    @close="emit('fechar')"
    @confirm="emit('confirmar')"
  >
    <div
      data-relacionamentos="dialogo-desfazer"
      class="flex flex-col gap-3 text-sm text-n-slate-11"
      aria-live="polite"
    >
      <template v-if="previa">
        <p class="m-0 text-n-slate-12">{{ fraseDoQueSai }}</p>
        <p class="m-0">{{ t('RELACIONAMENTOS_TRAZER.DESFAZER.CONVERSAS') }}</p>
        <p
          v-if="previa.receberamCampanha"
          class="m-0 font-medium text-n-amber-11"
        >
          {{
            t(
              'RELACIONAMENTOS_TRAZER.DESFAZER.CAMPANHA',
              { count: previa.receberamCampanha },
              previa.receberamCampanha
            )
          }}
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
          class="w-full min-h-11"
          type="button"
          :label="t('RELACIONAMENTOS.COMUM.CANCELAR')"
          @click="dialogo?.close()"
        />
        <Button
          color="ruby"
          class="w-full min-h-11"
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
