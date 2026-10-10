<script setup>
import { onBeforeUnmount, onMounted, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useScrollLock } from '@vueuse/core';
import { useModalFocus } from 'dashboard/components-next/CampaignJourney/useModalFocus';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';

// #1181 — gaveta lateral do módulo (folha de baixo no celular). Mesma base do AudienceSidePanel:
// foco entra no botão de fechar, Tab e Shift+Tab ficam dentro, Esc fecha e o foco volta para quem
// abriu (useModalFocus, reaproveitado sem editar). Vai para o body (TeleportWithDirection, como o
// AudienceSidePanel): fora do contêiner que rola, a rolagem não vaza para a lista por trás, e um
// ancestral com transform não prende o `fixed`. A página por trás não rola enquanto ela está
// aberta. Quem usa monta com v-if e fecha no evento `fechar`.
defineProps({
  titulo: { type: String, required: true },
  larga: { type: Boolean, default: false },
});

const emit = defineEmits(['fechar']);

const { t } = useI18n();
const tituloId = `gaveta-${useId()}`;
const painel = ref(null);
const fechar = ref(null);

const travaRolagem = useScrollLock(
  typeof document === 'undefined' ? null : document.body
);
onMounted(() => {
  travaRolagem.value = true;
});
onBeforeUnmount(() => {
  travaRolagem.value = false;
});

useModalFocus({
  container: painel,
  initial: fechar,
  onClose: () => emit('fechar'),
});
</script>

<template>
  <TeleportWithDirection>
    <div
      data-fundo
      role="presentation"
      class="fixed inset-0 z-40 bg-n-alpha-black1"
      @click="emit('fechar')"
    />
    <aside
      ref="painel"
      role="dialog"
      aria-modal="true"
      :aria-labelledby="tituloId"
      tabindex="-1"
      class="fixed inset-x-0 bottom-0 z-40 flex flex-col max-h-[90vh] rounded-t-2xl bg-n-solid-1 shadow-xl outline-none sm:inset-x-auto sm:inset-y-0 sm:max-h-none sm:rounded-none ltr:sm:right-0 rtl:sm:left-0 ltr:sm:border-l rtl:sm:border-r border-n-weak"
      :class="larga ? 'sm:w-[32.5rem]' : 'sm:w-[30rem]'"
    >
      <header
        class="flex items-center justify-between gap-3 px-5 py-3 border-b border-n-weak"
      >
        <h2 :id="tituloId" class="m-0 text-lg font-semibold text-n-slate-12">
          {{ titulo }}
        </h2>
        <button
          ref="fechar"
          data-fechar
          type="button"
          :aria-label="t('AGENTS.JORNADA.COMUM.FECHAR')"
          class="grid rounded-xl place-items-center size-11 shrink-0 text-n-slate-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
          @click="emit('fechar')"
        >
          <span class="i-lucide-x size-5" aria-hidden="true" />
        </button>
      </header>
      <div
        class="flex flex-col flex-1 min-h-0 gap-4 px-5 py-4 overflow-y-auto overscroll-contain"
      >
        <slot />
      </div>
      <footer
        v-if="$slots.rodape"
        class="flex flex-col gap-2 px-5 py-4 border-t border-n-weak"
      >
        <slot name="rodape" />
      </footer>
    </aside>
  </TeleportWithDirection>
</template>
