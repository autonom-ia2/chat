<script setup>
import { nextTick, ref, watch } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { useGuiaDescoberta } from './useGuiaDescoberta';
import GuideDot from './GuideDot.vue';

// #697 — entrada do "Guia da Plataforma" no pé da barra lateral, acima do perfil (só
// computador; no celular é a bolinha do AutonomiaGuideLauncher). Aqui ela tem lugar
// próprio e não cobre nenhum controle da tela, como fazia o botão flutuante no canto.
// Com a barra recolhida vira só o ícone. O balão de apresentação sai para o lado de
// fora da barra, apontando para o botão.
defineProps({
  isCollapsed: { type: Boolean, default: false },
});

const {
  guiaDisponivel,
  painelAberto,
  mostrarIntro,
  mostrarPonto,
  entendi,
  depois,
  alternarGuia,
} = useGuiaDescoberta();

const botaoRef = ref(null);

// Quando o painel fecha (pelo X dele ou pelo Esc), o foco volta para este botão, senão
// fica no nada e quem usa teclado recomeça do topo da página.
watch(painelAberto, async (aberto, estavaAberto) => {
  if (aberto || !estavaAberto) return;
  await nextTick();
  botaoRef.value?.$el?.focus();
});
</script>

<template>
  <div
    v-if="guiaDisponivel"
    class="relative hidden md:flex w-full px-1"
    :class="isCollapsed ? 'justify-center' : ''"
  >
    <div class="relative" :class="isCollapsed ? '' : 'w-full'">
      <Button
        ref="botaoRef"
        data-guia-abrir
        icon="i-lucide-circle-help"
        :label="isCollapsed ? undefined : $t('AUTONOMIA_GUIDE.LAUNCHER_LABEL')"
        :title="$t('AUTONOMIA_GUIDE.LAUNCHER_LABEL')"
        :aria-label="$t('AUTONOMIA_GUIDE.LAUNCHER_LABEL')"
        :aria-expanded="painelAberto"
        color="blue"
        :variant="painelAberto ? 'faded' : 'solid'"
        :justify="isCollapsed ? 'center' : 'start'"
        no-animation
        class="!h-10"
        :class="isCollapsed ? '!w-10' : 'w-full'"
        @click="alternarGuia"
      />
      <GuideDot v-if="mostrarPonto" />
    </div>
    <div
      v-if="mostrarIntro"
      data-guia-intro
      role="dialog"
      aria-modal="false"
      :aria-label="$t('AUTONOMIA_GUIDE.LAUNCHER')"
      class="absolute bottom-0 ltr:left-full rtl:right-full ltr:ml-3 rtl:mr-3 z-50 w-72 p-3 rounded-xl bg-n-solid-2 outline outline-1 outline-n-container shadow-lg text-sm leading-6 text-n-slate-12"
    >
      <span
        aria-hidden="true"
        class="absolute bottom-4 ltr:-left-1.5 rtl:-right-1.5 size-3 rotate-45 bg-n-solid-2 ltr:border-l ltr:border-b rtl:border-r rtl:border-t border-n-container"
      />
      <p class="mb-2">{{ $t('AUTONOMIA_GUIDE.INTRO.TEXT') }}</p>
      <div class="flex items-center gap-2">
        <Button
          data-guia-entendi
          :label="$t('AUTONOMIA_GUIDE.INTRO.OK')"
          color="blue"
          sm
          @click="entendi"
        />
        <Button
          data-guia-depois
          :label="$t('AUTONOMIA_GUIDE.INTRO.LATER')"
          color="slate"
          variant="ghost"
          sm
          @click="depois"
        />
      </div>
    </div>
  </div>
  <template v-else />
</template>
