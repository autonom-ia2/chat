<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import EsqueletoDeLista from '../comum/EsqueletoDeLista.vue';
import ErroComTentarDeNovo from '../comum/ErroComTentarDeNovo.vue';
import {
  PRAZO,
  SITUACOES_DA_LISTA,
  formatarDia,
  prazoParaDesfazer,
} from '../../trazer/prazo';

// #2894 — "O que eu já trouxe": arquivo, quando, quem, quantas pessoas, a
// situação e o Desfazer com o prazo. Vazio é uma frase, sem botão.
defineProps({
  listas: { type: Array, required: true },
  carregando: { type: Boolean, default: false },
  comErro: { type: Boolean, default: false },
  prazoDe: { type: Function, required: true },
});
const emit = defineEmits(['desfazer', 'tentar']);

const { t, locale } = useI18n();

const SELOS = {
  [SITUACOES_DA_LISTA.PRONTO]: 'bg-n-teal-3 text-n-teal-11',
  [SITUACOES_DA_LISTA.TRAZENDO]: 'bg-n-blue-3 text-n-blue-11',
  [SITUACOES_DA_LISTA.DESFEITO]: 'bg-n-alpha-2 text-n-slate-11',
};
const NOMES = {
  [SITUACOES_DA_LISTA.PRONTO]:
    'RELACIONAMENTOS_TRAZER.HISTORICO.SITUACAO.PRONTO',
  [SITUACOES_DA_LISTA.TRAZENDO]:
    'RELACIONAMENTOS_TRAZER.HISTORICO.SITUACAO.TRAZENDO',
  [SITUACOES_DA_LISTA.DESFEITO]:
    'RELACIONAMENTOS_TRAZER.HISTORICO.SITUACAO.DESFEITO',
};

const dia = ms => formatarDia(ms, locale.value);
</script>

<template>
  <section data-relacionamentos="historico" class="flex flex-col gap-4">
    <h2 class="m-0 text-2xl font-semibold tracking-tight text-n-slate-12">
      {{ t('RELACIONAMENTOS_TRAZER.HISTORICO.TITULO') }}
    </h2>

    <div v-if="carregando" data-relacionamentos="carregando">
      <EsqueletoDeLista :linhas="2" />
    </div>
    <div v-else-if="comErro" data-relacionamentos="erro">
      <ErroComTentarDeNovo
        :mensagem="t('RELACIONAMENTOS_TRAZER.ERROS.HISTORICO')"
        @tentar="emit('tentar')"
      />
    </div>
    <p
      v-else-if="!listas.length"
      data-relacionamentos="vazio"
      class="m-0 text-base text-n-slate-11"
    >
      {{ t('RELACIONAMENTOS_TRAZER.HISTORICO.VAZIO') }}
    </p>
    <ul v-else class="flex flex-col gap-3 p-0 m-0 list-none">
      <li
        v-for="lista in listas"
        :key="lista.id"
        :data-lista="lista.id"
        class="flex flex-col gap-4 p-5 border rounded-2xl border-n-weak bg-n-solid-1 sm:flex-row sm:items-center sm:justify-between"
      >
        <div class="flex flex-col min-w-0 gap-1">
          <p class="m-0 text-base font-medium truncate text-n-slate-12">
            {{ lista.arquivo }}
          </p>
          <p class="m-0 text-sm text-n-slate-11">
            {{
              t('RELACIONAMENTOS_TRAZER.HISTORICO.EM', {
                data: dia(lista.quando),
              })
            }}
            ·
            {{
              t('RELACIONAMENTOS_TRAZER.HISTORICO.POR', { nome: lista.quem })
            }}
            ·
            <span class="tabular-nums">
              {{
                t(
                  'RELACIONAMENTOS_TRAZER.HISTORICO.PESSOAS',
                  { count: lista.total },
                  lista.total
                )
              }}
            </span>
          </p>
        </div>
        <div class="flex flex-wrap items-center gap-3 sm:justify-end">
          <span
            :data-situacao="lista.situacao"
            class="px-3 py-1 text-sm font-medium rounded-full tabular-nums"
            :class="SELOS[lista.situacao]"
          >
            {{ t(NOMES[lista.situacao], { porcentagem: lista.porcentagem }) }}
          </span>
          <template v-if="prazoDe(lista) === PRAZO.ABERTO">
            <div class="flex flex-col items-center gap-1">
              <Button
                slate
                faded
                data-relacionamentos="desfazer"
                class="min-h-11"
                :label="t('RELACIONAMENTOS_TRAZER.HISTORICO.DESFAZER')"
                :aria-label="
                  t('RELACIONAMENTOS_TRAZER.HISTORICO.ROTULO_DESFAZER', {
                    arquivo: lista.arquivo,
                  })
                "
                @click="emit('desfazer', lista)"
              />
              <span class="text-xs text-n-slate-11">
                {{
                  t('RELACIONAMENTOS_TRAZER.HISTORICO.ATE', {
                    data: dia(prazoParaDesfazer(lista.quando)),
                  })
                }}
              </span>
            </div>
          </template>
          <span
            v-else-if="prazoDe(lista) === PRAZO.ACABOU"
            class="text-sm text-n-slate-11"
          >
            {{ t('RELACIONAMENTOS_TRAZER.HISTORICO.PRAZO_ACABOU') }}
          </span>
        </div>
      </li>
    </ul>
  </section>
</template>
