<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import SeloDeEstado from '../comum/SeloDeEstado.vue';
import ListaDeLinhas from './ListaDeLinhas.vue';
import SegundaLinha from './SegundaLinha.vue';
import { pessoasDeExemplo } from '../../lista/pessoasDeExemplo';
import { segundaLinhaDaPessoa } from '../../lista/segundaLinhaDaPessoa';

// #2894 — conta sem ninguém: abaixo do convite, a lista como ela vai ficar.
// É a receita do `EmptyStateLayout` da casa (linhas de exemplo apagadas, que
// somem num degradê), sem o título e o botão dele: o convite e a única ação da
// tela já estão no topo escuro. É só desenho — nada aqui se clica, e o leitor
// de tela não lê (o convite já disse tudo).
const props = defineProps({
  agora: { type: Number, default: () => Date.now() },
});

const { t } = useI18n();

const linhas = computed(() =>
  pessoasDeExemplo(props.agora).map(pessoa => ({
    id: pessoa.id,
    nome: pessoa.name,
    ehCliente: pessoa.contact_type === 'customer',
    partes: segundaLinhaDaPessoa(pessoa, props.agora, t),
  }))
);
</script>

<template>
  <div
    data-relacionamentos="linhas-de-exemplo"
    aria-hidden="true"
    class="flex flex-col gap-3 pointer-events-none select-none"
  >
    <p class="m-0 text-sm text-n-slate-11">
      {{ t('RELACIONAMENTOS.LISTA.EXEMPLO.LEGENDA') }}
    </p>
    <div class="relative overflow-hidden max-h-80">
      <ListaDeLinhas class="opacity-50">
        <li
          v-for="linha in linhas"
          :key="linha.id"
          data-linha-de-exemplo
          class="flex items-center min-w-0 gap-3 px-3 py-3 sm:px-5"
        >
          <Avatar :name="linha.nome" :size="40" rounded-full />
          <div class="flex flex-col flex-1 min-w-0 gap-0.5">
            <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
              <span
                class="min-w-0 text-base font-semibold truncate text-n-slate-12"
              >
                {{ linha.nome }}
              </span>
              <SeloDeEstado v-if="linha.ehCliente" tom="cliente">
                {{ t('RELACIONAMENTOS.COMUM.SELO_CLIENTE') }}
              </SeloDeEstado>
            </div>
            <SegundaLinha :partes="linha.partes" />
          </div>
        </li>
      </ListaDeLinhas>
      <div
        class="absolute inset-x-0 bottom-0 h-40 bg-gradient-to-t from-n-surface-1 to-transparent"
      />
    </div>
  </div>
</template>
