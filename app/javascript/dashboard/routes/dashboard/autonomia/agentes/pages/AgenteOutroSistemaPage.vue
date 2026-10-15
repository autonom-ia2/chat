<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useCanManage } from 'dashboard/composables/useCanManage';
import { useCanaisOcupados } from '../composables/useCanaisOcupados';
import { ESTADO } from '../utils/estadoDoAgente';
import PaginaHeroi from '../components/pagina/PaginaHeroi.vue';
import DialogoAcao from '../components/pagina/DialogoAcao.vue';
import AgenteBotao from '../components/AgenteBotao.vue';
import ChaveDeAcesso from '../components/ChaveDeAcesso.vue';
import GavetaAlterarOutro from '../components/GavetaAlterarOutro.vue';

// #1648 (mockup-2, ajuste do Rodrigo) — a página do agente de outro sistema (agent_bot webhook) é a
// mesma página dos nossos agentes: o herói (nome, foto, selo Atendendo/Parado e onde atende) e as
// seções no padrão da PaginaBlocos. Seções: O que ele faz · Como ele se conecta (endereço e chave) ·
// Onde atende (os canais em que atende primeiro; troca-se na aba Agente de IA de cada canal).
// "Alterar" abre a gaveta da seção com Cancelar e Salvar, como nas nossas seções. "Apagar agente"
// e "Mudar nome e foto" ficam no "⋯" do herói. Mesma rota da página dos nossos agentes, com
// `?origem=webhook` (os ids de agent_bot e de agente da plataforma podem coincidir).
const props = defineProps({
  botId: { type: [String, Number], required: true },
});

const NS = 'AGENTS.OUTRO_SISTEMA.PAGINA';
const { t } = useI18n();
const router = useRouter();
const store = useStore();
const podeGerenciar = useCanManage('autonomia_manage');
const bots = useMapGetter('agentBots/getBots');
const ocupacao = useCanaisOcupados();

const alterando = ref(null);
const dialogoApagar = ref(null);

const agente = computed(() =>
  (bots.value || []).find(bot => String(bot.id) === String(props.botId))
);
const nome = computed(() => agente.value?.name || '');
const canais = computed(() =>
  ocupacao.canais.value.filter(
    canal =>
      canal.occupied_by?.kind === 'external' &&
      String(canal.occupied_by.agent_bot_id) === String(props.botId)
  )
);
const estado = computed(() =>
  canais.value.length ? ESTADO.ATENDENDO : ESTADO.PARADO
);
const onde = computed(() => {
  const total = canais.value.length;
  if (!total) return t('AGENTS.JORNADA.CARTAO.ONDE_NENHUM');
  if (total === 1) {
    return t('AGENTS.JORNADA.CARTAO.ONDE_CANAL', {
      canal: canais.value[0].name,
    });
  }
  return t('AGENTS.JORNADA.CARTAO.ONDE_N_CANAIS', { n: total }, total);
});

const hrefLista = computed(
  () => router.resolve({ name: 'autonomia_agents_index' }).href
);
const irParaLista = () => router.push({ name: 'autonomia_agents_index' });
const rotaDoCanal = canal => ({
  name: 'settings_inbox_show',
  params: { inboxId: canal.inbox_id, tab: 'bot-configuration' },
});

const itensMais = computed(() =>
  podeGerenciar.value
    ? [
        {
          chave: 'nome-foto',
          texto: t(`${NS}.MENU_NOME_FOTO`),
          icone: 'i-lucide-image',
        },
        {
          chave: 'apagar',
          texto: t('AGENTS.OUTRO_SISTEMA.APAGAR'),
          icone: 'i-lucide-trash-2',
          perigo: true,
          separar: true,
        },
      ]
    : []
);

const escolherMais = chave => {
  if (chave === 'apagar') dialogoApagar.value?.abrir();
  else alterando.value = chave;
};

const apagar = async () => {
  await store.dispatch('agentBots/delete', agente.value.id);
  useAlert(t('AGENTS.OUTRO_SISTEMA.APAGOU'));
  irParaLista();
};

const BLOCO = 'flex flex-col gap-3 p-5 sm:flex-row sm:items-start';
const ICONE = 'grid rounded-lg place-items-center size-9 shrink-0 bg-n-alpha-2';
const ALTERAR =
  'max-sm:w-full max-sm:ring-1 max-sm:ring-inset max-sm:ring-n-blue-9 shrink-0';

onMounted(() => {
  store.dispatch('agentBots/get');
});
</script>

<template>
  <div class="w-full h-full overflow-y-auto bg-n-background">
    <div
      class="relative flex flex-col w-full max-w-[55rem] gap-6 px-4 py-6 mx-auto md:px-6"
    >
      <template v-if="!agente">
        <p role="status" class="sr-only">{{ t(`${NS}.CARREGANDO`) }}</p>
        <div
          data-esqueleto
          aria-hidden="true"
          class="flex items-center gap-4 px-6 py-8 rounded-3xl bg-[#0D2344] dark:bg-[#12305E]"
        >
          <span
            class="rounded-full size-16 bg-white/15 motion-safe:animate-pulse"
          />
          <span
            class="w-2/5 h-7 rounded-lg bg-white/15 motion-safe:animate-pulse"
          />
        </div>
      </template>

      <template v-else>
        <PaginaHeroi
          :nome="nome"
          :foto="agente.thumbnail || ''"
          :estado="estado"
          :onde="onde"
          :href-lista="hrefLista"
          :itens-mais="itensMais"
          @voltar-lista="irParaLista"
          @mais="escolherMais"
        />

        <section
          data-bloco="outro-sistema"
          :aria-label="nome"
          class="flex flex-col shadow-sm divide-y rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak dark:ring-n-slate-6 divide-n-weak"
        >
          <div data-linha="faz" :class="BLOCO">
            <div class="flex items-start flex-1 min-w-0 gap-3">
              <span :class="ICONE" aria-hidden="true">
                <span
                  class="i-lucide-message-square-text size-5 text-n-slate-11"
                />
              </span>
              <div class="flex flex-col flex-1 min-w-0 gap-1">
                <h2 class="m-0 text-sm font-semibold text-n-slate-11">
                  {{ t(`${NS}.BLOCO_FAZ`) }}
                </h2>
                <p class="m-0 text-sm text-n-slate-12">
                  {{ agente.description || t(`${NS}.FAZ_VAZIO`) }}
                </p>
              </div>
            </div>
            <AgenteBotao
              v-if="podeGerenciar"
              data-alterar="faz"
              :class="ALTERAR"
              variante="fantasma"
              @click="alterando = 'faz'"
            >
              {{ t(`${NS}.ALTERAR`) }}
            </AgenteBotao>
          </div>

          <div data-linha="conexao" class="flex flex-col gap-4 p-5">
            <div class="flex flex-col gap-3 sm:flex-row sm:items-start">
              <div class="flex items-start flex-1 min-w-0 gap-3">
                <span :class="ICONE" aria-hidden="true">
                  <span class="i-lucide-link size-5 text-n-slate-11" />
                </span>
                <div class="flex flex-col flex-1 min-w-0 gap-1">
                  <h2 class="m-0 text-sm font-semibold text-n-slate-11">
                    {{ t(`${NS}.BLOCO_CONEXAO`) }}
                  </h2>
                  <p class="m-0 text-sm text-n-slate-11">
                    {{ t(`${NS}.CONEXAO_TEXTO`) }}
                  </p>
                  <p
                    data-endereco
                    class="m-0 font-mono text-sm break-all text-n-slate-12"
                  >
                    {{ agente.outgoing_url }}
                  </p>
                </div>
              </div>
              <AgenteBotao
                v-if="podeGerenciar"
                data-alterar="conexao"
                :class="ALTERAR"
                variante="fantasma"
                @click="alterando = 'conexao'"
              >
                {{ t(`${NS}.ALTERAR`) }}
              </AgenteBotao>
            </div>
            <ChaveDeAcesso
              v-if="podeGerenciar && agente.access_token"
              class="sm:ps-12"
              :valor="agente.access_token"
            />
          </div>

          <div data-linha="onde" class="flex flex-col gap-3 p-5">
            <div class="flex items-start gap-3">
              <span :class="ICONE" aria-hidden="true">
                <span class="i-lucide-map-pin size-5 text-n-slate-11" />
              </span>
              <div class="flex flex-col flex-1 min-w-0 gap-1">
                <h2 class="m-0 text-sm font-semibold text-n-slate-11">
                  {{ t(`${NS}.BLOCO_ONDE`) }}
                </h2>
                <p class="m-0 text-sm text-n-slate-12">
                  {{
                    canais.length
                      ? t(`${NS}.ONDE_TEXTO`)
                      : t(`${NS}.ONDE_NENHUM`)
                  }}
                </p>
              </div>
            </div>
            <ul
              v-if="canais.length"
              class="flex flex-col gap-2 p-0 m-0 list-none sm:ps-12"
            >
              <li
                v-for="canal in canais"
                :key="canal.inbox_id"
                data-canal
                class="flex flex-wrap items-center justify-between gap-2 px-3 py-1 rounded-xl bg-n-slate-2"
              >
                <span class="flex items-center gap-2 text-sm text-n-slate-12">
                  <span
                    class="i-lucide-message-circle size-4 text-n-slate-11"
                    aria-hidden="true"
                  />
                  {{ canal.name }}
                </span>
                <router-link
                  :to="rotaDoCanal(canal)"
                  class="inline-flex items-center gap-1 px-2 text-sm font-semibold rounded-lg min-h-11 text-n-blue-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
                >
                  {{ t(`${NS}.ABRIR_CANAL`) }}
                  <span
                    class="i-lucide-arrow-right size-4 rtl:rotate-180"
                    aria-hidden="true"
                  />
                </router-link>
              </li>
            </ul>
            <p class="m-0 text-sm text-n-slate-11 sm:ps-12">
              {{ t(`${NS}.ONDE_COMO`) }}
            </p>
          </div>
        </section>
      </template>
    </div>

    <GavetaAlterarOutro
      v-if="agente && alterando"
      :agente="agente"
      :campo="alterando"
      @fechar="alterando = null"
    />
    <DialogoAcao
      v-if="agente"
      ref="dialogoApagar"
      :titulo="t('AGENTS.OUTRO_SISTEMA.APAGAR_TITULO', { nome })"
      :texto="t('AGENTS.OUTRO_SISTEMA.APAGAR_TEXTO')"
      :confirmar="t('AGENTS.OUTRO_SISTEMA.APAGAR_CONFIRMAR')"
      :rotulo-carregando="t(`${NS}.APAGANDO`)"
      variante="perigo"
      :erro-titulo="t(`${NS}.APAGAR_ERRO`)"
      :erro-garantia="t(`${NS}.APAGAR_ERRO_GARANTIA`, { nome })"
      :executar="apagar"
    />
  </div>
</template>
