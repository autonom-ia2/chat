<script setup>
import { computed, onMounted, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import AgenteBotao from '../AgenteBotao.vue';
import AgendaEstado from './AgendaEstado.vue';
import ResumoOndeTrabalha from '../onde/ResumoOndeTrabalha.vue';
import { usePermissoesDaJornada } from '../../composables/usePermissoesDaJornada';
import { useAgendaDoAgente } from '../../composables/useAgendaDoAgente';
import { useAgendaNovaNaConta } from '../../composables/useAgendaNovaNaConta';

// #1181 PR3 (protótipo T07, blocksT07) — os blocos claros da página do agente:
// - Testar: a pergunta vai para a gaveta Testar;
// - resumo com "Alterar": O que sabe, Onde e quando responde, Nome e jeito de falar;
// - Quando passa para a equipe: a frase da Atribuição e "Escolher quem recebe" só para quem pode
//   (DECISOES.md item 8); quem recebe é definido lá, de propósito.
// Agente escrito à mão troca "Mudar conversando" por "Editar instruções". Cotação mostra só onde e
// quando e leva o resto ao módulo de cotação. Interno não tem onde e quando. Quem só vê lê e testa.
// #1433 (tema 13): o agente da equipe troca "Onde e quando responde" por "Onde {nome} trabalha" (caixa e
// papel); "Mudar" abre direto nos passos do agente da equipe.
// Tema 14 (#1434): o ajudante não fala com cliente: sem "Testar" (como cliente) e sem "Quando passa para a
// equipe". No lugar, "Quem {nome} ajuda" e "Quando chamar", e cada "Mudar" abre direto os passos do ajudante.
const props = defineProps({
  agente: { type: Object, required: true },
  nome: { type: String, required: true },
  podeGerenciar: { type: Boolean, default: false },
  manual: { type: Boolean, default: false },
  cotacao: { type: Boolean, default: false },
  interno: { type: Boolean, default: false },
  temCanal: { type: Boolean, default: false },
  textoOnde: { type: String, default: '' },
  // #1433: nomes das outras caixas em que ele também recebe quando alguém passa (agente da equipe nelas).
  tambemRecebe: { type: Array, default: () => [] },
  quantasFontes: { type: Number, default: 0 },
  quantasPerguntas: { type: Number, default: 0 },
  // #1426 — materiais que precisam do dono (a revisão não aprovou ou não deu para ler). Só a Fase 2 manda.
  problemasNoMaterial: { type: Number, default: 0 },
  // #1433: linhas da L2 em que o agente está na equipe, ou null quando ele não é agente da equipe.
  equipe: { type: Array, default: null },
  caixas: { type: Array, default: () => [] },
  // #1720 — com a Fase 2, "Onde e quando responde" é uma linha só (`textoOnde`, a mesma do herói) e "Alterar"
  // vale também para quem só recebe quando alguém passa. Sem ela, como antes.
  fase2: { type: Boolean, default: false },
  // Tema 14: { principais: [{ id, name }], quando } quando o agente é ajudante, ou null.
  ajuda: { type: Object, default: null },
});

const emit = defineEmits([
  'perguntar',
  'abrir',
  'mudar',
  'escrever',
  'escolherCanal',
  'mudarEquipe',
  'mudarAjuda',
]);

const { t } = useI18n();
const router = useRouter();
const { podeEscolherQuemRecebe, podeAbrirAgendamento, crmLigado } =
  usePermissoesDaJornada();
const NS = 'AGENTS.JORNADA.PAGINA';
const base = `blocos-${useId()}`;
const pergunta = ref('');

const linkQuemRecebe = computed(
  () => router.resolve({ name: 'crm_handoff_settings_index' }).href
);
const linkCotacao = computed(
  () => router.resolve({ name: 'autonomia_insurance_agent' }).href
);

const perguntar = () => {
  const texto = pergunta.value.trim();
  if (!texto) return;
  pergunta.value = '';
  emit('perguntar', texto);
};

// #1369 — sem o resumo da IA (ele só chega depois que os arquivos e sites são revisados), a frase
// segue a contagem logo abaixo: com arquivo ou site, não diz que sabe só a conversa.
const textoSabe = computed(() => {
  if (props.agente.knowledge_summary) return props.agente.knowledge_summary;
  if (!props.quantasFontes) {
    return t(`${NS}.BLOCO_SABE.TEXTO`, { nome: props.nome });
  }
  return t(
    `${NS}.BLOCO_SABE.TEXTO_COM_FONTES`,
    { nome: props.nome },
    props.quantasFontes
  );
});

// #1253 — Marca reuniões: a mesma regra do "Marcar reuniões" do painel antigo (useAgendaDoAgente).
// Só com a agenda nova na conta (`crm_booking_v2`); some na cotação, no agente sem agenda e quando
// a API de páginas responde erro (inclusive para quem não vê Agendamento).
const agendaNaConta = useAgendaNovaNaConta();
const agenda = useAgendaDoAgente(() => props.agente);
const mostrarAgenda = computed(
  () => agendaNaConta.value && !props.cotacao && agenda.disponivel.value
);
// #1181 (item A) — a frase diz o estado real da página salva (AgendaEstado).
const estadoAgenda = computed(() => agenda.estadoDe(agenda.paginaSalva.value));
const paginaAgenda = computed(() => {
  const pagina = agenda.paginaDe(agenda.paginaSalva.value);
  return pagina ? agenda.tituloDaPagina(pagina) : '';
});
const linkPaginas = computed(() =>
  podeAbrirAgendamento.value
    ? router.resolve({ name: 'settings_booking' }).href
    : ''
);

onMounted(() => {
  if (agendaNaConta.value && !props.cotacao) agenda.carregar();
});
</script>

<template>
  <div class="flex flex-col gap-4">
    <section
      v-if="!cotacao && !ajuda"
      data-bloco="testar"
      :aria-labelledby="`${base}-testar`"
      class="flex flex-col gap-3 p-5 shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak dark:ring-n-slate-6"
    >
      <div class="flex items-start gap-3">
        <span
          class="grid rounded-lg place-items-center size-9 shrink-0 bg-n-alpha-2"
          aria-hidden="true"
        >
          <span class="i-lucide-flask-conical size-5 text-n-slate-11" />
        </span>
        <div class="flex flex-col flex-1 min-w-0 gap-1">
          <h2
            :id="`${base}-testar`"
            class="m-0 text-base font-semibold text-n-slate-12"
          >
            {{ t(`${NS}.BLOCO_TESTAR.TITULO`) }}
          </h2>
          <p class="m-0 text-sm text-n-slate-11">
            {{ t(`${NS}.BLOCO_TESTAR.TEXTO`) }}
          </p>
        </div>
      </div>
      <form
        class="relative flex flex-col gap-2 sm:flex-row"
        @submit.prevent="perguntar"
      >
        <label :for="`${base}-pergunta`" class="sr-only">
          {{ t(`${NS}.BLOCO_TESTAR.PERGUNTE`, { nome }) }}
        </label>
        <input
          :id="`${base}-pergunta`"
          v-model="pergunta"
          data-pergunta
          autocomplete="off"
          :placeholder="t(`${NS}.BLOCO_TESTAR.PERGUNTE`, { nome })"
          class="flex-1 min-w-0 px-3 text-base rounded-xl min-h-12 bg-n-solid-1 ring-1 ring-inset ring-n-slate-7 border-0 !mb-0 text-n-slate-12 placeholder:text-n-slate-10"
        />
        <AgenteBotao
          type="submit"
          data-perguntar
          variante="contorno"
          tamanho="lg"
          class="w-full sm:w-auto"
        >
          {{ t(`${NS}.BLOCO_TESTAR.ENVIAR`) }}
        </AgenteBotao>
      </form>
    </section>

    <section
      data-bloco="resumo"
      :aria-label="t(`${NS}.RESUMO`, { nome })"
      class="flex flex-col shadow-sm divide-y rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak dark:ring-n-slate-6 divide-n-weak"
    >
      <div
        v-if="!cotacao"
        data-linha="sabe"
        role="group"
        :aria-labelledby="`${base}-sabe`"
        class="flex flex-col gap-3 p-5 sm:flex-row sm:items-start"
      >
        <div class="flex items-start flex-1 min-w-0 gap-3">
          <span
            class="grid rounded-lg place-items-center size-9 shrink-0 bg-n-alpha-2"
            aria-hidden="true"
          >
            <span class="i-lucide-book-open size-5 text-n-slate-11" />
          </span>
          <div class="flex flex-col flex-1 min-w-0 gap-1">
            <h3
              :id="`${base}-sabe`"
              class="m-0 text-sm font-semibold text-n-slate-11"
            >
              {{ t(`${NS}.BLOCO_SABE.TITULO`) }}
            </h3>
            <p class="m-0 text-sm text-n-slate-12">{{ textoSabe }}</p>
            <p class="flex items-center gap-1 m-0 text-sm text-n-slate-11">
              <span
                :class="
                  quantasFontes
                    ? 'i-lucide-file-text'
                    : 'i-lucide-message-circle'
                "
                class="size-4 shrink-0"
                aria-hidden="true"
              />
              {{
                quantasFontes
                  ? t(
                      `${NS}.BLOCO_SABE.N_FONTES`,
                      { n: quantasFontes },
                      quantasFontes
                    )
                  : t(`${NS}.BLOCO_SABE.SO_CONVERSA`)
              }}
            </p>
            <p
              v-if="podeGerenciar && quantasPerguntas"
              data-perguntas-para-conferir
              class="flex items-center gap-1.5 px-2.5 py-1 m-0 text-sm font-medium rounded-lg w-fit bg-n-amber-2 ring-1 ring-inset ring-n-amber-6 text-n-slate-12"
            >
              <span
                class="i-lucide-info size-4 shrink-0 text-n-amber-11"
                aria-hidden="true"
              />
              {{
                t(
                  `${NS}.BLOCO_SABE.N_PERGUNTAS`,
                  { n: quantasPerguntas },
                  quantasPerguntas
                )
              }}
            </p>
            <p
              v-if="podeGerenciar && problemasNoMaterial"
              data-problemas-no-material
              class="flex items-center gap-1.5 px-2.5 py-1 m-0 text-sm font-medium rounded-lg w-fit bg-n-amber-2 ring-1 ring-inset ring-n-amber-6 text-n-slate-12"
            >
              <span
                class="i-lucide-hand size-4 shrink-0 text-n-amber-11"
                aria-hidden="true"
              />
              {{
                t(
                  `${NS}.BLOCO_SABE.N_PROBLEMAS`,
                  { n: problemasNoMaterial },
                  problemasNoMaterial
                )
              }}
            </p>
          </div>
        </div>
        <AgenteBotao
          data-alterar="sabe"
          class="max-sm:w-full max-sm:ring-1 max-sm:ring-inset max-sm:ring-n-blue-9 shrink-0"
          variante="fantasma"
          :aria-label="
            podeGerenciar
              ? t(`${NS}.BLOCO_SABE.ALTERAR_ARIA`)
              : t(`${NS}.BLOCO_SABE.VER_ARIA`)
          "
          @click="emit('abrir', 'sabe')"
        >
          {{ podeGerenciar ? t(`${NS}.ALTERAR`) : t(`${NS}.VER`) }}
        </AgenteBotao>
      </div>

      <template v-if="ajuda">
        <div
          data-linha="quem-ajuda"
          role="group"
          :aria-labelledby="`${base}-quem-ajuda`"
          class="flex flex-col gap-3 p-5 sm:flex-row sm:items-start"
        >
          <div class="flex items-start flex-1 min-w-0 gap-3">
            <span
              class="grid rounded-lg place-items-center size-9 shrink-0 bg-n-iris-3"
              aria-hidden="true"
            >
              <span class="i-lucide-bot size-5 text-n-iris-11" />
            </span>
            <div class="flex flex-col flex-1 min-w-0 gap-1">
              <h3
                :id="`${base}-quem-ajuda`"
                class="m-0 text-sm font-semibold text-n-slate-11"
              >
                {{ t('AGENTS.JORNADA.AJUDANTE.QUEM_AJUDA', { nome }) }}
              </h3>
              <p data-quem-ajuda class="m-0 text-sm text-n-slate-12">
                {{
                  ajuda.principais.length
                    ? ajuda.principais
                        .map(principal => principal.name)
                        .join(', ')
                    : t('AGENTS.JORNADA.AJUDANTE.NINGUEM', { nome })
                }}
              </p>
              <p class="m-0 text-sm text-n-slate-11">
                {{ t('AGENTS.JORNADA.AJUDANTE.NUNCA_CLIENTE', { nome }) }}
              </p>
            </div>
          </div>
          <AgenteBotao
            v-if="podeGerenciar"
            data-mudar-ajuda="quem"
            class="max-sm:w-full max-sm:ring-1 max-sm:ring-inset max-sm:ring-n-blue-9 shrink-0"
            variante="fantasma"
            :aria-label="t('AGENTS.JORNADA.AJUDANTE.MUDAR_ARIA', { nome })"
            @click="emit('mudarAjuda', 'quem')"
          >
            {{ t('AGENTS.JORNADA.ONDE.MUDAR') }}
          </AgenteBotao>
        </div>
        <div
          data-linha="quando-chamar"
          role="group"
          :aria-labelledby="`${base}-quando-chamar`"
          class="flex flex-col gap-3 p-5 sm:flex-row sm:items-start"
        >
          <div class="flex items-start flex-1 min-w-0 gap-3">
            <span
              class="grid rounded-lg place-items-center size-9 shrink-0 bg-n-alpha-2"
              aria-hidden="true"
            >
              <span class="i-lucide-bell-ring size-5 text-n-slate-11" />
            </span>
            <div class="flex flex-col flex-1 min-w-0 gap-1">
              <h3
                :id="`${base}-quando-chamar`"
                class="m-0 text-sm font-semibold text-n-slate-11"
              >
                {{ t('AGENTS.JORNADA.AJUDANTE.QUANDO.ROTULO') }}
              </h3>
              <p data-quando-chamar class="m-0 text-sm text-n-slate-12">
                {{
                  ajuda.quando ||
                  t('AGENTS.JORNADA.AJUDANTE.QUANDO.SEM_LEITURA')
                }}
              </p>
            </div>
          </div>
          <AgenteBotao
            v-if="podeGerenciar"
            data-mudar-ajuda="quando"
            class="max-sm:w-full max-sm:ring-1 max-sm:ring-inset max-sm:ring-n-blue-9 shrink-0"
            variante="fantasma"
            :aria-label="
              t('AGENTS.JORNADA.AJUDANTE.MUDAR_QUANDO_ARIA', { nome })
            "
            @click="emit('mudarAjuda', 'quando')"
          >
            {{ t('AGENTS.JORNADA.ONDE.MUDAR') }}
          </AgenteBotao>
        </div>
      </template>

      <div
        v-else-if="equipe"
        data-linha="onde-trabalha"
        role="group"
        :aria-labelledby="`${base}-onde-trabalha`"
        class="flex flex-col gap-3 p-5 sm:flex-row sm:items-start"
      >
        <div class="flex items-start flex-1 min-w-0 gap-3">
          <span
            class="grid rounded-lg place-items-center size-9 shrink-0 bg-n-alpha-2"
            aria-hidden="true"
          >
            <span class="i-lucide-map-pin size-5 text-n-slate-11" />
          </span>
          <div class="flex flex-col flex-1 min-w-0 gap-2">
            <h3
              :id="`${base}-onde-trabalha`"
              class="m-0 text-sm font-semibold text-n-slate-11"
            >
              {{ t('AGENTS.JORNADA.ONDE.TITULO', { nome }) }}
            </h3>
            <ResumoOndeTrabalha
              v-if="equipe.length"
              :canais="equipe"
              :caixas="caixas"
            />
            <p v-else class="m-0 text-sm text-n-slate-12">
              {{ t('AGENTS.JORNADA.ONDE.RECEBE') }}
            </p>
            <!-- #1433: aqui entra "Escolher de quais funis ele cuida", quando a tela do CRM existir
              (a rota vem do Multifunnel, #1447). Até lá, sem botão. -->
          </div>
        </div>
        <AgenteBotao
          v-if="podeGerenciar"
          data-mudar-equipe
          class="max-sm:w-full max-sm:ring-1 max-sm:ring-inset max-sm:ring-n-blue-9 shrink-0"
          variante="fantasma"
          :aria-label="t('AGENTS.JORNADA.ONDE.MUDAR_ARIA', { nome })"
          @click="emit('mudarEquipe')"
        >
          {{ t('AGENTS.JORNADA.ONDE.MUDAR') }}
        </AgenteBotao>
      </div>

      <div
        v-else-if="!interno"
        data-linha="onde"
        role="group"
        :aria-labelledby="`${base}-onde`"
        class="flex flex-col gap-3 p-5 sm:flex-row sm:items-start"
      >
        <div class="flex items-start flex-1 min-w-0 gap-3">
          <span
            class="grid rounded-lg place-items-center size-9 shrink-0 bg-n-alpha-2"
            aria-hidden="true"
          >
            <span class="i-lucide-map-pin size-5 text-n-slate-11" />
          </span>
          <div class="flex flex-col flex-1 min-w-0 gap-1">
            <h3
              :id="`${base}-onde`"
              class="m-0 text-sm font-semibold text-n-slate-11"
            >
              {{ t(`${NS}.BLOCO_ONDE.TITULO`) }}
            </h3>
            <p
              v-if="fase2"
              data-resumo-onde
              class="m-0 text-sm text-n-slate-12"
            >
              {{ textoOnde }}
            </p>
            <p v-else class="m-0 text-sm text-n-slate-12">
              {{ temCanal ? textoOnde : t(`${NS}.NENHUM_CANAL`) }}
            </p>
            <p
              v-if="!fase2 && tambemRecebe.length"
              data-tambem-recebe
              class="m-0 text-sm text-n-slate-12"
            >
              {{
                t(`${NS}.BLOCO_ONDE.TAMBEM`, {
                  caixas: tambemRecebe.join(', '),
                })
              }}
            </p>
          </div>
        </div>
        <template v-if="podeGerenciar">
          <AgenteBotao
            v-if="temCanal || (fase2 && tambemRecebe.length)"
            data-alterar="onde"
            class="max-sm:w-full max-sm:ring-1 max-sm:ring-inset max-sm:ring-n-blue-9 shrink-0"
            variante="fantasma"
            :aria-label="t(`${NS}.BLOCO_ONDE.ALTERAR_ARIA`)"
            @click="emit('abrir', 'onde')"
          >
            {{ t(`${NS}.ALTERAR`) }}
          </AgenteBotao>
          <AgenteBotao
            v-else
            data-escolher-canal
            class="max-sm:w-full max-sm:ring-1 max-sm:ring-inset max-sm:ring-n-blue-9 shrink-0"
            variante="contorno"
            @click="emit('escolherCanal')"
          >
            {{ t(`${NS}.BLOCO_ONDE.ESCOLHER_CANAL`) }}
          </AgenteBotao>
        </template>
      </div>

      <div
        v-if="!cotacao"
        data-linha="jeito"
        role="group"
        :aria-labelledby="`${base}-jeito`"
        class="flex flex-col gap-3 p-5 sm:flex-row sm:items-start"
      >
        <div class="flex items-start flex-1 min-w-0 gap-3">
          <span
            class="grid rounded-lg place-items-center size-9 shrink-0 bg-n-alpha-2"
            aria-hidden="true"
          >
            <span class="i-lucide-smile size-5 text-n-slate-11" />
          </span>
          <div class="flex flex-col flex-1 min-w-0 gap-1">
            <h3
              :id="`${base}-jeito`"
              class="m-0 text-sm font-semibold text-n-slate-11"
            >
              {{ t(`${NS}.BLOCO_JEITO.TITULO`) }}
            </h3>
            <p class="m-0 text-sm text-n-slate-12">
              {{ t(`${NS}.BLOCO_JEITO.TEXTO`, { nome }) }}
            </p>
            <p
              v-if="manual"
              class="flex items-center gap-1 m-0 text-sm text-n-slate-11"
            >
              <span
                class="i-lucide-pencil size-4 shrink-0"
                aria-hidden="true"
              />
              {{ t(`${NS}.BLOCO_JEITO.MANUAL`) }}
            </p>
          </div>
        </div>
        <template v-if="podeGerenciar">
          <AgenteBotao
            v-if="manual"
            data-alterar="instrucoes"
            class="max-sm:w-full max-sm:ring-1 max-sm:ring-inset max-sm:ring-n-blue-9 shrink-0"
            variante="fantasma"
            @click="emit('escrever')"
          >
            {{ t(`${NS}.EDITAR_INSTRUCOES`) }}
          </AgenteBotao>
          <AgenteBotao
            v-else
            data-alterar="jeito"
            class="max-sm:w-full max-sm:ring-1 max-sm:ring-inset max-sm:ring-n-blue-9 shrink-0"
            variante="fantasma"
            :aria-label="t(`${NS}.BLOCO_JEITO.ALTERAR_ARIA`)"
            @click="emit('mudar', 'jeito')"
          >
            {{ t(`${NS}.ALTERAR`) }}
          </AgenteBotao>
        </template>
      </div>

      <!-- #1429 F3: a linha "Base de seguros" (BaseDoAgenteLinha), quando a página a manda. -->
      <slot name="base" />

      <div
        v-if="mostrarAgenda"
        data-linha="agenda"
        role="group"
        :aria-labelledby="`${base}-agenda`"
        class="flex flex-col gap-3 p-5 sm:flex-row sm:items-start"
      >
        <div class="flex items-start flex-1 min-w-0 gap-3">
          <span
            class="grid rounded-lg place-items-center size-9 shrink-0 bg-n-alpha-2"
            aria-hidden="true"
          >
            <span class="i-lucide-calendar-check size-5 text-n-slate-11" />
          </span>
          <div class="flex flex-col flex-1 min-w-0 gap-1">
            <h3
              :id="`${base}-agenda`"
              class="m-0 text-sm font-semibold text-n-slate-11"
            >
              {{ t(`${NS}.BLOCO_AGENDA.TITULO`) }}
            </h3>
            <AgendaEstado
              :estado="estadoAgenda"
              :nome="nome"
              :pagina="paginaAgenda"
              :link-paginas="linkPaginas"
              :gerencia="podeGerenciar"
            />
          </div>
        </div>
        <AgenteBotao
          v-if="podeGerenciar"
          data-alterar="agenda"
          class="max-sm:w-full max-sm:ring-1 max-sm:ring-inset max-sm:ring-n-blue-9 shrink-0"
          variante="fantasma"
          :aria-label="t(`${NS}.BLOCO_AGENDA.ALTERAR_ARIA`)"
          @click="emit('abrir', 'agenda')"
        >
          {{ t(`${NS}.ALTERAR`) }}
        </AgenteBotao>
      </div>
    </section>

    <section
      v-if="cotacao"
      data-bloco="cotacao"
      :aria-labelledby="`${base}-cotacao`"
      class="flex flex-col items-start gap-3 p-5 shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak dark:ring-n-slate-6"
    >
      <h2
        :id="`${base}-cotacao`"
        class="m-0 text-base font-semibold text-n-slate-12"
      >
        {{ t(`${NS}.BLOCO_COTACAO.TITULO`) }}
      </h2>
      <p class="m-0 text-sm text-n-slate-11">
        {{ t(`${NS}.BLOCO_COTACAO.TEXTO`, { nome }) }}
      </p>
      <a
        data-abrir-cotacao
        :href="linkCotacao"
        class="inline-flex items-center gap-1 text-sm font-semibold underline min-h-11 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
      >
        {{ t(`${NS}.BLOCO_COTACAO.ABRIR`) }}
        <span
          class="i-lucide-arrow-right size-4 rtl:rotate-180"
          aria-hidden="true"
        />
      </a>
    </section>

    <section
      v-else-if="!ajuda"
      data-bloco="passa"
      :aria-labelledby="`${base}-passa`"
      class="flex flex-col gap-3 p-5 shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak dark:ring-n-slate-6"
    >
      <div class="flex items-start gap-3">
        <span
          class="grid rounded-lg place-items-center size-9 shrink-0 bg-n-alpha-2"
          aria-hidden="true"
        >
          <span class="i-lucide-users size-5 text-n-slate-11" />
        </span>
        <div class="flex flex-col flex-1 min-w-0 gap-1">
          <h2
            :id="`${base}-passa`"
            class="m-0 text-base font-semibold text-n-slate-12"
          >
            {{ t(`${NS}.BLOCO_PASSA.TITULO`) }}
          </h2>
          <p class="m-0 text-sm text-n-slate-11">
            {{ t(`${NS}.BLOCO_PASSA.TEXTO`, { nome }) }}
          </p>
        </div>
      </div>
      <a
        v-if="podeEscolherQuemRecebe"
        data-quem-recebe
        :href="linkQuemRecebe"
        target="_blank"
        rel="noopener noreferrer"
        class="relative inline-flex items-center gap-1 text-sm font-semibold underline min-h-11 w-fit text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
      >
        {{ t('AGENTS.JORNADA.ONDE_QUANDO.ESCOLHER_QUEM_RECEBE') }}
        <span class="i-lucide-external-link size-4" aria-hidden="true" />
        <span class="sr-only">{{ t('AGENTS.JORNADA.COMUM.NOVA_ABA') }}</span>
      </a>
      <p
        v-else-if="crmLigado"
        data-sem-permissao
        class="m-0 text-sm text-n-slate-11"
      >
        {{ t('AGENTS.JORNADA.ONDE_QUANDO.QUEM_RECEBE_SEM_PERMISSAO') }}
      </p>
      <p v-if="podeGerenciar" class="m-0 text-sm text-n-slate-11">
        {{
          manual
            ? t(`${NS}.BLOCO_PASSA.MANUAL`, { nome })
            : t(`${NS}.BLOCO_PASSA.MUDAR`, { nome })
        }}
      </p>
    </section>
  </div>
</template>
