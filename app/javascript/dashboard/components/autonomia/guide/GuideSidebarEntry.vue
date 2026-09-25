<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useElementBounding, useWindowSize } from '@vueuse/core';
import Button from 'dashboard/components-next/button/Button.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import { useBrandedSidebar } from 'dashboard/composables/useBrandedSidebar';
import { useMapGetter } from 'dashboard/composables/store';
import { useGuiaDescoberta } from './useGuiaDescoberta';
import GuideDot from './GuideDot.vue';

// #697 — entrada do "Guia da Plataforma" no pé da barra lateral, acima do perfil (só
// computador; no celular é a bolinha do AutonomiaGuideLauncher). Aqui ela tem lugar
// próprio e não cobre nenhum controle da tela, como fazia o botão flutuante no canto.
// Com a barra recolhida vira só o ícone. O balão de apresentação sai para o lado de
// fora da barra, apontando para o botão.
const props = defineProps({
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

// Barra com cor de marca: as regras `.sidebar-branded :deep(...)` do Sidebar.vue repintam
// `.bg-n-brand` de branco a 70% — com o texto branco do botão azul, ele ficava cinza e
// parecendo desativado. Nesse caso o botão é branco sólido com o texto na cor da barra.
// A variante ghost não traz nenhuma classe que aquelas regras alcancem.
const { brandedColor } = useBrandedSidebar();
const temMarca = computed(() => Boolean(brandedColor.value));
const aparenciaDoBotao = computed(() => {
  if (!temMarca.value) {
    return { variant: painelAberto.value ? 'faded' : 'solid', classe: '' };
  }
  return {
    variant: 'ghost',
    classe: painelAberto.value
      ? '!bg-white/15 !text-white hover:!bg-white/20'
      : '!bg-white !text-[var(--sidebar-background-color)] hover:!bg-white/90',
  };
});

// O balão vai para o <body> (Teleport): dentro da barra, as mesmas regras de marca o
// deixavam transparente e com texto branco sobre a página. Fora dela, ele segue o
// botão pela posição na tela, inclusive quando a barra é recolhida ou redimensionada.
const isRTL = useMapGetter('accounts/isRTL');
const { width: larguraDaJanela, height: alturaDaJanela } = useWindowSize();
const retangulo = useElementBounding(computed(() => botaoRef.value?.$el));
const DISTANCIA_DO_BOTAO = 12;
const posicaoDoBalao = computed(() => {
  const lado = isRTL.value
    ? {
        right: `${larguraDaJanela.value - retangulo.left.value + DISTANCIA_DO_BOTAO}px`,
      }
    : { left: `${retangulo.right.value + DISTANCIA_DO_BOTAO}px` };
  return {
    ...lado,
    bottom: `${alturaDaJanela.value - retangulo.bottom.value}px`,
  };
});
// Mudar a largura da barra (recolher) mexe no botão: pede a posição de novo.
watch(
  () => props.isCollapsed,
  () => nextTick(retangulo.update)
);
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
        :variant="aparenciaDoBotao.variant"
        :justify="isCollapsed ? 'center' : 'start'"
        no-animation
        class="!h-10"
        :class="[isCollapsed ? '!w-10' : 'w-full', aparenciaDoBotao.classe]"
        @click="alternarGuia"
      />
      <GuideDot v-if="mostrarPonto" />
    </div>
    <TeleportWithDirection>
      <div
        v-if="mostrarIntro"
        data-guia-intro
        role="dialog"
        aria-modal="false"
        :aria-label="$t('AUTONOMIA_GUIDE.LAUNCHER')"
        :style="posicaoDoBalao"
        class="fixed z-50 w-72 p-3 rounded-xl bg-n-solid-2 outline outline-1 outline-n-container shadow-lg text-sm leading-6 text-n-slate-12"
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
    </TeleportWithDirection>
  </div>
  <template v-else />
</template>
