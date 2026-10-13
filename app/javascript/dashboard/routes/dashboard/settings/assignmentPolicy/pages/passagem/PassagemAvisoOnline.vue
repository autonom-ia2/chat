<script setup>
import Button from 'dashboard/components-next/button/Button.vue';

// #1385 — regra salva pela tela antiga em que a conversa pode ir para quem está fora e calar a assistente
// (prefer_online desligado: HandoffExecutor#assign! e HandoffEscalationJob chamam bot_handoff!). Diz o que acontece
// hoje, o que muda ao corrigir e corrige com um toque, gravando na hora. No padrão do "Falta a frase" do funil (#1384).
defineProps({
  ocupado: { type: Boolean, default: false },
});

defineEmits(['corrigir']);
</script>

<template>
  <div
    data-aviso-online
    class="mt-2 flex flex-col items-start gap-3 rounded-xl border border-dashed border-n-amber-8 bg-n-amber-2 p-3 sm:flex-row sm:items-center"
  >
    <span class="flex min-w-0 flex-col gap-1 sm:flex-1">
      <span class="text-[0.9375rem] text-n-slate-12">
        {{ $t('CRM_KANBAN.PASSAGEM.ANTIGA.TEXTO') }}
      </span>
      <span class="text-sm text-n-slate-11">
        {{ $t('CRM_KANBAN.PASSAGEM.ANTIGA.EFEITO') }}
      </span>
    </span>
    <Button
      :label="$t('CRM_KANBAN.PASSAGEM.ANTIGA.BOTAO')"
      icon="i-lucide-shield-check"
      amber
      :is-loading="ocupado"
      class="!min-h-11 shrink-0 max-sm:w-full"
      @click="$emit('corrigir')"
    />
  </div>
</template>
