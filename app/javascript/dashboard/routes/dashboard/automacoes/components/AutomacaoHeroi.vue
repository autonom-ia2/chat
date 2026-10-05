<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

// #982 — a porta de entrada da tela vazia: uma pergunta, um campo e um botão.
// O texto vai para a tela de nova automação, onde o Guia monta. As ideias
// preenchem o campo para a pessoa ver como se pede.
defineProps({
  desabilitado: { type: Boolean, default: false },
});

const emit = defineEmits(['pedir', 'falar']);

const { t } = useI18n();
const pedido = ref('');
const IDEIAS = ['RECLAMACAO', 'FORA_DO_HORARIO', 'ORCAMENTO'];
const ideias = computed(() =>
  IDEIAS.map(chave => t(`AUTOMACOES.HEROI.IDEIAS.${chave}`))
);

const enviar = () => {
  const texto = pedido.value.trim();
  if (texto) emit('pedir', texto);
};
</script>

<template>
  <section
    data-heroi
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
    <div class="relative flex flex-col gap-5 max-w-3xl">
      <span
        class="inline-flex items-center gap-2 text-xs font-semibold tracking-wider uppercase text-n-blue-6"
      >
        <span class="i-lucide-sparkles size-4" aria-hidden="true" />
        {{ $t('AUTOMACOES.LISTA.TITULO') }}
      </span>
      <h1
        class="text-3xl font-bold leading-tight tracking-tight text-white md:text-[2.5rem]"
      >
        {{ $t('AUTOMACOES.HEROI.TITULO') }}
      </h1>
      <p class="mb-0 text-base leading-relaxed md:text-lg text-white/75">
        {{ $t('AUTOMACOES.HEROI.TEXTO') }}
      </p>
      <form
        class="flex flex-col gap-2 p-2 bg-white shadow-2xl sm:flex-row sm:items-center rounded-2xl"
        @submit.prevent="enviar"
      >
        <label for="automacao-pedido" class="sr-only">
          {{ $t('AUTOMACOES.HEROI.TITULO') }}
        </label>
        <input
          id="automacao-pedido"
          v-model="pedido"
          data-pedido
          type="text"
          maxlength="500"
          :disabled="desabilitado"
          :placeholder="$t('AUTOMACOES.HEROI.EXEMPLO')"
          class="flex-1 min-w-0 px-4 text-base bg-transparent border-0 outline-none min-h-[3.25rem] text-n-slate-12 placeholder:text-n-slate-10 disabled:cursor-not-allowed !mb-0"
        />
        <button
          type="button"
          data-falar
          :disabled="desabilitado"
          :aria-label="$t('AUTOMACOES.HEROI.FALAR')"
          :title="$t('AUTOMACOES.HEROI.FALAR')"
          class="hidden sm:grid place-items-center shrink-0 size-[3.25rem] rounded-xl ring-1 ring-inset ring-n-weak bg-n-slate-2 text-[#0D2344] transition hover:bg-n-slate-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:cursor-not-allowed disabled:opacity-50"
          @click="emit('falar')"
        >
          <span class="i-lucide-mic size-6" aria-hidden="true" />
        </button>
        <button
          type="submit"
          data-montar
          :disabled="desabilitado || !pedido.trim()"
          class="inline-flex items-center justify-center gap-2 px-6 text-base font-semibold text-white transition min-h-[3.25rem] rounded-xl bg-n-brand hover:brightness-110 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand disabled:cursor-not-allowed disabled:opacity-50"
        >
          {{ $t('AUTOMACOES.HEROI.MONTAR') }}
          <span
            class="i-lucide-arrow-right size-5 rtl:rotate-180"
            aria-hidden="true"
          />
        </button>
      </form>
      <div class="flex flex-wrap items-center gap-2">
        <span class="text-sm text-white/60">
          {{ $t('AUTOMACOES.HEROI.IDEIAS_ROTULO') }}
        </span>
        <button
          v-for="ideia in ideias"
          :key="ideia"
          type="button"
          data-ideia
          :disabled="desabilitado"
          class="px-4 py-2 text-sm transition rounded-xl min-h-11 ring-1 ring-inset ring-white/20 bg-white/10 text-white/90 hover:bg-white/20 focus-visible:outline focus-visible:outline-2 focus-visible:outline-white disabled:cursor-not-allowed"
          @click="pedido = ideia"
        >
          {{ ideia }}
        </button>
      </div>
    </div>
  </section>
</template>
