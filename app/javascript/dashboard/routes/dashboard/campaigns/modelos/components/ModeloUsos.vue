<script setup>
// Onde o modelo está em uso (campanhas, avisos do agendamento, follow-ups do
// CRM, Anúncios, pesquisa de satisfação), cada um com o link para resolver.
// Aparece antes de alterar ou apagar, para a pessoa saber o que muda.
defineProps({
  usos: { type: Array, required: true },
  semMoldura: { type: Boolean, default: false },
  semTitulo: { type: Boolean, default: false },
});

const ICONES = {
  campanha: 'i-lucide-megaphone',
  agendamento: 'i-lucide-calendar-clock',
  crm: 'i-lucide-kanban',
  anuncios: 'i-lucide-chart-no-axes-column',
  satisfacao: 'i-lucide-star',
};
</script>

<template>
  <section
    data-usos
    class="flex flex-col gap-3"
    :class="
      semMoldura
        ? ''
        : 'p-6 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1'
    "
  >
    <h3 v-if="!semTitulo" class="m-0 text-base font-semibold text-n-slate-12">
      {{ $t('MODELOS_WHATSAPP.USOS.TITULO') }}
    </h3>
    <p v-if="!usos.length" class="mb-0 text-[0.9375rem] text-n-slate-11">
      {{ $t('MODELOS_WHATSAPP.USOS.NENHUM') }}
    </p>
    <ul v-else class="flex flex-col gap-2 p-0 m-0 list-none">
      <li
        v-for="(uso, indice) in usos"
        :key="indice"
        :data-uso="uso.tipo"
        class="flex items-center gap-3 text-[0.9375rem] text-n-slate-12"
      >
        <span
          class="grid place-items-center size-9 shrink-0 rounded-lg bg-n-slate-3 text-n-slate-11"
        >
          <span class="size-4" :class="ICONES[uso.tipo]" aria-hidden="true" />
        </span>
        <span class="flex flex-col flex-1 min-w-0">
          <span class="text-sm text-n-slate-10">
            {{ $t(`MODELOS_WHATSAPP.USOS.TIPOS.${uso.tipo}`) }}
            <template v-if="uso.quando"> · {{ uso.quando }}</template>
          </span>
          <span class="break-words">{{ uso.nome }}</span>
        </span>
        <router-link
          v-if="uso.rota"
          :to="uso.rota"
          class="inline-flex items-center gap-1 px-2 text-sm font-medium rounded-lg shrink-0 min-h-11 text-n-blue-11 hover:underline"
        >
          {{ $t('MODELOS_WHATSAPP.USOS.ABRIR') }}
          <span class="i-lucide-arrow-right size-4 rtl:rotate-180" aria-hidden="true" />
        </router-link>
      </li>
    </ul>
  </section>
</template>
