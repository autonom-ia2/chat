<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useEventListener } from '@vueuse/core';
import Button from 'dashboard/components-next/button/Button.vue';
import { useAvisoCrm } from './useAvisoCrm';

// Onde os avisos do CRM aparecem (useAvisoCrm): embaixo, no meio, acima das gavetas.
const { t } = useI18n();
const {
  avisos,
  fecharAviso,
  executarAviso,
  desfazerPeloTeclado,
  pausarAvisos,
} = useAvisoCrm();

const caixa = ref(null);
const atualizarPausa = () => {
  const el = caixa.value;
  if (!el) return;
  pausarAvisos(el.matches(':hover') || el.contains(document.activeElement));
};
// O foco sai depois do evento; a conferência espera ele assentar.
const depois = () => setTimeout(atualizarPausa, 0);

const EDITAVEL = ['INPUT', 'TEXTAREA', 'SELECT'];
useEventListener(document, 'keydown', evento => {
  const z = evento.key?.toLowerCase() === 'z';
  if (!z || !(evento.ctrlKey || evento.metaKey) || evento.shiftKey) return;
  const alvo = evento.target;
  if (EDITAVEL.includes(alvo?.tagName) || alvo?.isContentEditable) return;
  if (desfazerPeloTeclado()) evento.preventDefault();
});
</script>

<template>
  <div
    ref="caixa"
    role="status"
    aria-live="polite"
    data-crm-avisos
    class="pointer-events-none fixed inset-x-0 bottom-4 z-[70] flex flex-col items-center gap-2 px-4"
    @mouseenter="depois"
    @mouseleave="depois"
    @focusin="depois"
    @focusout="depois"
  >
    <div
      v-for="aviso in avisos"
      :key="aviso.id"
      data-crm-aviso
      class="pointer-events-auto flex w-full max-w-[34rem] flex-wrap items-center gap-x-3 gap-y-1 rounded-xl bg-n-slate-12 py-1.5 pe-1.5 ps-4 text-sm text-n-slate-1 shadow-lg dark:bg-n-slate-3 dark:text-n-slate-12"
    >
      <p class="mb-0 min-w-0 flex-1 py-2 leading-snug">{{ aviso.mensagem }}</p>
      <div class="flex items-center gap-1">
        <Button
          v-for="(acao, indice) in aviso.acoes"
          :key="acao.rotulo"
          data-crm-aviso-acao
          :label="acao.rotulo"
          :aria-keyshortcuts="acao.desfazer ? 'Control+Z Meta+Z' : null"
          :title="acao.desfazer ? t('CRM_ARQUIVADOS.AVISO.ATALHO') : null"
          link
          class="!min-h-11 !px-3 !font-semibold !text-n-blue-8 dark:!text-n-blue-11"
          @click="executarAviso(aviso.id, indice)"
        />
        <Button
          icon="i-lucide-x"
          ghost
          slate
          :aria-label="t('CRM_ARQUIVADOS.AVISO.FECHAR')"
          class="!min-h-11 !min-w-11 !text-n-slate-1 dark:!text-n-slate-12"
          @click="fecharAviso(aviso.id)"
        />
      </div>
    </div>
  </div>
</template>
