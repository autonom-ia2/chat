<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import ListaDeLinhas from '../lista/ListaDeLinhas.vue';
import SegundaLinha from '../lista/SegundaLinha.vue';
import { segurosDeExemplo } from '../../carteira/segurosDeExemplo';
import { useTextosDoSeguro } from '../../carteira/useTextosDoSeguro';
import SelosDoSeguro from './SelosDoSeguro.vue';

// #2897 — conta sem seguro: abaixo do convite, a aba como ela vai ficar. Mesmo
// desenho das linhas de exemplo do bloco A (`LinhasDeExemplo`): apagadas, somem
// num degradê, nada se clica e o leitor de tela não lê (o convite já disse
// tudo).
const props = defineProps({
  agora: { type: Number, default: () => Date.now() },
});

const { t } = useI18n();
const textos = useTextosDoSeguro();

const linhas = computed(() =>
  segurosDeExemplo(props.agora).map(seguro => ({
    seguro,
    partes: [
      textos.tipo(seguro),
      seguro.seguradora,
      textos.quando(seguro, props.agora),
    ],
  }))
);
</script>

<template>
  <div
    data-carteira="seguros-de-exemplo"
    aria-hidden="true"
    class="flex flex-col gap-3 pointer-events-none select-none"
  >
    <p class="m-0 text-sm text-n-slate-11">
      {{ t('RELACIONAMENTOS_CARTEIRA.LISTA.EXEMPLO_LEGENDA') }}
    </p>
    <div class="relative overflow-hidden max-h-80">
      <ListaDeLinhas class="opacity-50">
        <li
          v-for="{ seguro, partes } in linhas"
          :key="seguro.id"
          data-linha-de-exemplo
          class="flex items-center min-w-0 gap-3 px-3 py-3 sm:px-5"
        >
          <Avatar :name="seguro.segurado.nome" :size="40" rounded-full />
          <div class="flex flex-col flex-1 min-w-0 gap-0.5">
            <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
              <span
                class="min-w-0 text-base font-semibold truncate text-n-slate-12"
              >
                {{ seguro.segurado.nome }}
              </span>
              <SelosDoSeguro :seguro="seguro" :agora="agora" />
            </div>
            <SegundaLinha :partes="partes" />
          </div>
        </li>
      </ListaDeLinhas>
      <div
        class="absolute inset-x-0 bottom-0 h-40 bg-gradient-to-t from-n-surface-1 to-transparent"
      />
    </div>
  </div>
</template>
