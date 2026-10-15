<script setup>
import { computed, inject, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { ehAgente } from '../passagem';

// #1385 — quem recebe, com três clientes de exemplo: o rodízio pela equipe, ou uma frase só quando é sempre a mesma
// pessoa (ou falta escolher, que o erro já mostra à esquerda).
// #1593 — com agentes de IA nas caixas e o "pedido pelo nome" ligado, a primeira cliente pede um agente pelo nome e
// vai para ele; as outras seguem a vez entre as pessoas (a IA não entra na vez).
const props = defineProps({
  regra: { type: Object, required: true },
  fila: { type: Array, default: () => [] },
  pessoa: { type: String, default: '' },
});

const { t } = useI18n();
const P = 'CRM_KANBAN.PASSAGEM.PREVIA';
const CLIENTES = ['CLIENTE', 'CLIENTE_2', 'CLIENTE_3'];
const { agentes } = inject('passagemIa', { agentes: ref([]) });
const comIa = computed(() => agentes.value.length > 0);

const sempreAMesma = computed(() => props.regra.pool_type === 'user');
const paraIa = computed(
  () => sempreAMesma.value && ehAgente(props.regra.pool_id)
);
const pedido = computed(() =>
  props.regra.mode === 'direct'
    ? agentes.value.find(agente => !agente.parado) || null
    : null
);
const linhas = computed(() => {
  const daVez = indice =>
    props.fila[indice % Math.max(props.fila.length, 1)] || t(`${P}.ALGUEM`);
  if (!pedido.value) {
    return CLIENTES.map((chave, indice) => ({
      chave,
      cliente: t(`${P}.${chave}`),
      recebe: daVez(indice),
      ia: false,
    }));
  }
  const [primeira, ...outras] = CLIENTES;
  return [
    {
      chave: primeira,
      cliente: t(`${P}.PEDIU`, {
        cliente: t(`${P}.${primeira}`),
        nome: pedido.value.name,
      }),
      recebe: pedido.value.name,
      ia: true,
    },
    ...outras.map((chave, indice) => ({
      chave,
      cliente: t(`${P}.${chave}`),
      recebe: daVez(indice),
      ia: false,
    })),
  ];
});
const notaDaVez = computed(() => {
  if (props.regra.mode !== 'direct') {
    return t(comIa.value ? `${P}.FILA_EQUIPE_IA` : `${P}.FILA_EQUIPE`);
  }
  return t(comIa.value ? `${P}.FILA_EQUIPE_NOME_IA` : `${P}.FILA_EQUIPE_NOME`);
});
</script>

<template>
  <section
    class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4"
  >
    <h3 class="mb-0 text-sm font-semibold text-n-slate-12">
      {{ t(`${P}.FILA_TITULO`) }}
    </h3>
    <p
      v-if="sempreAMesma"
      class="mb-0 flex items-start gap-2 rounded-xl bg-n-alpha-1 px-3 py-3 text-[0.9375rem] text-n-slate-12"
    >
      <span
        class="mt-1 size-4 shrink-0 text-n-slate-11"
        :class="paraIa ? 'i-lucide-bot' : 'i-lucide-user-round'"
        aria-hidden="true"
      />
      <span v-if="!pessoa">{{ t(`${P}.FILA_FALTA`) }}</span>
      <span v-else-if="paraIa" data-previa-ia>
        {{ t(`${P}.FILA_IA`, { nome: pessoa }) }}
      </span>
      <span v-else>{{ t(`${P}.FILA_PESSOA`, { nome: pessoa }) }}</span>
    </p>
    <template v-else>
      <ol class="m-0 flex list-none flex-col gap-2 p-0">
        <li
          v-for="linha in linhas"
          :key="linha.chave"
          :data-previa-pedido="linha.ia || undefined"
          class="flex items-center gap-3 rounded-xl px-3 py-2 text-[0.9375rem] text-n-slate-12"
          :class="linha.ia ? 'bg-n-iris-2' : 'bg-n-alpha-1'"
        >
          <span class="min-w-0 flex-1 truncate">{{ linha.cliente }}</span>
          <span
            class="i-lucide-arrow-right size-4 shrink-0 text-n-slate-10 rtl:rotate-180"
            aria-hidden="true"
          />
          <span
            class="flex min-w-0 flex-1 flex-wrap items-center gap-x-1.5 gap-y-1 font-semibold"
          >
            <span
              v-if="linha.ia"
              class="i-lucide-bot size-4 shrink-0 text-n-iris-11"
              aria-hidden="true"
            />
            <span class="truncate">{{ linha.recebe }}</span>
            <span
              v-if="linha.ia"
              class="rounded-md bg-n-iris-3 px-1.5 py-0.5 text-xs font-medium text-n-iris-11"
            >
              {{ t('CRM_CAIXAS.PESSOAS.SELO_IA') }}
            </span>
          </span>
        </li>
      </ol>
      <p class="mb-0 text-sm text-n-slate-11">
        {{ notaDaVez }}
      </p>
    </template>
  </section>
</template>
