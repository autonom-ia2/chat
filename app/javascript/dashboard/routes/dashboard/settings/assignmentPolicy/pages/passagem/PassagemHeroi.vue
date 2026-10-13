<script setup>
// #1385 — o cabeçalho escuro, da mesma família do funil (#1384) e de Automações: anéis, migalha que volta,
// rótulo pequeno com ícone, título que diz o benefício, uma frase e o X de fechar no canto. Não usa o FunilHeroi
// (#1384) porque aquele é o cabeçalho de uma gaveta (h2 com o id da gaveta); aqui é o título da página (h1).
defineProps({
  voltar: { type: String, required: true },
  rotulo: { type: String, required: true },
  icone: { type: String, default: 'i-lucide-user-round-check' },
  titulo: { type: String, required: true },
  texto: { type: String, default: '' },
});

defineEmits(['voltar', 'fechar']);
</script>

<template>
  <header
    data-passagem-heroi
    class="relative shrink-0 overflow-hidden bg-[#0D2344] px-5 py-5 text-white sm:px-8"
  >
    <span
      aria-hidden="true"
      class="pointer-events-none absolute -end-16 -top-24 size-80 rounded-full border-[3rem] border-n-blue-9 opacity-15"
    />
    <span
      aria-hidden="true"
      class="pointer-events-none absolute -bottom-36 end-32 size-56 rounded-full border-[2rem] border-n-blue-7 opacity-10"
    />
    <div class="relative flex items-start gap-4">
      <div class="flex min-w-0 flex-1 flex-col gap-1.5">
        <button
          type="button"
          data-passagem-voltar
          class="-ms-2 inline-flex min-h-11 w-fit items-center gap-2 rounded-xl px-2 text-sm font-medium text-white/75 transition hover:bg-white/10 hover:text-white focus-visible:outline focus-visible:outline-2 focus-visible:outline-white"
          @click="$emit('voltar')"
        >
          <span
            class="i-lucide-arrow-left size-4 rtl:rotate-180"
            aria-hidden="true"
          />
          {{ voltar }}
        </button>
        <span
          class="inline-flex items-center gap-2 text-sm font-semibold text-n-blue-6"
        >
          <span class="size-4" :class="icone" aria-hidden="true" />
          {{ rotulo }}
        </span>
        <h1
          data-view-title
          tabindex="-1"
          class="mb-0 text-2xl font-bold leading-tight tracking-tight text-white outline-none"
        >
          {{ titulo }}
        </h1>
        <p
          v-if="texto"
          class="mb-0 text-sm leading-relaxed text-white/75 sm:text-base"
        >
          {{ texto }}
        </p>
      </div>
      <button
        type="button"
        data-passagem-fechar
        :aria-label="$t('CRM_KANBAN.PASSAGEM.HEROI.FECHAR')"
        class="grid size-11 shrink-0 place-items-center rounded-xl text-white/80 transition hover:bg-white/10 hover:text-white focus-visible:outline focus-visible:outline-2 focus-visible:outline-white"
        @click="$emit('fechar')"
      >
        <span class="i-lucide-x size-5" aria-hidden="true" />
      </button>
    </div>
  </header>
</template>
