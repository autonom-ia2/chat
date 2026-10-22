<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { idiomaDoNavegador } from '../../utils/pagina';

// #1181 PR3 (protótipo T07, kpiT07) — os números da semana na página do agente: dois cartões claros
// iguais (conversas respondidas e passadas para a equipe), lidos da mesma L1 da lista, filtrada por
// este agente (DECISOES.md item 2), para os números nunca divergirem. Sem percentual nem nota.
// - `numeros` null (a L1 falhou ou ainda não chegou): a linha inteira some (t07-semnumeros).
// - zero e zero: um aviso de que os números aparecem quando o agente responder (t07-semconversas).
// - `podeAbrir`: cada cartão vira botão e abre as conversas da semana (t07-conversas).
// #2000 — três cartões, da conta única da IA (a mesma da linha da IA em CRM › Números › Equipe):
// respondidas, passadas para alguém da equipe e resolvidas sem ninguém da equipe. A linha diz "esta
// semana" com todas as letras, porque a Equipe mostra o mês.
const props = defineProps({
  numeros: { type: Object, default: null },
  nome: { type: String, required: true },
  podeAbrir: { type: Boolean, default: false },
});

const emit = defineEmits(['abrir']);

const { t, locale } = useI18n();
const NS = 'AGENTS.JORNADA.PAGINA.SEMANA';

const formatar = n =>
  Number(n || 0).toLocaleString(idiomaDoNavegador(locale.value));
const vazia = computed(
  () =>
    !props.numeros?.respondidas &&
    !props.numeros?.passadas &&
    !props.numeros?.resolvidas
);

const cartoes = computed(() => {
  if (!props.numeros) return [];
  const respondidas = Number(props.numeros.respondidas || 0);
  const passadas = Number(props.numeros.passadas || 0);
  const resolvidas = Number(props.numeros.resolvidas || 0);
  // #1369 — plural pelo i18n ("respondeu 1 conversa", "1 conversa respondida").
  return [
    {
      aba: 'respondidas',
      numero: formatar(respondidas),
      rotulo: t(`${NS}.RESPONDIDAS`, respondidas),
      nota: t(`${NS}.NOTA_RESPONDIDAS`, { nome: props.nome }),
    },
    {
      aba: 'passadas',
      numero: formatar(passadas),
      rotulo: t(`${NS}.PASSADAS`, passadas),
      nota: t(`${NS}.NOTA_PASSADAS`),
    },
    {
      aba: 'resolvidas',
      numero: formatar(resolvidas),
      rotulo: t(`${NS}.RESOLVIDAS`, resolvidas),
      nota: t(`${NS}.NOTA_RESOLVIDAS`),
    },
  ];
});
</script>

<template>
  <section
    v-if="numeros && vazia"
    data-semana-vazia
    :aria-label="t(`${NS}.ROTULO`)"
    class="flex items-start gap-3 p-5 text-sm shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak dark:ring-n-slate-6 text-n-slate-11"
  >
    <span class="i-lucide-clock size-5 shrink-0" aria-hidden="true" />
    <p class="m-0">{{ t(`${NS}.VAZIA`, { nome }) }}</p>
  </section>
  <section
    v-else-if="numeros"
    data-semana
    :aria-label="t(`${NS}.ROTULO`)"
    class="flex flex-col gap-3"
  >
    <div class="flex flex-col">
      <p data-periodo class="m-0 text-sm font-semibold text-n-slate-12">
        {{ t(`${NS}.PERIODO`) }}
      </p>
      <p data-no-mes class="m-0 text-xs text-n-slate-11">
        {{ t(`${NS}.NO_MES`) }}
      </p>
    </div>
    <div class="grid grid-cols-1 gap-4 md:grid-cols-3">
      <component
        :is="podeAbrir ? 'button' : 'div'"
        v-for="cartao in cartoes"
        :key="cartao.aba"
        :type="podeAbrir ? 'button' : undefined"
        :data-numero="cartao.aba"
        class="flex flex-col gap-1 p-5 shadow-sm text-start rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak dark:ring-n-slate-6"
        :class="
          podeAbrir
            ? 'transition hover:ring-n-slate-7 hover:shadow-md focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-blue-11'
            : ''
        "
        @click="podeAbrir && emit('abrir', cartao.aba)"
      >
        <span class="text-3xl font-bold tabular-nums text-n-slate-12">
          {{ cartao.numero }}
        </span>
        <span class="text-sm font-semibold text-n-slate-12">
          {{ cartao.rotulo }}
        </span>
        <span class="text-sm text-n-slate-11">{{ cartao.nota }}</span>
        <span
          v-if="podeAbrir"
          data-ver
          class="inline-flex items-center gap-1 pt-2 mt-auto text-sm font-semibold text-n-blue-11"
        >
          {{ t(`${NS}.VER`) }}
          <span
            class="i-lucide-arrow-right size-3.5 rtl:rotate-180"
            aria-hidden="true"
          />
        </span>
      </component>
    </div>
  </section>
</template>
