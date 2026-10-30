<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import AgentsAPI from 'dashboard/api/autonomia/agents';
import { idiomaDoNavegador } from '../../utils/pagina';

// #1709 — "Quando {nome} não respondeu" na página do agente (mockup aprovado pelo Rodrigo, 17/10/2026): as vezes, esta
// semana, em que o agente não respondeu de propósito (eventos skipped_* do Analytics, `silences` de
// GET /autonomia/agents/:id/analytics na janela de 7 dias do Desempenho, que começa à meia-noite no fuso do servidor; os
// números da semana começam no fuso da conta, Autonomia::ContaDaIa, #2000). Sem clique para as conversas.
// O bloco some quando:
// - o agente não fala com o cliente (`falaComCliente`, decidido pela página: ajudante, interno, cotação);
// - não houve conversa esta semana (`numeros`, o mesmo dado do AgenteSemana: null ou zero e zero);
// - a leitura ainda não chegou ou falhou (é um aviso, não um dado de que a tela dependa; a falha vai ao console só com
//   o status ou a classe do erro, sem dado da conversa).
// Com conversa na semana e nenhum silêncio: "{nome} não deixou de responder nenhuma vez esta semana." (o texto
// aprovado no mockup). Trocando de agente, a resposta que chega do agente anterior é descartada.
const props = defineProps({
  agentId: { type: Number, required: true },
  nome: { type: String, required: true },
  numeros: { type: Object, default: null },
  falaComCliente: { type: Boolean, default: true },
});

const { t, locale } = useI18n();
const NS = 'AGENTS.JORNADA.PAGINA.SILENCIOS';
const MOTIVOS = [
  'mensagem_sem_suporte',
  'mensagem_apagada',
  'escolha_retirada',
];

const silencios = ref(null);

const teveConversa = computed(
  () =>
    Number(props.numeros?.respondidas || 0) +
      Number(props.numeros?.passadas || 0) >
    0
);
const aparece = computed(() => props.falaComCliente && teveConversa.value);

// O status HTTP, ou a classe do erro: nunca a mensagem nem o corpo da resposta.
const resumoDoErro = erro => erro?.response?.status ?? erro?.name ?? 'erro';

const ler = async () => {
  silencios.value = null;
  if (!aparece.value) return;
  const pedido = props.agentId;
  try {
    const { data } = await AgentsAPI.analytics(pedido, { range: '7d' });
    if (pedido !== props.agentId) return;
    silencios.value = (data?.silences || []).filter(linha =>
      MOTIVOS.includes(linha.reason)
    );
  } catch (erro) {
    if (pedido !== props.agentId) return;
    // eslint-disable-next-line no-console
    console.warn('[agentes] silencios: leitura falhou', resumoDoErro(erro));
    silencios.value = null;
  }
};

watch(() => [props.agentId, aparece.value], ler, { immediate: true });

const vazio = computed(() => silencios.value?.length === 0);
const formatar = n =>
  Number(n || 0).toLocaleString(idiomaDoNavegador(locale.value));
const titulo = computed(() => `silencios-${props.agentId}`);
</script>

<template>
  <section
    v-if="aparece && silencios"
    data-bloco="silencios"
    :aria-labelledby="titulo"
    class="flex flex-col gap-3 p-5 shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak dark:ring-n-slate-6"
  >
    <div class="flex items-start gap-3">
      <span
        class="grid rounded-lg place-items-center size-9 shrink-0 bg-n-alpha-2"
        aria-hidden="true"
      >
        <span
          v-if="vazio"
          class="i-lucide-circle-check size-5 text-n-teal-11"
        />
        <span
          v-else
          class="i-lucide-message-circle-off size-5 text-n-slate-11"
        />
      </span>
      <div class="flex flex-col flex-1 min-w-0 gap-1">
        <h2 :id="titulo" class="m-0 text-base font-semibold text-n-slate-12">
          {{ t(`${NS}.TITULO`, { nome }) }}
        </h2>
        <p class="m-0 text-sm text-n-slate-11">
          {{ vazio ? t(`${NS}.VAZIO`, { nome }) : t(`${NS}.TEXTO`, { nome }) }}
        </p>
      </div>
    </div>
    <ul
      v-if="!vazio"
      class="flex flex-col p-0 m-0 list-none divide-y rounded-xl ring-1 ring-inset ring-n-weak divide-n-weak"
    >
      <li
        v-for="linha in silencios"
        :key="linha.reason"
        :data-motivo="linha.reason"
        class="flex items-center justify-between gap-3 px-4 py-3 text-sm min-h-11"
      >
        <span class="min-w-0 text-n-slate-12">
          {{ t(`${NS}.MOTIVOS.${linha.reason}`) }}
        </span>
        <span class="font-semibold shrink-0 tabular-nums text-n-slate-12">
          {{ t(`${NS}.VEZES`, { n: formatar(linha.count) }, linha.count) }}
        </span>
      </li>
    </ul>
  </section>
  <!-- Agente que não fala com o cliente, semana sem conversa ou leitura sem resposta: o bloco não aparece. -->
  <template v-else />
</template>
