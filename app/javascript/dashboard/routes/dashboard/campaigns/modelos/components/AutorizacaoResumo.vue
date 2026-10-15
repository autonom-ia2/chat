<script setup>
import { computed } from 'vue';
import { useBranding } from 'shared/composables/useBranding';
import { useAutorizacao } from '../helpers/useAutorizacao';

// #1586 — na lista de Modelos, só para quem administra modelos: se o
// sistema pode criar modelos sozinho e o caminho para ver ou mudar.
const { installationName } = useBranding();
const { estado, autorizacao } = useAutorizacao();
const marca = computed(() => installationName.value || 'Chat2You');

const chaveDoResumo = computed(() => {
  if (!autorizacao.value?.servico) return 'DESLIGADA';
  return autorizacao.value.divulgacao ? 'LIGADA_TUDO' : 'LIGADA_SERVICO';
});
const ligada = computed(() => Boolean(autorizacao.value?.servico));
</script>

<template>
  <div class="contents">
    <router-link
      v-if="estado === 'pronto'"
      data-autorizacao-resumo
      :to="{ name: 'modelos_whatsapp_autorizacao' }"
      class="flex items-center gap-4 px-5 py-4 no-underline rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1 hover:bg-n-alpha-1 min-h-11"
    >
      <span
        class="grid place-items-center size-11 shrink-0 rounded-xl"
        :class="
          ligada ? 'bg-n-teal-3 text-n-teal-11' : 'bg-n-slate-3 text-n-slate-11'
        "
      >
        <span
          class="size-6"
          :class="ligada ? 'i-lucide-shield-check' : 'i-lucide-shield'"
          aria-hidden="true"
        />
      </span>
      <span class="flex flex-col flex-1 min-w-0 gap-0.5">
        <span class="text-base font-semibold text-n-slate-12">
          {{ $t('MODELOS_WHATSAPP.AUTORIZACAO.RESUMO.TITULO', { marca }) }}
        </span>
        <span class="text-[0.9375rem] text-n-slate-11">
          {{
            $t(`MODELOS_WHATSAPP.AUTORIZACAO.RESUMO.${chaveDoResumo}`, {
              marca,
            })
          }}
        </span>
      </span>
      <span
        class="hidden text-[0.9375rem] font-medium sm:inline text-n-blue-11"
      >
        {{ $t('MODELOS_WHATSAPP.AUTORIZACAO.RESUMO.ABRIR') }}
      </span>
      <span
        class="i-lucide-chevron-right size-5 shrink-0 text-n-slate-10 rtl:rotate-180"
        aria-hidden="true"
      />
    </router-link>
  </div>
</template>
