<script setup>
import { computed } from 'vue';

// #1384 — a meta como aparece no painel de vendas. O número vendido é um
// exemplo, para a pessoa ver a barra andando.
const props = defineProps({
  venda: { type: Boolean, default: true },
  meta: { type: Number, default: 0 },
  sucesso: { type: String, default: '' },
  fracasso: { type: String, default: '' },
  dinheiro: { type: Function, required: true },
});

const PARTE_DO_EXEMPLO = 0.4;
const PORCENTO = Math.round(PARTE_DO_EXEMPLO * 100);
const vendido = computed(() => Math.round(props.meta * PARTE_DO_EXEMPLO));
</script>

<template>
  <div class="flex flex-col gap-4">
    <section
      v-if="venda && meta > 0"
      class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-5"
    >
      <span class="flex items-center gap-2 text-sm font-medium text-n-slate-11">
        <span class="i-lucide-target size-4" aria-hidden="true" />
        {{ $t('CRM_FUNIL.PREVIA.META_MES') }}
      </span>
      <span class="text-2xl font-bold text-n-slate-12">{{
        dinheiro(meta)
      }}</span>
      <span
        class="h-3 overflow-hidden rounded-full bg-n-slate-4 ring-1 ring-inset ring-n-slate-6"
        aria-hidden="true"
      >
        <span class="block h-full w-2/5 rounded-full bg-n-teal-9" />
      </span>
      <span
        class="flex flex-wrap items-center justify-between gap-2 text-sm text-n-slate-11"
      >
        <span>
          {{
            $t('CRM_FUNIL.PREVIA.META_EXEMPLO', { valor: dinheiro(vendido) })
          }}
        </span>
        <span class="font-semibold text-n-teal-11">
          {{ $t('CRM_FUNIL.PREVIA.META_PARTE', { n: PORCENTO }) }}
        </span>
      </span>
    </section>
    <!-- #1498: Atender não tem meta; a prévia mostra só como termina. -->
    <p
      v-else-if="venda"
      class="mb-0 rounded-2xl border border-dashed border-n-slate-6 p-5 text-[0.9375rem] text-n-slate-11"
    >
      {{ $t('CRM_FUNIL.PREVIA.SEM_META') }}
    </p>
    <section
      class="flex flex-col gap-2 rounded-2xl border border-n-weak bg-n-solid-1 p-5"
    >
      <span v-if="venda" class="text-sm font-medium text-n-slate-11">
        {{ $t('CRM_FUNIL.PREVIA.FIM') }}
      </span>
      <span class="flex flex-wrap gap-2">
        <span
          class="inline-flex items-center gap-1.5 rounded-lg bg-n-teal-3 px-2.5 py-1 text-sm font-medium text-n-teal-11"
        >
          <span class="i-lucide-check size-4" aria-hidden="true" />
          {{ sucesso }}
        </span>
        <span
          class="inline-flex items-center gap-1.5 rounded-lg bg-n-ruby-3 px-2.5 py-1 text-sm font-medium text-n-ruby-11"
        >
          <span class="i-lucide-x size-4" aria-hidden="true" />
          {{ fracasso }}
        </span>
      </span>
    </section>
  </div>
</template>
