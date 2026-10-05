<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import AutomationAPI from 'dashboard/api/automation';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  nomeDaAcao,
  nomeDoAtributo,
} from 'dashboard/helper/automacaoEmPortugues';

// #859/#982 — "Veja o que teria acontecido": a regra roda nas conversas mais
// recentes só para mostrar o que faria. O servidor não executa nada
// (AutomationRules::Ensaio). Com `automatico`, o teste roda ao abrir: a pessoa
// vê o resultado antes de decidir ligar.
const props = defineProps({
  regraId: { type: Number, required: true },
  accountId: { type: Number, required: true },
  automatico: { type: Boolean, default: false },
});

const { t } = useI18n();

const QUANTIDADE = 10;

const estado = ref('parado');
const resultados = ref([]);
const semTeste = ref([]);
// Passos depois do Decisor (#858): o teste não pergunta a ele, então eles só
// aparecem como dependentes da resposta.
const dependeDoDecisor = ref([]);
// Falso quando a regra inteira depende de algo mudar na hora: aí não há o que
// testar em conversa parada, e a tela diz isso em vez de listar conversas.
const testavel = ref(true);
const erro = ref('');

const casaram = computed(
  () => resultados.value.filter(item => item.casou).length
);

const testar = async () => {
  estado.value = 'testando';
  erro.value = '';
  try {
    const { data } = await AutomationAPI.ensaio(props.regraId, QUANTIDADE);
    resultados.value = data?.resultados || [];
    semTeste.value = data?.sem_teste || [];
    dependeDoDecisor.value = data?.depende_do_decisor || [];
    testavel.value = data?.testavel !== false;
    estado.value = 'pronto';
  } catch (error) {
    erro.value = error?.response?.data?.error || t('AUTOMACOES.ENSAIO.ERRO');
    estado.value = 'erro';
  }
};

const nomesDasAcoes = lista =>
  lista.map(acao => nomeDaAcao(acao, t)).join(', ');

const fariaTexto = item =>
  t('AUTOMACOES.ENSAIO.FARIA', { acoes: nomesDasAcoes(item.faria) });

const dependeDoDecisorTexto = computed(() =>
  t('AUTOMACOES.ENSAIO.DEPENDE_DO_DECISOR', {
    acoes: nomesDasAcoes(dependeDoDecisor.value),
  })
);

const partesSemTeste = computed(() =>
  semTeste.value.map(chave => nomeDoAtributo(chave, t)).join(', ')
);

const iniciais = item =>
  (item.contato || '?')
    .split(' ')
    .filter(Boolean)
    .slice(0, 2)
    .map(parte => parte[0].toUpperCase())
    .join('');

onMounted(() => {
  if (props.automatico) testar();
});

const linkDaConversa = item => ({
  name: 'inbox_conversation',
  params: { accountId: props.accountId, conversation_id: item.display_id },
});
</script>

<template>
  <section
    class="flex flex-col gap-4 p-6 border rounded-3xl border-n-weak bg-n-solid-1"
    :aria-label="$t('AUTOMACOES.ENSAIO.TITULO')"
  >
    <div class="flex flex-wrap items-center justify-between gap-3">
      <h2 class="text-lg font-semibold text-n-slate-12">
        {{ $t('AUTOMACOES.ENSAIO.TITULO') }}
      </h2>
      <Button
        data-testar
        :label="
          estado === 'parado'
            ? $t('AUTOMACOES.ENSAIO.BOTAO')
            : $t('AUTOMACOES.ENSAIO.DE_NOVO')
        "
        icon="i-lucide-flask-conical"
        slate
        faded
        size="sm"
        class="min-h-11"
        :is-loading="estado === 'testando'"
        :disabled="estado === 'testando'"
        @click="testar"
      />
    </div>
    <p class="mb-0 text-[0.9375rem] text-n-slate-11">
      {{ $t('AUTOMACOES.ENSAIO.EXPLICA') }}
    </p>

    <div role="status" aria-live="polite" class="flex flex-col gap-3">
      <div
        v-if="estado === 'testando'"
        class="flex flex-col gap-2"
        aria-busy="true"
      >
        <span class="sr-only">{{ $t('AUTOMACOES.ENSAIO.TESTANDO') }}</span>
        <div class="h-10 rounded-xl w-1/2 bg-n-alpha-2 animate-pulse" />
        <div class="h-11 rounded-xl bg-n-alpha-2 animate-pulse" />
        <div class="h-11 rounded-xl bg-n-alpha-2 animate-pulse" />
      </div>
      <p
        v-else-if="estado === 'erro'"
        data-ensaio-erro
        class="mb-0 text-[0.9375rem] text-n-ruby-11"
      >
        {{ erro }}
      </p>
      <p
        v-else-if="estado === 'pronto' && !testavel"
        data-nao-testavel
        class="mb-0 p-4 text-[0.9375rem] rounded-xl bg-n-amber-2 text-n-slate-12"
      >
        {{ $t('AUTOMACOES.ENSAIO.NAO_TESTAVEL', { partes: partesSemTeste }) }}
      </p>
      <template v-else-if="estado === 'pronto'">
        <p
          v-if="!resultados.length"
          data-ensaio-vazio
          class="mb-0 text-[0.9375rem] text-n-slate-11"
        >
          {{ $t('AUTOMACOES.ENSAIO.SEM_CONVERSA') }}
        </p>
        <p
          v-else
          data-ensaio-resumo
          class="flex flex-wrap items-baseline gap-x-3 gap-y-1 m-0"
        >
          <span
            class="text-4xl font-bold tracking-tight tabular-nums text-n-teal-11"
          >
            {{ casaram }}
          </span>
          <span class="text-base text-n-slate-11">
            {{
              $t('AUTOMACOES.ENSAIO.RESUMO', {
                casaram,
                total: resultados.length,
              })
            }}
          </span>
        </p>
        <p
          v-if="semTeste.length"
          data-sem-teste
          class="mb-0 text-sm text-n-amber-11"
        >
          {{ $t('AUTOMACOES.ENSAIO.SEM_TESTE', { partes: partesSemTeste }) }}
        </p>
        <p
          v-if="dependeDoDecisor.length"
          data-depende-do-decisor
          class="mb-0 text-sm text-n-amber-11"
        >
          {{ dependeDoDecisorTexto }}
        </p>
        <ul
          v-if="resultados.length"
          class="flex flex-col p-0 m-0 list-none divide-y divide-n-weak"
        >
          <li
            v-for="item in resultados"
            :key="item.conversation_id"
            data-ensaio-item
            class="flex items-center gap-3 py-2"
          >
            <span
              class="grid text-xs font-bold rounded-full place-items-center size-8 shrink-0 bg-n-slate-3 text-n-slate-11"
              aria-hidden="true"
            >
              {{ iniciais(item) }}
            </span>
            <span class="flex flex-col flex-1 min-w-0">
              <span class="text-[0.9375rem] truncate text-n-slate-12">
                {{ item.contato || $t('AUTOMACOES.ENSAIO.CONTATO_SEM_NOME') }}
              </span>
              <span v-if="item.casou" class="text-xs truncate text-n-slate-11">
                {{ fariaTexto(item) }}
              </span>
            </span>
            <span
              class="text-sm font-semibold shrink-0"
              :class="item.casou ? 'text-n-teal-11' : 'text-n-slate-10'"
            >
              {{
                item.casou
                  ? $t('AUTOMACOES.ENSAIO.CASARIA')
                  : $t('AUTOMACOES.ENSAIO.NAO_CASARIA')
              }}
            </span>
            <router-link
              :to="linkDaConversa(item)"
              :aria-label="$t('AUTOMACOES.ENSAIO.ABRIR_CONVERSA')"
              :title="$t('AUTOMACOES.ENSAIO.ABRIR_CONVERSA')"
              class="grid rounded-lg place-items-center size-11 shrink-0 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-blue-11"
            >
              <span class="i-lucide-external-link size-4" aria-hidden="true" />
            </router-link>
          </li>
        </ul>
      </template>
    </div>
  </section>
</template>
