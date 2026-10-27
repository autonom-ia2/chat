<script setup>
import { computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { useFormatoDoPainel } from '../../../composables/useFormatoDoPainel';
import { TAMANHOS_DE_PAGINA } from '../../../utils/desempenhoDetalhe';

// #2226 v2 — "1–25 de 231", Anterior/Próxima e quantas linhas por página.
const props = defineProps({
  // Resultado de paginar(): { pagina, paginas, total, de, ate }
  pagina: { type: Object, required: true },
  tamanho: { type: Number, required: true },
});

const emit = defineEmits(['update:pagina', 'update:tamanho']);
const { t, n } = useFormatoDoPainel();
const B = 'AGENTS.DESEMPENHO2.B.PAGINACAO';

const opcoesDoTamanho = computed(() =>
  TAMANHOS_DE_PAGINA.map(valor => ({
    value: valor,
    label: t(`${B}.POR_PAGINA`, { n: valor }),
  }))
);
const tamanhoEscolhido = computed({
  get: () => props.tamanho,
  set: valor => emit('update:tamanho', Number(valor)),
});
</script>

<template>
  <nav
    class="flex flex-wrap items-center justify-between gap-3"
    :aria-label="t(`${B}.ROTULO`)"
  >
    <p class="text-sm text-n-slate-11 tabular-nums" aria-live="polite">
      {{
        t(`${B}.FAIXA`, {
          de: n(pagina.de),
          ate: n(pagina.ate),
          total: n(pagina.total),
        })
      }}
    </p>
    <div class="flex items-center gap-2">
      <ChoiceSelect
        v-model="tamanhoEscolhido"
        compact
        :options="opcoesDoTamanho"
        :aria-label="t(`${B}.TAMANHO`)"
      />
      <Button
        size="sm"
        variant="faded"
        color="slate"
        icon="i-lucide-chevron-left"
        class="min-h-11"
        :label="t(`${B}.ANTERIOR`)"
        :disabled="pagina.pagina <= 1"
        data-anterior
        @click="emit('update:pagina', pagina.pagina - 1)"
      />
      <Button
        size="sm"
        variant="faded"
        color="slate"
        icon="i-lucide-chevron-right"
        trailing-icon
        class="min-h-11"
        :label="t(`${B}.PROXIMA`)"
        :disabled="pagina.pagina >= pagina.paginas"
        data-proxima
        @click="emit('update:pagina', pagina.pagina + 1)"
      />
    </div>
  </nav>
</template>
