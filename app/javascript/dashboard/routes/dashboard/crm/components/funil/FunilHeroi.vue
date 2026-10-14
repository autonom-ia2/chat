<script setup>
// #1384 — o cabeçalho escuro da gaveta, no padrão do herói de Automações:
// anéis decorativos, migalha, rótulo pequeno com ícone, título e uma frase.
// A anatomia e a altura são as mesmas em toda tela: nas telas internas a
// migalha volta; nas de cima, ela só diz onde a pessoa está.
defineProps({
  rotulo: { type: String, required: true },
  icone: { type: String, default: 'i-lucide-kanban' },
  titulo: { type: String, required: true },
  texto: { type: String, default: '' },
  voltar: { type: String, default: '' },
  migalha: { type: String, default: '' },
});

defineEmits(['voltar', 'fechar']);
</script>

<template>
  <header
    data-funil-heroi
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
          v-if="voltar"
          type="button"
          data-funil-voltar
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
          v-else
          data-funil-migalha
          class="inline-flex min-h-11 items-center text-sm font-medium text-white/75"
        >
          {{ migalha }}
        </span>
        <span
          class="inline-flex items-center gap-2 text-sm font-semibold text-n-blue-6 dark:text-n-blue-11"
        >
          <span class="size-4" :class="icone" aria-hidden="true" />
          {{ rotulo }}
        </span>
        <h2
          id="crm-pipeline-drawer-title"
          data-view-title
          tabindex="-1"
          class="mb-0 text-2xl font-bold leading-tight tracking-tight text-white outline-none"
        >
          {{ titulo }}
        </h2>
        <p
          v-if="texto"
          class="mb-0 text-sm leading-relaxed text-white/75 sm:text-base"
        >
          {{ texto }}
        </p>
      </div>
      <button
        type="button"
        data-funil-fechar
        :aria-label="$t('CRM_FUNIL.FECHAR')"
        class="grid size-11 shrink-0 place-items-center rounded-xl text-white/80 transition hover:bg-white/10 hover:text-white focus-visible:outline focus-visible:outline-2 focus-visible:outline-white"
        @click="$emit('fechar')"
      >
        <span class="i-lucide-x size-5" aria-hidden="true" />
      </button>
    </div>
  </header>
</template>
