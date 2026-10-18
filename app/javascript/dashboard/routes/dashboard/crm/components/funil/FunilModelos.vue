<script setup>
// #1384 — "Começar pronto": cada modelo é um cartão grande com ícone, nome e
// o caminho do cliente. O escolhido ganha a borda azul e o visto.
// #1498 — só os modelos do tipo escolhido (Atender tem quatro).
// #1802 — a corretora também escolhe entre dois de Vender: a pergunta segue o
// tipo.
defineProps({
  tipo: { type: String, default: '' },
  modelo: { type: String, required: true },
  modelos: { type: Array, required: true },
});

defineEmits(['escolher']);
</script>

<template>
  <section class="flex flex-col gap-3">
    <h3
      id="funil-modelos-titulo"
      class="mb-0 text-base font-semibold text-n-slate-12"
    >
      {{
        tipo === 'VENDER'
          ? $t('CRM_FUNIL.TIPO.MODELO_VENDER')
          : $t('CRM_FUNIL.TIPO.MODELO')
      }}
    </h3>
    <div
      class="grid gap-3 sm:grid-cols-2"
      role="group"
      aria-labelledby="funil-modelos-titulo"
    >
      <button
        v-for="item in modelos"
        :key="item.chave"
        type="button"
        :data-modelo="item.chave"
        :aria-pressed="modelo === item.chave"
        class="relative flex min-h-11 items-center gap-3 rounded-2xl border-2 p-4 text-start transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
        :class="
          modelo === item.chave
            ? 'border-n-blue-9 bg-n-blue-2'
            : 'border-n-slate-5 bg-n-solid-1 shadow-sm hover:border-n-slate-8'
        "
        @click="$emit('escolher', item.chave)"
      >
        <span
          class="grid size-11 shrink-0 place-items-center rounded-xl"
          :class="item.tom"
          aria-hidden="true"
        >
          <span class="size-5" :class="item.icone" />
        </span>
        <span class="flex min-w-0 flex-1 flex-col gap-0.5">
          <span class="text-base font-semibold text-n-slate-12">
            {{ $t(`CRM_FUNIL.MODELOS.${item.chave}.NOME`) }}
          </span>
          <span class="text-sm text-n-slate-11">
            {{ $t(`CRM_FUNIL.MODELOS.${item.chave}.TEXTO`) }}
          </span>
        </span>
        <span
          v-if="modelo === item.chave"
          class="grid size-6 shrink-0 place-items-center rounded-full bg-n-blue-9 text-white"
          aria-hidden="true"
        >
          <span class="i-lucide-check size-4" />
        </span>
      </button>
    </div>
  </section>
</template>
