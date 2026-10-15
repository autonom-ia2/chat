<script setup>
import { ref } from 'vue';

// Topo navy da página inicial de Configurações (#1617), no molde do AgentesHeroi/AutomacaoHeroi: rótulo, título,
// uma frase, a busca e o "Comece por aqui" com a primeira coisa que falta.
defineProps({
  comece: { type: Object, default: null },
  tudoPronto: { type: Boolean, default: false },
});

const termo = defineModel('termo', { type: String, default: '' });
const campo = ref(null);

const limpar = () => {
  termo.value = '';
  campo.value?.focus();
};
</script>

<template>
  <section
    data-heroi
    aria-labelledby="settings-inicio-titulo"
    class="relative overflow-clip rounded-3xl bg-n-heroi dark:bg-[#12305E] px-6 py-10 text-white md:px-12 md:py-12"
  >
    <span
      aria-hidden="true"
      class="absolute rounded-full pointer-events-none -end-16 -top-24 size-80 border-[3rem] border-n-blue-9 opacity-15"
    />
    <span
      aria-hidden="true"
      class="absolute rounded-full pointer-events-none end-32 -bottom-36 size-56 border-[2rem] border-n-blue-7 opacity-10"
    />
    <div class="relative flex flex-col max-w-4xl gap-5">
      <span
        class="inline-flex items-center gap-2 text-xs font-semibold tracking-wider uppercase text-n-blue-6 dark:text-n-blue-11"
      >
        <span class="i-lucide-settings size-4" aria-hidden="true" />
        {{ $t('SETTINGS_INICIO.ROTULO') }}
      </span>
      <h1
        id="settings-inicio-titulo"
        class="m-0 text-3xl font-bold leading-tight tracking-tight text-white md:text-[2.5rem]"
      >
        {{ $t('SETTINGS_INICIO.TITULO') }}
      </h1>
      <p class="mb-0 text-base leading-relaxed md:text-lg text-white/80">
        {{ $t('SETTINGS_INICIO.TEXTO') }}
      </p>
      <div role="search" class="relative">
        <label for="settings-inicio-busca" class="sr-only">
          {{ $t('SETTINGS_INICIO.BUSCA.ROTULO') }}
        </label>
        <span
          class="absolute -translate-y-1/2 pointer-events-none i-lucide-search top-1/2 start-4 size-6 text-n-slate-10"
          aria-hidden="true"
        />
        <input
          id="settings-inicio-busca"
          ref="campo"
          v-model="termo"
          data-busca
          type="text"
          inputmode="search"
          enterkeyhint="search"
          autocomplete="off"
          :placeholder="$t('SETTINGS_INICIO.BUSCA.PLACEHOLDER')"
          class="reset-base w-full h-14 !mb-0 ps-14 pe-14 text-lg rounded-2xl border-0 bg-white text-n-slate-12 shadow-2xl placeholder:text-n-slate-10 outline-none focus:outline focus:outline-4 focus:outline-n-blue-6 dark:bg-n-solid-1"
        />
        <button
          v-if="termo"
          type="button"
          :aria-label="$t('SETTINGS_INICIO.BUSCA.LIMPAR')"
          class="absolute grid -translate-y-1/2 top-1/2 end-1.5 size-11 place-items-center rounded-xl text-n-slate-11 hover:bg-n-slate-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="limpar"
        >
          <span class="i-lucide-x size-5" aria-hidden="true" />
        </button>
      </div>
      <RouterLink
        v-if="comece && !termo"
        :to="comece.to"
        data-comece
        class="group grid grid-cols-[auto_1fr] items-center gap-4 p-4 rounded-2xl ring-1 ring-inset ring-white/20 bg-white/10 transition hover:bg-white/15 focus-visible:outline focus-visible:outline-2 focus-visible:outline-white sm:grid-cols-[auto_1fr_auto]"
      >
        <span
          class="grid shrink-0 place-items-center size-12 rounded-xl bg-n-amber-9 text-n-amber-12"
          aria-hidden="true"
        >
          <span class="size-6" :class="comece.icone" />
        </span>
        <span class="flex flex-col flex-1 min-w-0 gap-0.5">
          <span
            class="text-xs font-semibold tracking-wider uppercase text-n-blue-6 dark:text-n-blue-11"
          >
            {{ $t('SETTINGS_INICIO.COMECE.ROTULO') }}
          </span>
          <span class="text-lg font-semibold leading-snug text-white">
            {{ comece.estado.texto }}
          </span>
          <span class="text-sm text-white/70">{{ comece.titulo }}</span>
        </span>
        <span
          class="inline-flex items-center justify-center col-span-2 gap-2 px-5 text-base font-semibold whitespace-nowrap rounded-xl min-h-11 bg-white text-n-heroi group-hover:bg-white/90 sm:col-span-1"
        >
          {{ $t('SETTINGS_INICIO.ABRIR') }}
          <span
            class="i-lucide-arrow-right size-5 rtl:rotate-180"
            aria-hidden="true"
          />
        </span>
      </RouterLink>
      <p
        v-else-if="tudoPronto && !termo"
        class="inline-flex items-center gap-2 mb-0 text-base text-white/80"
      >
        <span
          class="i-lucide-circle-check size-5 text-n-teal-9"
          aria-hidden="true"
        />
        {{ $t('SETTINGS_INICIO.COMECE.TUDO_PRONTO') }}
      </p>
    </div>
  </section>
</template>
