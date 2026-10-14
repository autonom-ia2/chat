<script setup>
// #1423 — o card como aparece no quadro: faixa da cor da etapa, quem é o
// cliente, o negócio, quanto vale, a urgência e quem cuida. Muda enquanto a
// pessoa preenche.
defineProps({
  cor: { type: String, default: '#2563eb' },
  cliente: { type: String, required: true },
  titulo: { type: String, default: '' },
  valor: { type: String, default: '' },
  urgente: { type: Boolean, default: false },
  urgencia: { type: String, default: '' },
  atencao: { type: Number, default: 0 },
  quemCuida: { type: String, default: '' },
});
</script>

<template>
  <article
    data-card-previa-quadro
    class="relative overflow-hidden rounded-[1.25rem] border border-n-weak bg-n-solid-1 py-4 pe-4 ps-5 shadow-md"
  >
    <span
      class="absolute inset-y-0 start-0 w-1"
      :style="{ backgroundColor: cor }"
      aria-hidden="true"
    />
    <p
      class="mb-1 flex items-center gap-2 text-base font-semibold text-n-slate-12"
    >
      <span class="i-lucide-user-round size-4 shrink-0" aria-hidden="true" />
      <span class="min-w-0 truncate">{{ cliente }}</span>
    </p>
    <p v-if="titulo" class="mb-2 truncate text-sm text-n-slate-11">
      {{ titulo }}
    </p>
    <div class="flex flex-wrap gap-1.5">
      <span
        v-if="valor"
        class="rounded-lg bg-n-teal-3 px-2 py-0.5 text-xs font-medium text-n-teal-11"
      >
        {{ valor }}
      </span>
      <span
        v-if="urgencia"
        class="inline-flex items-center gap-1 rounded-lg px-2 py-0.5 text-xs font-medium"
        :class="
          urgente
            ? 'bg-n-ruby-3 text-n-ruby-11'
            : 'bg-n-alpha-2 text-n-slate-11'
        "
      >
        <span class="i-lucide-flag size-3" aria-hidden="true" />
        {{ urgencia }}
      </span>
      <span
        v-if="atencao"
        class="rounded-lg bg-n-blue-3 px-2 py-0.5 text-xs font-medium text-n-blue-11"
      >
        {{ $t('CRM_CARD.LADO.ATENCAO', { nota: atencao }) }}
      </span>
    </div>
    <p
      class="mb-0 mt-3 flex items-center gap-1.5 border-t border-n-weak pt-2.5 text-xs text-n-slate-11"
    >
      <span class="i-lucide-user-round size-3" aria-hidden="true" />
      {{ quemCuida || $t('CRM_KANBAN.CARD.NO_OWNER') }}
    </p>
  </article>
</template>
