<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import EsqueletoDeLista from '../comum/EsqueletoDeLista.vue';
import ErroComTentarDeNovo from '../comum/ErroComTentarDeNovo.vue';
import { SITUACOES_DA_LISTA, formatarDia } from '../../trazer/prazo';
import { SEPARADOR } from '../comum/ponto';

// #2894 — "O que eu já trouxe": arquivo, quando, quem, quantas pessoas, a
// situação e o Desfazer (sem prazo). Vazio é uma frase, sem botão.
// #2896 — a lista que parou no meio diz que não foi trazida e, quando dá para
// continuar (`podeTentar`), oferece "Tentar de novo"; sem isso, só a frase.
// O Desfazer só aparece quando a conta tem (`temDesfazer`, que vem da fonte) e
// o servidor diz que aquela lista pode ser desfeita (`podeDesfazer`), seja qual
// for a situação: a pronta; a que parou no meio depois de pôr gente (aí ao lado
// do "Tentar de novo": a pessoa escolhe); e a que teve o desfazer travado.
// A lista que está sendo desfeita diz "Desfazendo…", com o selo de lista em
// andamento. Os dois botões da linha têm 44 px de altura (alvo de toque).
// A linha tem dois blocos. O da esquerda ocupa o espaço que sobra e tem até
// três linhas: o arquivo; "em 12/11 · por Fulano · 2 pessoas", montada aqui no
// script (no template o espaço depois do ponto se perdia); e, quando há, a
// frase do problema. O da direita não encolhe o da esquerda e tem só o selo e
// os botões, que quebram de linha quando não cabem.
// A frase do problema é uma de duas: a lista que não foi trazida, em vermelho;
// ou o desfazer que travou (`desfazendo` com `podeDesfazer`), "O desfazer parou
// no meio.". Nesse caso o selo "Desfazendo…" sai (não há nada acontecendo) e o
// botão vira "Continuar", em azul, como o "Tentar de novo": é a ação principal
// da linha. Sem o Desfazer na conta, a lista travada fica só com o selo.
// O selo é anunciado pelo leitor de tela quando muda ("Desfazendo…" para
// "Desfeito"), menos o da lista que está entrando: a porcentagem dela muda a
// cada consulta. E a linha aceita o foco (`tabindex="-1"`): é para ela que a
// tela leva o foco depois de desfazer, quando o botão clicado some.
const props = defineProps({
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
const falhou = lista => lista.situacao === SITUACOES_DA_LISTA.FALHOU;
const podeDesfazer = lista => props.temDesfazer && Boolean(lista.podeDesfazer);
const desfazerParou = lista =>
  lista.situacao === SITUACOES_DA_LISTA.DESFAZENDO && podeDesfazer(lista);
const temSelo = lista => !falhou(lista) && !desfazerParou(lista);
const podeTentarDeNovo = lista => falhou(lista) && Boolean(lista.podeTentar);
const temBotao = lista => podeTentarDeNovo(lista) || podeDesfazer(lista);

// "em 12/11 · por Fulano · 2 pessoas"; sem quem trouxe, "em 12/11 · 2 pessoas".
const quandoQuemQuantas = lista =>
  [
    t('RELACIONAMENTOS_TRAZER.HISTORICO.EM', { data: dia(lista.quando) }),
    lista.quem
      ? t('RELACIONAMENTOS_TRAZER.HISTORICO.POR', { nome: lista.quem })
      : '',
    t(
      'RELACIONAMENTOS_TRAZER.HISTORICO.PESSOAS',
      { count: lista.total },
      lista.total
    ),
  ]
    .filter(Boolean)
    .join(SEPARADOR);

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
        <div class="flex flex-col flex-1 min-w-0 gap-1">
          <p class="m-0 text-base font-medium truncate text-n-slate-12">
            {{ lista.arquivo }}
          </p>
          <p class="m-0 text-sm text-n-slate-11 tabular-nums">
            {{ quandoQuemQuantas(lista) }}
          </p>
          <p
            v-if="falhou(lista)"
            :data-situacao="lista.situacao"
            class="m-0 text-sm font-medium text-n-ruby-11"
          >
            {{ t('RELACIONAMENTOS_TRAZER.HISTORICO.FALHOU') }}
          </p>
          <p
            v-else-if="desfazerParou(lista)"
            data-relacionamentos="desfazer-parou"
            :data-situacao="lista.situacao"
            aria-live="polite"
            class="m-0 text-sm font-medium text-n-amber-11"
          >
            {{ t('RELACIONAMENTOS_TRAZER.HISTORICO.DESFAZER_PAROU') }}
          </p>
        </div>
        <div
          v-if="temSelo(lista) || temBotao(lista)"
          class="flex flex-wrap items-center gap-3 shrink-0 sm:justify-end"
        >
          <span
            v-if="temSelo(lista)"
            :data-situacao="lista.situacao"
            :aria-live="anuncio(lista)"
            class="px-3 py-1 text-sm font-medium rounded-full tabular-nums"
            :class="SELOS[lista.situacao]"
          >
            {{ t(NOMES[lista.situacao], { porcentagem: lista.porcentagem }) }}
          </span>
          <Button
            v-if="podeTentarDeNovo(lista)"
            blue
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
            v-if="desfazerParou(lista)"
            blue
            faded
            class="min-h-11"
            data-relacionamentos="desfazer"
            :label="t('RELACIONAMENTOS_TRAZER.HISTORICO.CONTINUAR')"
            :aria-label="
              t('RELACIONAMENTOS_TRAZER.HISTORICO.ROTULO_CONTINUAR', {
                arquivo: lista.arquivo,
              })
            "
            @click="emit('desfazer', lista)"
          />
          <Button
            v-else-if="podeDesfazer(lista)"
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
