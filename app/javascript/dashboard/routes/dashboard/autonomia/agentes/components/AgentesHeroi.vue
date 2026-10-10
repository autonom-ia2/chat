<script setup>
import { useId } from 'vue';

// #1181 — o bloco navy da tela (um por tela, DECISOES.md item 10), com os anéis do AutomacaoHeroi.
// `compacto` é o herói da lista com agentes (T02); o cheio é o da lista vazia (T01), com os modelos
// no slot padrão. Ações (Criar agente) vão no slot `acoes`.
defineProps({
  titulo: { type: String, required: true },
  texto: { type: String, default: '' },
  compacto: { type: Boolean, default: false },
});

const tituloId = `heroi-${useId()}`;
</script>

<template>
  <section
    data-heroi
    :aria-labelledby="tituloId"
    class="relative overflow-hidden rounded-3xl bg-[#0D2344] dark:bg-[#12305E] text-white"
    :class="compacto ? 'px-6 py-6 md:px-8' : 'px-6 py-10 md:px-12 md:py-12'"
  >
    <span
      aria-hidden="true"
      class="absolute rounded-full pointer-events-none -end-16 -top-24 size-80 border-[3rem] border-n-blue-9 opacity-15"
    />
    <span
      aria-hidden="true"
      class="absolute rounded-full pointer-events-none end-32 -bottom-36 size-56 border-[2rem] border-n-blue-7 opacity-10"
    />
    <div class="relative flex flex-col gap-6">
      <div class="flex flex-wrap items-start justify-between gap-4">
        <div class="flex flex-col max-w-4xl gap-2">
          <h1
            :id="tituloId"
            class="m-0 font-bold leading-tight tracking-tight text-white"
            :class="compacto ? 'text-3xl' : 'text-3xl md:text-[2.5rem]'"
          >
            {{ titulo }}
          </h1>
          <p
            v-if="texto"
            class="m-0 leading-relaxed text-white/80"
            :class="compacto ? 'text-base' : 'text-base md:text-lg'"
          >
            {{ texto }}
          </p>
          <slot name="detalhe" />
        </div>
        <slot name="acoes" />
      </div>
      <slot />
    </div>
  </section>
</template>
