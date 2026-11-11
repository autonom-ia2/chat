<script setup>
// #2894 — o herói escuro das telas de Relacionamentos: uma frase, uma ação
// principal (com uma linha de apoio opcional entre as duas). Ação discreta, se
// houver, vai no mesmo slot, ao lado da principal. Mesmo desenho do herói de
// Automações e do Resumo de hoje (token bg-n-heroi).
</script>

<template>
  <section
    data-relacionamentos-heroi
    class="relative px-6 py-10 overflow-hidden text-white shadow-xl rounded-3xl bg-n-heroi ring-1 ring-inset ring-white/10 dark:bg-n-heroi-escuro md:px-12 md:py-12"
  >
    <span
      aria-hidden="true"
      class="absolute rounded-full pointer-events-none -end-16 -top-24 size-80 border-[3rem] border-n-blue-9 opacity-15"
    />
    <span
      aria-hidden="true"
      class="absolute rounded-full pointer-events-none end-32 -bottom-36 size-56 border-[2rem] border-n-blue-7 opacity-10"
    />
    <div class="relative flex flex-col max-w-4xl gap-6">
      <p
        data-heroi-frase
        class="m-0 text-3xl font-bold leading-tight tracking-tight text-white md:text-4xl"
      >
        <slot name="frase" />
      </p>
      <p
        v-if="$slots.apoio"
        data-heroi-apoio
        class="m-0 -mt-3 text-base text-white/80 md:text-lg"
      >
        <slot name="apoio" />
      </p>
      <div v-if="$slots.acao" data-heroi-acao class="flex flex-wrap gap-3">
        <slot name="acao" />
      </div>
    </div>
  </section>
</template>
