<script setup>
import { computed } from 'vue';
import { useMenuNovo } from './useMenuNovo';
import { usePodeAbrir } from './usePodeAbrir';

// "Gerenciado em Atribuição" (#1617): na aba Agentes da caixa e no formulário de Times, uma linha leva ao lugar
// dono de quem recebe cada conversa. Só com o menu novo e para quem pode abrir Atribuição.
const { ligado } = useMenuNovo();
const { podeAbrir } = usePodeAbrir();

const destino = { name: 'assignment_policy_index' };
const visivel = computed(() => ligado.value && podeAbrir(destino));
</script>

<template>
  <p
    v-if="visivel"
    data-gerenciado-em-atribuicao
    class="flex flex-wrap items-center gap-x-2 mt-3 mb-0 text-sm text-n-slate-11"
  >
    <span class="i-lucide-info size-4 shrink-0" aria-hidden="true" />
    <span>{{ $t('FORK_SIDEBAR.ATRIBUICAO.TEXTO') }}</span>
    <RouterLink
      :to="destino"
      class="inline-flex items-center gap-1 font-medium min-h-11 text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand rounded"
    >
      {{ $t('FORK_SIDEBAR.ATRIBUICAO.LINK') }}
      <span
        class="i-lucide-arrow-right size-4 rtl:rotate-180"
        aria-hidden="true"
      />
    </RouterLink>
  </p>
  <template v-else />
</template>
