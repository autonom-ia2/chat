<script setup>
import { computed, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { fusoDaConta, rotuloDoFuso } from 'dashboard/helper/fusoDaConta';
import { usePodeAbrir } from 'dashboard/components-next/sidebar/fork/usePodeAbrir';
import CrmNumerosOrigensAPI from 'dashboard/api/crmNumerosOrigens';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import NumerosEspera from '../components/numeros/v2/NumerosEspera.vue';
import NumerosMes from '../components/numeros/v2/NumerosMes.vue';
import OrigensDeOnde from '../components/numeros/v2/origens/OrigensDeOnde.vue';
import OrigensAnuncios from '../components/numeros/v2/origens/OrigensAnuncios.vue';
import OrigensGasto from '../components/numeros/v2/origens/OrigensGasto.vue';
import OrigensNaoMandaram from '../components/numeros/v2/origens/OrigensNaoMandaram.vue';
import OrigensComoContamos from '../components/numeros/v2/origens/OrigensComoContamos.vue';
import OrigensRelatorio from '../components/numeros/v2/origens/OrigensRelatorio.vue';
import {
  destinoDaOrigem,
  destinoDoAnuncio,
} from '../components/numeros/v2/origens/destinosOrigens';
import { useQuemVeNumeros } from '../components/numeros/useQuemVeNumeros';
import {
  P,
  comMaiuscula,
  nomeDoMes,
} from '../components/numeros/v2/numerosTextos';
import { useNumerosFormato } from '../components/numeros/v2/useNumerosFormato';

// CRM › Números › "De onde vieram os clientes" (#2001, F6 do #1871): uma tela, quatro perguntas. Abre pela visão
// "Equipe" (o R$ dos outros é número comercial: quem vê a equipe), com a flag `crm_numeros_origens`. As perguntas 3
// e 4 só existem com gasto de anúncio conectado, para quem pode ver os anúncios e só em "Todos os funis" (o gasto é
// da conta toda, decisão do Rodrigo de 25/10); com um funil escolhido, um convite leva para "Todos os funis". Sem
// gasto, nada de gasto. Quem decide o que vem é o servidor (GET crm/numeros/origens).
const O = 'CRM_NUMEROS_ORIGENS';
const TODOS_OS_FUNIS = 'todos';
const route = useRoute();
const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);
const { currentAccount } = useAccount();
const { podeAbrir } = usePodeAbrir();
const { t, locale } = useNumerosFormato();
const { pronto, equipeNova, veEquipe } = useQuemVeNumeros();

const dados = ref(null);
const carregando = ref(true);
const falhou = ref(false);
const comoContamos = ref(null);

const fuso = computed(() => fusoDaConta(currentAccount.value));
// Funil da tela: ?funil=<id>|todos (volta da Lista no mesmo funil). Sem nada, o funil principal.
const funil = computed(() =>
  typeof route.query.funil === 'string' ? route.query.funil : ''
);
// Mês da tela: ?mes=AAAA-MM (decisão 4, 25/10). Sem nada, o mês de hoje no fuso da conta.
const mesPedido = computed(() =>
  typeof route.query.mes === 'string' ? route.query.mes : ''
);

// Só o que veio na URL: vazio é o mês de hoje e o funil principal (o servidor decide).
const filtroPedido = computed(() => ({
  ...(mesPedido.value ? { mes: mesPedido.value } : {}),
  ...(funil.value ? { funil: funil.value } : {}),
}));

const carregar = async () => {
  carregando.value = true;
  falhou.value = false;
  try {
    const { data } = await CrmNumerosOrigensAPI.show(filtroPedido.value);
    dados.value = data;
  } catch {
    falhou.value = true;
  } finally {
    carregando.value = false;
  }
};

const ligada = computed(() =>
  Boolean(
    isFeatureEnabledonAccount.value(
      accountId.value,
      FEATURE_FLAGS.CRM_NUMEROS_ORIGENS
    )
  )
);
const abre = computed(() => equipeNova.value && veEquipe.value && ligada.value);
watch(
  [pronto, abre],
  ([carregou, pode]) => {
    if (!carregou) return;
    if (!pode) {
      router.replace({ name: 'crm_dashboard_index', params: route.params });
      return;
    }
    carregar();
  },
  { immediate: true }
);
watch([funil, mesPedido], () => {
  if (abre.value) carregar();
});

const funilEscolhido = computed(() => dados.value?.funil?.escolhido || '');
const emTodos = computed(() => funilEscolhido.value === TODOS_OS_FUNIS);
const opcoesDeFunil = computed(() =>
  (dados.value?.funil?.opcoes || []).map(op => ({
    value: op.id,
    label:
      op.id === TODOS_OS_FUNIS
        ? t(`${O}.FUNIL.TODOS`)
        : t(op.principal ? `${O}.FUNIL.PRINCIPAL` : `${O}.FUNIL.NOME`, {
            nome: op.nome,
          }),
  }))
);
const trocarFunil = valor => {
  router.replace({ query: { ...route.query, funil: valor } });
};
const ondeTexto = computed(() =>
  emTodos.value
    ? t(`${O}.FUNIL.ONDE_TODOS`)
    : t(`${O}.FUNIL.ONDE`, { nome: dados.value?.funil?.nome || '' })
);

const mesNome = computed(() =>
  dados.value?.mes
    ? nomeDoMes(dados.value.mes.chave, { locale: locale(), fuso: fuso.value })
    : ''
);
const rotuloDoMes = computed(() => {
  const info = dados.value?.mes;
  if (!info) return '';
  if (info.fechado)
    return t(`${P}.MES.FECHADO`, { mes: comMaiuscula(mesNome.value) });
  return t(
    `${P}.MES.ATUAL`,
    { mes: comMaiuscula(mesNome.value), n: info.diasRestantes },
    info.diasRestantes
  );
});

// Troca de mês: o servidor diz o anterior e o seguinte (do limite de meses até o de hoje), como na Equipe.
const mesAnterior = computed(() => dados.value?.mes?.anterior || '');
const mesSeguinte = computed(() => dados.value?.mes?.seguinte || '');
const nomeCurto = chave =>
  chave ? nomeDoMes(chave, { locale: locale(), fuso: fuso.value }) : '';
const irParaMes = chave => {
  if (chave) router.replace({ query: { ...route.query, mes: chave } });
};

const contexto = computed(() => ({
  funilId: dados.value?.funilId,
  mes: dados.value?.mes?.chave,
  podeAbrir,
}));
const destinoDaLinha = tipo => destinoDaOrigem(tipo, contexto.value);
const destinoDaLinhaDoAnuncio = id => destinoDoAnuncio(id, contexto.value);

const voltar = { name: 'crm_dashboard_index', query: { visao: 'equipe' } };
const abrirFunil = computed(() => ({
  name: 'crm_kanban_index',
  query: dados.value?.funilId
    ? { pipeline_id: String(dados.value.funilId) }
    : {},
}));
// Estado sem dados no mês: com o seletor de funil na tela, diz o funil; sem ele, só o mês.
const textoVazio = computed(() =>
  dados.value?.funil?.nome && opcoesDeFunil.value.length
    ? t(`${O}.VAZIO.TITULO_FUNIL`, {
        funil: dados.value.funil.nome,
        mes: mesNome.value,
      })
    : t(`${O}.VAZIO.TITULO`, { mes: mesNome.value })
);
// O arquivo sai com o mesmo mês e o mesmo funil que a tela mostra.
const filtroDoArquivo = computed(() => ({
  mes: dados.value?.mes?.chave,
  funil: funilEscolhido.value,
}));
// "Alterar mês ou funil" no diálogo do relatório: fecha e põe o foco no seletor de funil.
const focarFiltros = () => {
  document.getElementById('origens-funil')?.focus();
};
</script>

<template>
  <div class="flex h-full w-full flex-col overflow-auto bg-n-background">
    <header
      class="flex flex-col gap-2 border-b border-n-weak px-4 py-4 sm:px-6 sm:py-5"
    >
      <RouterLink
        :to="voltar"
        data-origens-voltar
        class="inline-flex min-h-11 w-fit items-center gap-1 rounded-lg px-1 text-sm font-medium text-n-slate-11 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      >
        <span
          class="i-lucide-chevron-left size-4 rtl:rotate-180"
          aria-hidden="true"
        />
        {{ t(`${O}.VOLTAR`) }}
      </RouterLink>
      <h1 class="m-0 text-xl font-semibold text-n-slate-12">
        {{ t(`${O}.TITULO`) }}
      </h1>
      <div
        class="flex flex-wrap items-center gap-x-3 gap-y-2"
        data-origens-filtros
      >
        <NumerosMes
          v-if="rotuloDoMes"
          :rotulo="rotuloDoMes"
          :anterior="nomeCurto(mesAnterior)"
          :seguinte="nomeCurto(mesSeguinte)"
          :disabled="carregando"
          @anterior="irParaMes(mesAnterior)"
          @seguinte="irParaMes(mesSeguinte)"
        />
        <div
          v-if="opcoesDeFunil.length"
          class="flex items-center gap-2"
          data-origens-funil
        >
          <label
            for="origens-funil"
            class="text-sm font-medium text-n-slate-11"
          >
            {{ t(`${O}.FUNIL.ROTULO`) }}
          </label>
          <ChoiceSelect
            :model-value="funilEscolhido"
            trigger-id="origens-funil"
            :options="opcoesDeFunil"
            :aria-label="t(`${O}.FUNIL.ROTULO`)"
            compact
            @update:model-value="trocarFunil"
          />
        </div>
        <div v-if="dados && !dados.vazio" class="ms-auto">
          <OrigensRelatorio
            :filtro="filtroDoArquivo"
            :mes-nome="mesNome"
            :funil-nome="emTodos ? '' : dados.funil.nome"
            @alterar="focarFiltros"
          />
        </div>
      </div>
    </header>

    <div
      class="mx-auto flex w-full max-w-3xl flex-col gap-6 px-4 pb-24 pt-5 transition-opacity sm:px-6 sm:pb-5 motion-reduce:transition-none"
      :class="carregando && dados ? 'opacity-60' : ''"
      :aria-busy="carregando ? 'true' : 'false'"
      data-numeros-origens
      :data-com-gasto="dados?.gasto ? 'sim' : 'nao'"
    >
      <NumerosEspera
        v-if="!pronto || (carregando && !dados) || falhou"
        :falhou="falhou"
        @tentar="carregar"
      />

      <div
        v-else-if="dados?.vazio || !dados?.origens?.length"
        data-origens-vazio
        class="flex flex-col items-center gap-4 rounded-2xl bg-n-solid-1 px-6 py-10 text-center ring-1 ring-inset ring-n-weak"
      >
        <p class="m-0 text-base font-semibold text-n-slate-12">
          {{ textoVazio }}
        </p>
        <RouterLink
          v-if="podeAbrir(abrirFunil)"
          :to="abrirFunil"
          class="inline-flex min-h-12 items-center rounded-xl bg-n-blue-9 px-6 text-base font-semibold text-white hover:bg-n-blue-10 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        >
          {{ t(`${O}.VAZIO.ACAO`) }}
        </RouterLink>
      </div>

      <template v-else-if="dados">
        <OrigensDeOnde
          :origens="dados.origens"
          :onde="ondeTexto"
          :em-todos="emTodos"
          :mes-nome="mesNome"
          :moeda="dados.moeda"
          :destino-de="destinoDaLinha"
        />
        <OrigensAnuncios
          v-if="dados.anuncios.length"
          :anuncios="dados.anuncios"
          :em-todos="emTodos"
          :moeda="dados.moeda"
          :destino-de="destinoDaLinhaDoAnuncio"
        />
        <section
          v-if="dados.gastoEmTodos"
          data-origens-gasto-em-todos
          class="flex flex-col items-start gap-3 rounded-xl bg-n-solid-1 p-4 ring-1 ring-inset ring-n-weak"
        >
          <p class="mb-0 text-sm text-n-slate-12">
            {{ t(`${O}.GASTO_EM_TODOS.TEXTO`) }}
          </p>
          <button
            type="button"
            data-ver-todos-os-funis
            class="inline-flex min-h-11 items-center gap-1.5 rounded-xl bg-n-alpha-2 px-4 text-sm font-semibold text-n-slate-12 hover:bg-n-alpha-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            @click="trocarFunil(TODOS_OS_FUNIS)"
          >
            {{ t(`${O}.GASTO_EM_TODOS.ACAO`) }}
          </button>
        </section>
        <OrigensGasto
          v-if="dados.gasto"
          :gasto="dados.gasto"
          :mes-nome="mesNome"
          :moeda="dados.moeda"
        />
        <OrigensNaoMandaram
          v-if="dados.gasto"
          :toques="dados.gasto.toques"
          :clientes="dados.gasto.clientes"
        />
        <p
          v-if="dados.gastoOculto"
          data-origens-gasto-oculto
          class="mb-0 flex items-start gap-2 rounded-xl bg-n-solid-1 px-4 py-3 text-sm text-n-slate-11 ring-1 ring-inset ring-n-weak"
        >
          <span
            class="i-lucide-lock mt-0.5 size-4 flex-none"
            aria-hidden="true"
          />
          {{ t(`${O}.GASTO_OCULTO`) }}
        </p>
        <button
          type="button"
          data-como-contamos-link
          class="inline-flex min-h-11 w-fit items-center gap-1.5 rounded-xl px-3 text-sm font-medium text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="comoContamos?.abrir()"
        >
          <span class="i-lucide-circle-help size-4" aria-hidden="true" />
          {{ t(`${O}.COMO_CONTAMOS.LINK`) }}
        </button>
      </template>
    </div>

    <OrigensComoContamos
      ref="comoContamos"
      :fuso="rotuloDoFuso(fuso)"
      :com-gasto="Boolean(dados?.gasto)"
    />
  </div>
</template>
