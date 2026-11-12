<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import EsqueletoDeLista from '../comum/EsqueletoDeLista.vue';
import ErroComTentarDeNovo from '../comum/ErroComTentarDeNovo.vue';
import { SITUACOES_DA_LISTA, formatarDia } from '../../trazer/prazo';
import { PONTO } from '../comum/ponto';

// #2894 — "O que eu já trouxe": arquivo, quando, quem, quantas pessoas, a
// situação e o Desfazer (sem prazo). Vazio é uma frase, sem botão.
// #2896 — a lista que parou no meio diz que não foi trazida e, quando dá para
// continuar (`podeTentar`), oferece "Tentar de novo"; sem isso, só a frase.
// O Desfazer só aparece quando a conta tem (`temDesfazer`, que vem da fonte) e
// o servidor diz que aquela lista pode ser desfeita (`podeDesfazer`), seja qual
// for a situação: a pronta; a que parou no meio depois de pôr gente (aí ao lado
// do "Tentar de novo": a pessoa escolhe); e a que teve o desfazer travado.
// A lista que está sendo desfeita diz "Desfazendo…", com o selo de lista em
// andamento. Na linha, a frase e os botões quebram de linha quando não cabem.
// Os dois botões da linha têm 44 px de altura (alvo de toque).
// O desfazer que travou (`desfazendo` com `podeDesfazer`) diz que parou e manda
// clicar em Desfazer; sem o botão, a frase não aparece.
// O selo é anunciado pelo leitor de tela quando muda ("Desfazendo…" para
// "Desfeito"), menos o da lista que está entrando: a porcentagem dela muda a
// cada consulta. E a linha aceita o foco (`tabindex="-1"`): é para ela que a
// tela leva o foco depois de desfazer, quando o botão clicado some.
defineProps({
  listas: { type: Array, required: true },
  temDesfazer: { type: Boolean, default: false },
  carregando: { type: Boolean, default: false },
  comErro: { type: Boolean, default: false },
  // O id da lista que está tentando de novo agora (o botão dela fica ocupado).
  tentando: { type: [String, Number], default: null },
});
const emit = defineEmits(['desfazer', 'tentar', 'tentarDeNovo']);

const { t, locale } = useI18n();

const SELOS = {
  [SITUACOES_DA_LISTA.PRONTO]: 'bg-n-teal-3 text-n-teal-11',
  [SITUACOES_DA_LISTA.TRAZENDO]: 'bg-n-blue-3 text-n-blue-11',
  [SITUACOES_DA_LISTA.DESFAZENDO]: 'bg-n-blue-3 text-n-blue-11',
  [SITUACOES_DA_LISTA.DESFEITO]: 'bg-n-alpha-2 text-n-slate-11',
};
const dia = ms => formatarDia(ms, locale.value);
const anuncio = lista =>
  lista.situacao === SITUACOES_DA_LISTA.TRAZENDO ? 'off' : 'polite';
const desfazerParou = lista =>
  lista.situacao === SITUACOES_DA_LISTA.DESFAZENDO && lista.podeDesfazer;

const NOMES = {
  [SITUACOES_DA_LISTA.PRONTO]:
    'RELACIONAMENTOS_TRAZER.HISTORICO.SITUACAO.PRONTO',
  [SITUACOES_DA_LISTA.TRAZENDO]:
    'RELACIONAMENTOS_TRAZER.HISTORICO.SITUACAO.TRAZENDO',
  [SITUACOES_DA_LISTA.DESFAZENDO]:
    'RELACIONAMENTOS_TRAZER.HISTORICO.SITUACAO.DESFAZENDO',
  [SITUACOES_DA_LISTA.DESFEITO]:
    'RELACIONAMENTOS_TRAZER.HISTORICO.SITUACAO.DESFEITO',
};
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
        tabindex="-1"
        class="flex flex-col gap-4 p-5 border rounded-2xl border-n-weak bg-n-solid-1 sm:flex-row sm:items-center sm:justify-between focus:outline-none focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
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
            {{ PONTO }}
            <template v-if="lista.quem">
              {{
                t('RELACIONAMENTOS_TRAZER.HISTORICO.POR', { nome: lista.quem })
              }}
              {{ PONTO }}
            </template>
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
          <p
            v-if="lista.situacao === SITUACOES_DA_LISTA.FALHOU"
            :data-situacao="lista.situacao"
            class="m-0 text-sm font-medium text-n-ruby-11"
          >
            {{ t('RELACIONAMENTOS_TRAZER.HISTORICO.FALHOU') }}
          </p>
          <span
            v-else
            :data-situacao="lista.situacao"
            :aria-live="anuncio(lista)"
            class="px-3 py-1 text-sm font-medium rounded-full tabular-nums"
            :class="SELOS[lista.situacao]"
          >
            {{ t(NOMES[lista.situacao], { porcentagem: lista.porcentagem }) }}
          </span>
          <p
            v-if="temDesfazer && desfazerParou(lista)"
            data-relacionamentos="desfazer-parou"
            class="m-0 text-sm text-n-slate-11"
          >
            {{ t('RELACIONAMENTOS_TRAZER.HISTORICO.DESFAZER_PAROU') }}
          </p>
          <Button
            v-if="
              lista.situacao === SITUACOES_DA_LISTA.FALHOU && lista.podeTentar
            "
            slate
            faded
            class="min-h-11"
            data-relacionamentos="tentar-de-novo"
            :label="t('RELACIONAMENTOS.COMUM.TENTAR_DE_NOVO')"
            :aria-label="
              t('RELACIONAMENTOS_TRAZER.HISTORICO.ROTULO_TENTAR', {
                arquivo: lista.arquivo,
              })
            "
            :is-loading="tentando === lista.id"
            :disabled="tentando === lista.id"
            @click="emit('tentarDeNovo', lista)"
          />
          <Button
            v-if="temDesfazer && lista.podeDesfazer"
            slate
            faded
            class="min-h-11"
            data-relacionamentos="desfazer"
            :label="t('RELACIONAMENTOS_TRAZER.HISTORICO.DESFAZER')"
            :aria-label="
              t('RELACIONAMENTOS_TRAZER.HISTORICO.ROTULO_DESFAZER', {
                arquivo: lista.arquivo,
              })
            "
            @click="emit('desfazer', lista)"
          />
        </div>
      </li>
    </ul>
  </section>
</template>
