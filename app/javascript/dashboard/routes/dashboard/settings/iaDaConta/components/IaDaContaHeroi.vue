<script setup>
import { computed } from 'vue';

// #2472: o topo da tela diz, numa frase, se a IA da conta está funcionando.
const props = defineProps({
  estado: { type: Object, required: true },
});

const titulo = computed(
  () =>
    ({
      vazio: 'VAZIO_TITULO',
      ok: 'OK_TITULO',
      parcial: 'PARCIAL_TITULO',
      parada: 'PARADA_TITULO',
    })[props.estado.tipo]
);

const selo = computed(
  () =>
    ({
      vazio: { chave: 'SELO_VAZIO', cor: 'bg-white/15 text-white' },
      ok: { chave: 'SELO_OK', cor: 'bg-n-teal-9 text-white' },
      parcial: { chave: 'SELO_PARCIAL', cor: 'bg-n-amber-9 text-white' },
      parada: { chave: 'SELO_PARADA', cor: 'bg-n-ruby-9 text-white' },
    })[props.estado.tipo]
);
</script>

<template>
  <section
    data-heroi
    :data-estado="estado.tipo"
    class="relative overflow-hidden rounded-3xl bg-[#0D2344] px-6 py-10 text-white md:px-12 md:py-12"
  >
    <span
      aria-hidden="true"
      class="absolute rounded-full pointer-events-none -end-16 -top-24 size-80 border-[3rem] border-n-blue-9 opacity-15"
    />
    <span
      aria-hidden="true"
      class="absolute rounded-full pointer-events-none end-32 -bottom-36 size-56 border-[2rem] border-n-blue-7 opacity-10"
    />
    <div class="relative flex flex-col gap-4 max-w-3xl">
      <div class="flex flex-wrap items-center gap-3">
        <span
          class="inline-flex items-center gap-2 text-sm font-semibold text-n-blue-6"
        >
          <span class="i-lucide-sparkles size-4" aria-hidden="true" />
          {{ $t('IA_DA_CONTA.ROTULO') }}
        </span>
        <span
          data-selo-heroi
          class="inline-flex items-center gap-2 px-3 py-1 text-sm font-semibold rounded-full"
          :class="selo.cor"
        >
          <span class="rounded-full size-2 bg-current" aria-hidden="true" />
          {{ $t(`IA_DA_CONTA.HEROI.${selo.chave}`) }}
        </span>
      </div>
      <h1
        class="text-3xl font-bold leading-tight tracking-tight text-white md:text-[2.5rem]"
      >
        {{ $t(`IA_DA_CONTA.HEROI.${titulo}`) }}
      </h1>
      <p class="mb-0 text-base leading-relaxed md:text-lg text-white/75">
        {{ $t(`IA_DA_CONTA.HEROI.${estado.texto}`) }}
      </p>
    </div>
  </section>
</template>
