<script setup>
// #2692 — o herói escuro da porta (v4, T0). Molde visual de
// automacoes/components/AutomacaoHeroi.vue (bg-[#0D2344] e os dois anéis), sem
// o rótulo em caixa alta. O conteúdo (o cartão branco) vem pelo slot.
defineProps({
  titulo: { type: String, required: true },
});
</script>

<template>
  <section
    class="relative px-4 py-8 overflow-hidden text-white rounded-3xl bg-[#0D2344] md:px-12 md:py-12"
    data-heroi
  >
    <span
      aria-hidden="true"
      class="absolute rounded-full pointer-events-none -end-16 -top-24 size-80 border-[3rem] border-n-blue-9 opacity-15"
    />
    <span
      aria-hidden="true"
      class="absolute rounded-full pointer-events-none end-32 -bottom-36 size-56 border-[2rem] border-n-blue-7 opacity-10"
    />
    <div class="relative flex flex-col gap-6 mx-auto max-w-3xl">
      <h1
        class="m-0 text-2xl font-bold leading-tight tracking-tight text-white md:text-[2.5rem]"
      >
        {{ titulo }}
      </h1>
      <slot />
    </div>
  </section>
</template>
