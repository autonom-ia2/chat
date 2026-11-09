<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { camadasDoPacote } from 'dashboard/i18n/pacotesDoPainel';
import AgentesHeroi from '../../components/AgentesHeroi.vue';
import AgenteBotao from '../../components/AgenteBotao.vue';
import VitrineCartao from '../components/VitrineCartao.vue';
import VitrineDetalhe from '../components/VitrineDetalhe.vue';
import { ehCotacao } from '../../utils/pagina';
import { FERRAMENTAS, GRUPOS, emDestaque, ferramentaPorId } from '../catalogo';
import { useVitrine } from '../useVitrine';

// #2776 — VITRINE DE FERRAMENTAS PRONTAS (protótipo, adaptador falso). Na frente, o que o agente passa a conseguir,
// em grupos de nome leigo; atrás, em "Criar a minha (avançado)", o cadastro livre do #1430. A pessoa nunca vê chave,
// link, formato nem método: a plataforma resolve (decisão 3 do Rodrigo). Tudo aparece para todo negócio, com as do
// ramo da conta em destaque (pacote #1550). A Lia (cotação) fica fora da escolha de agente, como no #2812.
// `?agente=<id>` chega da página do agente (Adicionar ferramenta) e já deixa o agente escolhido.
const NS = 'AGENTS.VITRINE';
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const { currentAccount, accountScopedRoute } = useAccount();
const vitrine = useVitrine();

const registros = useMapGetter('autonomiaAgents/getRecords');
const carregando = ref(true);
const agentes = computed(() =>
  (registros.value || []).filter(agente => !ehCotacao(agente))
);

const agenteDaRota = computed(() => {
  const id = Number(route.query.agente);
  return agentes.value.find(agente => agente.id === id) || null;
});

const busca = ref('');
const grupo = ref('TODAS');
const aberta = ref(null);

const camadas = computed(() =>
  camadasDoPacote(currentAccount.value?.autonomia_pacote)
);

// Busca simples por texto nos nomes e frases do catálogo (protótipo). Sem acento e sem diferença de maiúscula.
const ACENTOS_INICIO = 0x300;
const ACENTOS_FIM = 0x36f;
const semAcento = texto =>
  [...String(texto).normalize('NFD')]
    .filter(c => {
      const codigo = c.charCodeAt(0);
      return codigo < ACENTOS_INICIO || codigo > ACENTOS_FIM;
    })
    .join('')
    .toLowerCase();

const textoDe = ferramenta => {
  const base = `${NS}.FERRAMENTAS.${ferramenta.id}`;
  return semAcento(
    [
      t(`${base}.NOME`),
      t(`${base}.APOIO`),
      t(`${base}.FAZ`),
      t(`${NS}.GRUPOS.${ferramenta.grupo}.NOME`),
    ].join(' ')
  );
};

const termo = computed(() => semAcento(busca.value.trim()));
const achadas = computed(() =>
  termo.value
    ? FERRAMENTAS.filter(ferramenta =>
        termo.value
          .split(' ')
          .filter(Boolean)
          .every(parte => textoDe(ferramenta).includes(parte))
      )
    : FERRAMENTAS
);

const gruposVisiveis = computed(() =>
  GRUPOS.filter(item => grupo.value === 'TODAS' || item.id === grupo.value)
    .map(item => ({
      ...item,
      ferramentas: achadas.value.filter(f => f.grupo === item.id),
    }))
    .filter(item => item.ferramentas.length)
);

const destaque = computed(() =>
  termo.value || grupo.value !== 'TODAS' ? [] : emDestaque(camadas.value)
);
const tituloDoDestaque = computed(() =>
  camadas.value.length ? t(`${NS}.DESTAQUE.RAMO`) : t(`${NS}.DESTAQUE.GERAL`)
);

const tomDe = ferramenta =>
  GRUPOS.find(item => item.id === ferramenta.grupo)?.tom;

const jaSabe = ferramenta =>
  agenteDaRota.value && vitrine.tem(agenteDaRota.value.id, ferramenta.id)
    ? agenteDaRota.value.name
    : '';

const filtros = computed(() => [
  { id: 'TODAS', nome: t(`${NS}.FILTRO.TODAS`) },
  ...GRUPOS.map(item => ({
    id: item.id,
    nome: t(`${NS}.GRUPOS.${item.id}.NOME`),
  })),
]);

const verTodas = () => {
  busca.value = '';
  grupo.value = 'TODAS';
};

const trocarAgente = () =>
  router.replace({ query: { ...route.query, agente: undefined } });

const verFerramentasDoAgente = agente =>
  router.push(
    accountScopedRoute(
      'autonomia_agent_panel',
      { agentId: agente.id },
      { gaveta: 'ferramentas' }
    )
  );

const criarAgente = () =>
  router.push(accountScopedRoute('autonomia_agents_builder'));

const criarAMinha = () => {
  const agente = agenteDaRota.value || agentes.value[0];
  if (agente) verFerramentasDoAgente(agente);
};

onMounted(async () => {
  try {
    await store.dispatch('autonomiaAgents/get');
  } finally {
    carregando.value = false;
  }
  const abrir = ferramentaPorId(String(route.query.ferramenta || ''));
  if (abrir) aberta.value = abrir;
});
</script>

<template>
  <div data-vitrine class="w-full h-full overflow-y-auto bg-n-background">
    <div
      class="flex flex-col w-full max-w-6xl gap-8 px-4 pt-6 pb-24 mx-auto md:px-8 md:pb-6"
    >
      <AgentesHeroi
        :titulo="t(`${NS}.HEROI.TITULO`)"
        :texto="t(`${NS}.HEROI.TEXTO`)"
      >
        <label
          for="vitrine-busca"
          class="block mb-2 text-sm font-medium text-white/80"
        >
          {{ t(`${NS}.HEROI.BUSCA`) }}
        </label>
        <form
          role="search"
          class="relative flex items-center gap-2 p-2 bg-white shadow-2xl rounded-2xl dark:bg-n-solid-1 focus-within:ring-2 focus-within:ring-n-blue-9"
          @submit.prevent
        >
          <span
            aria-hidden="true"
            class="i-lucide-search size-5 ms-2 shrink-0 text-n-slate-11"
          />
          <input
            id="vitrine-busca"
            v-model="busca"
            data-vitrine-busca
            type="search"
            :placeholder="t(`${NS}.HEROI.BUSCA_EXEMPLO`)"
            class="flex-1 min-w-0 px-2 !mb-0 text-base !bg-transparent !border-0 !shadow-none !outline-none min-h-12 text-n-slate-12 focus:!ring-0 [&::-webkit-search-cancel-button]:appearance-none"
          />
          <button
            v-if="busca"
            type="button"
            data-vitrine-limpar
            :aria-label="t(`${NS}.HEROI.LIMPAR`)"
            class="grid rounded-xl place-items-center size-11 shrink-0 text-n-slate-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
            @click="busca = ''"
          >
            <span class="i-lucide-x size-5" aria-hidden="true" />
          </button>
        </form>
      </AgentesHeroi>

      <div
        v-if="!carregando && !agentes.length"
        data-vitrine-sem-agente
        class="flex flex-col items-center gap-4 px-6 py-12 text-center rounded-3xl bg-n-solid-1 ring-1 ring-inset ring-n-weak"
      >
        <span aria-hidden="true" class="i-lucide-bot size-10 text-n-slate-11" />
        <p class="max-w-md m-0 text-base text-n-slate-12">
          {{ t(`${NS}.SEM_AGENTE.TEXTO`) }}
        </p>
        <AgenteBotao tamanho="lg" icone="i-lucide-plus" @click="criarAgente">
          {{ t(`${NS}.SEM_AGENTE.BOTAO`) }}
        </AgenteBotao>
      </div>

      <template v-else>
        <div
          v-if="agenteDaRota"
          data-vitrine-para
          class="flex flex-wrap items-center justify-between gap-3 px-4 py-3 rounded-2xl bg-n-blue-2 ring-1 ring-inset ring-n-blue-6"
        >
          <p class="flex items-center gap-3 m-0 text-base text-n-slate-12">
            <span
              aria-hidden="true"
              class="grid text-sm font-semibold text-white rounded-full place-items-center size-9 bg-n-blue-9"
            >
              {{ agenteDaRota.name.charAt(0) }}
            </span>
            {{ t(`${NS}.PARA.TEXTO`, { nome: agenteDaRota.name }) }}
          </p>
          <AgenteBotao variante="fantasma" @click="trocarAgente">
            {{ t(`${NS}.PARA.TROCAR`) }}
          </AgenteBotao>
        </div>

        <nav :aria-label="t(`${NS}.FILTRO.ROTULO`)">
          <ul
            class="flex gap-2 p-0 pb-1 m-0 overflow-x-auto list-none snap-x scroll-px-4"
          >
            <li v-for="filtro in filtros" :key="filtro.id" class="snap-start">
              <button
                type="button"
                :data-vitrine-filtro="filtro.id"
                :aria-pressed="grupo === filtro.id ? 'true' : 'false'"
                class="px-4 text-sm font-medium rounded-full whitespace-nowrap min-h-11 ring-1 ring-inset focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
                :class="
                  grupo === filtro.id
                    ? 'bg-n-blue-11 text-white ring-n-blue-11 dark:text-n-slate-1'
                    : 'bg-n-solid-1 text-n-slate-12 ring-n-weak hover:bg-n-alpha-1'
                "
                @click="grupo = filtro.id"
              >
                {{ filtro.nome }}
              </button>
            </li>
          </ul>
        </nav>

        <p
          v-if="termo && achadas.length"
          role="status"
          class="m-0 text-sm text-n-slate-11"
        >
          {{
            t(`${NS}.BUSCA.ACHADAS`, { n: achadas.length, termo: busca.trim() })
          }}
        </p>

        <section
          v-if="destaque.length"
          data-vitrine-destaque
          aria-labelledby="vitrine-destaque"
          class="flex flex-col gap-4 p-5 rounded-3xl bg-n-blue-2 md:p-6"
        >
          <h2
            id="vitrine-destaque"
            class="flex items-center gap-2 m-0 text-xl font-bold text-n-slate-12"
          >
            <span
              class="i-lucide-sparkles size-5 text-n-blue-11"
              aria-hidden="true"
            />
            {{ tituloDoDestaque }}
          </h2>
          <ul
            class="grid gap-4 p-0 m-0 list-none sm:grid-cols-2 lg:grid-cols-3"
          >
            <li v-for="ferramenta in destaque" :key="ferramenta.id">
              <VitrineCartao
                :ferramenta="ferramenta"
                :tom="tomDe(ferramenta)"
                :ja-sabe="jaSabe(ferramenta)"
                destaque
                @abrir="aberta = $event"
              />
            </li>
          </ul>
        </section>

        <div
          v-if="!gruposVisiveis.length"
          data-vitrine-nada
          role="status"
          class="flex flex-col items-center gap-4 px-6 py-12 text-center rounded-3xl bg-n-solid-1 ring-1 ring-inset ring-n-weak"
        >
          <span
            aria-hidden="true"
            class="i-lucide-search-x size-10 text-n-slate-11"
          />
          <p class="m-0 text-base text-n-slate-12">
            {{ t(`${NS}.BUSCA.NADA`, { termo: busca.trim() }) }}
          </p>
          <AgenteBotao tamanho="lg" @click="verTodas">
            {{ t(`${NS}.BUSCA.VER_TODAS`) }}
          </AgenteBotao>
        </div>

        <section
          v-for="item in gruposVisiveis"
          :key="item.id"
          :data-vitrine-grupo="item.id"
          :aria-labelledby="`vitrine-grupo-${item.id}`"
          class="flex flex-col gap-4"
        >
          <div class="flex items-center gap-3">
            <span
              aria-hidden="true"
              class="grid rounded-xl place-items-center size-10 shrink-0 bg-n-alpha-2 text-n-slate-12"
            >
              <span :class="item.icone" class="size-5" />
            </span>
            <div class="flex flex-col">
              <h2
                :id="`vitrine-grupo-${item.id}`"
                class="m-0 text-lg font-bold text-n-slate-12"
              >
                {{ t(`${NS}.GRUPOS.${item.id}.NOME`) }}
              </h2>
              <p class="m-0 text-sm text-n-slate-11">
                {{ t(`${NS}.GRUPOS.${item.id}.TEXTO`) }}
              </p>
            </div>
          </div>
          <ul
            class="grid gap-4 p-0 m-0 list-none sm:grid-cols-2 lg:grid-cols-3"
          >
            <li v-for="ferramenta in item.ferramentas" :key="ferramenta.id">
              <VitrineCartao
                :ferramenta="ferramenta"
                :tom="item.tom"
                :ja-sabe="jaSabe(ferramenta)"
                @abrir="aberta = $event"
              />
            </li>
          </ul>
        </section>

        <div
          data-vitrine-avancado
          class="flex flex-wrap items-center justify-between gap-3 px-5 py-4 rounded-2xl bg-n-alpha-1"
        >
          <p class="m-0 text-sm text-n-slate-11">
            {{ t(`${NS}.AVANCADO.TEXTO`) }}
          </p>
          <AgenteBotao
            variante="contorno"
            icone="i-lucide-wrench"
            data-vitrine-criar
            @click="criarAMinha"
          >
            {{ t(`${NS}.AVANCADO.BOTAO`) }}
          </AgenteBotao>
        </div>
      </template>
    </div>

    <VitrineDetalhe
      v-if="aberta"
      :ferramenta="aberta"
      :agentes="agentes"
      :agente-inicial="agenteDaRota?.id ?? null"
      @fechar="aberta = null"
      @ver-agente="verFerramentasDoAgente"
    />
  </div>
</template>
