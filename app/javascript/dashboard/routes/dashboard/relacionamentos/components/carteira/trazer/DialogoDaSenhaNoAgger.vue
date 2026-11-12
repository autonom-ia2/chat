<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TituloDoDialogo from '../../comum/TituloDoDialogo.vue';

// #2897 — "Como resolver" a senha de uma seguradora que falta no Agger: o que
// fazer lá e, na volta, UM botão para tentar de novo. O mesmo caminho serve a
// busca dos seguros (Trazer) e a cotação da renovação; quem usa diz o texto e
// o que o botão faz.
defineProps({
  seguradora: { type: String, default: '' },
  texto: { type: String, default: '' },
  rotuloDaAcao: { type: String, required: true },
  marcaDaAcao: { type: String, default: 'agger-buscar-de-novo' },
  ocupado: { type: Boolean, default: false },
});
const emit = defineEmits(['resolver']);

const { t } = useI18n();
const dialogo = ref(null);

defineExpose({
  abrir: () => dialogo.value?.open(),
  fechar: () => dialogo.value?.close(),
});
</script>

<template>
  <Dialog ref="dialogo" width="md" @confirm="emit('resolver')">
    <div
      data-carteira="agger-dialogo-senha"
      class="flex flex-col gap-3 text-sm text-n-slate-11"
    >
      <TituloDoDialogo
        :titulo="
          t('RELACIONAMENTOS_CARTEIRA.TRAZER.AGGER.COMO_RESOLVER_TITULO', {
            seguradora,
          })
        "
      />
      <p class="m-0 text-base text-n-slate-12">{{ texto }}</p>
    </div>
    <template #footer>
      <div class="flex items-center justify-between w-full gap-3">
        <Button
          variant="faded"
          color="slate"
          size="lg"
          class="w-full"
          type="button"
          data-carteira="agger-fechar-dialogo"
          :label="t('RELACIONAMENTOS.COMUM.ENTENDI')"
          @click="dialogo?.close()"
        />
        <Button
          size="lg"
          class="w-full"
          type="submit"
          :data-carteira="marcaDaAcao"
          :label="rotuloDaAcao"
          :is-loading="ocupado"
          :disabled="ocupado"
        />
      </div>
    </template>
  </Dialog>
</template>
