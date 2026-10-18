<script setup>
// "Mostrar original" do menu ⋮ (#1786): os cabeçalhos que o e-mail trouxe (inclusive
// Message-ID e Em resposta a, úteis quando o suporte pergunta) e o texto puro, só
// leitura, com Copiar. O HTML nunca é mostrado cru.
import { computed, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  // Pares [rótulo, valor] já prontos para mostrar.
  linhas: { type: Array, required: true },
  texto: { type: String, default: '' },
});

const { t } = useI18n();
const dialogo = useTemplateRef('dialogo');
const visiveis = computed(() => props.linhas.filter(([, valor]) => valor));

const copiar = async () => {
  const cabecalho = visiveis.value
    .map(([rotulo, valor]) => `${rotulo}: ${valor}`)
    .join('\n');
  await copyTextToClipboard(`${cabecalho}\n\n${props.texto}`);
  useAlert(t('CONTACT_PANEL.COPY_SUCCESSFUL'));
};

// Classe numa constante: o <pre> cabe numa linha e o texto não ganha quebra do formatador.
const CAIXA_DO_TEXTO =
  'max-h-80 overflow-auto p-3 rounded-lg bg-n-alpha-1 text-xs text-n-slate-12 whitespace-pre-wrap break-words font-mono';

defineExpose({ open: () => dialogo.value?.open() });
</script>

<template>
  <Dialog
    ref="dialogo"
    :title="t('CONVERSA_CANAL.EMAIL.MOSTRAR_ORIGINAL')"
    :confirm-button-label="t('CONVERSA_CANAL.EMAIL.COPIAR_TUDO')"
    :cancel-button-label="t('CONVERSA_CANAL.EMAIL.FECHAR')"
    width="2xl"
    overflow-y-auto
    @confirm="copiar"
  >
    <dl
      class="grid grid-cols-[auto_minmax(0,1fr)] gap-x-3 gap-y-1.5 p-3 rounded-lg border border-n-weak bg-n-alpha-1 text-xs"
      data-original-do-email
    >
      <template v-for="[rotulo, valor] in visiveis" :key="rotulo">
        <dt class="text-n-slate-11 text-end">{{ rotulo }}</dt>
        <dd class="text-n-slate-12 break-all font-mono">{{ valor }}</dd>
      </template>
    </dl>
    <pre v-if="texto" :class="CAIXA_DO_TEXTO">{{ texto }}</pre>
  </Dialog>
</template>
