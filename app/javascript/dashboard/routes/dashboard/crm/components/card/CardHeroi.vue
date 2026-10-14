<script setup>
// #1423 — o cabeçalho escuro do card, na família do FunilHeroi (#1384):
// anéis, migalha (ou "voltar" nas telas internas), rótulo pequeno com ícone,
// título e uma frase. O X fecha a gaveta, sempre com 44 px.
import CustomerBadge from 'dashboard/components-next/customer-badge/CustomerBadge.vue';

defineProps({
  tituloId: { type: String, required: true },
  textoId: { type: String, required: true },
  rotulo: { type: String, required: true },
  icone: { type: String, default: 'i-lucide-user-round' },
  titulo: { type: String, required: true },
  texto: { type: String, default: '' },
  migalha: { type: Array, default: () => [] },
  voltar: { type: String, default: '' },
  // No resumo: o contato, para o selo "Cliente desde…" de quem já comprou.
  contato: { type: Object, default: null },
});

defineEmits(['voltar', 'fechar']);
</script>

<template>
  <header
    data-card-heroi
    class="relative shrink-0 overflow-hidden bg-[#0D2344] px-5 py-4 text-white sm:px-8"
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
          data-card-voltar
          class="-ms-2 inline-flex min-h-11 w-fit max-w-full items-center gap-2 rounded-xl px-2 text-sm font-medium text-white/75 transition hover:bg-white/10 hover:text-white focus-visible:outline focus-visible:outline-2 focus-visible:outline-white"
          @click="$emit('voltar')"
        >
          <span
            class="i-lucide-arrow-left size-4 shrink-0 rtl:rotate-180"
            aria-hidden="true"
          />
          <span class="truncate">{{ voltar }}</span>
        </button>
        <nav
          v-else
          data-card-migalha
          :aria-label="$t('CRM_CARD.MIGALHA')"
          class="flex min-h-7 min-w-0 items-center"
        >
          <ol
            class="m-0 flex min-w-0 list-none flex-wrap items-center gap-x-1.5 p-0 text-sm font-medium text-white/75"
          >
            <li
              v-for="(parte, indice) in migalha"
              :key="parte"
              class="flex min-w-0 items-center gap-1.5"
            >
              <span
                v-if="indice"
                class="i-lucide-chevron-right size-3.5 shrink-0 rtl:rotate-180"
                aria-hidden="true"
              />
              <span class="truncate">{{ parte }}</span>
            </li>
          </ol>
        </nav>
        <span
          class="inline-flex items-center gap-2 text-sm font-semibold text-n-blue-6 dark:text-n-blue-11"
        >
          <span class="size-4 shrink-0" :class="icone" aria-hidden="true" />
          {{ rotulo }}
          <CustomerBadge
            v-if="contato"
            :contact="contato"
            show-since
            data-heroi-cliente
          />
        </span>
        <h2
          :id="tituloId"
          data-card-titulo
          tabindex="-1"
          class="mb-0 break-words text-2xl font-bold leading-tight tracking-tight text-white outline-none"
        >
          {{ titulo }}
        </h2>
        <p
          v-if="texto"
          :id="textoId"
          class="mb-0 text-sm leading-relaxed text-white/75 sm:text-base"
        >
          {{ texto }}
        </p>
      </div>
      <button
        type="button"
        data-card-fechar
        :aria-label="$t('CRM_CARD.FECHAR')"
        class="grid size-11 shrink-0 place-items-center rounded-xl text-white/80 transition hover:bg-white/10 hover:text-white focus-visible:outline focus-visible:outline-2 focus-visible:outline-white"
        @click="$emit('fechar')"
      >
        <span class="i-lucide-x size-5" aria-hidden="true" />
      </button>
    </div>
  </header>
</template>
