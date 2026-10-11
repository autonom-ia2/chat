<script setup>
// Tela de recado (pausada, link inválido, erro, já agendado): título, uma frase e as saídas no slot.
defineProps({
  title: { type: String, required: true },
  body: { type: String, default: '' },
  icon: { type: String, default: 'i-lucide-calendar-x' },
});
defineSlots();
</script>

<template>
  <section
    class="flex flex-col items-center gap-4 text-center"
    aria-labelledby="step-heading"
  >
    <span
      aria-hidden="true"
      class="flex size-14 items-center justify-center rounded-full bg-bk-chip text-2xl text-bk-soft"
    >
      <span :class="icon" />
    </span>
    <h1
      id="step-heading"
      data-step-heading
      tabindex="-1"
      class="text-2xl font-bold text-bk-strong focus:outline-none"
    >
      {{ title }}
    </h1>
    <p v-if="body" class="text-base text-bk-medium">{{ body }}</p>
    <div class="flex w-full flex-col gap-3">
      <slot />
    </div>
  </section>
</template>
