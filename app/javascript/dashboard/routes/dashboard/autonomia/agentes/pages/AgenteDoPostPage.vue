<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import AgenteBotao from '../components/AgenteBotao.vue';
import GavetaSabeDoPost from '../components/doPost/GavetaSabeDoPost.vue';
import GavetaTestarDoPost from '../components/doPost/GavetaTestarDoPost.vue';
import GavetaComentariosDoPost from '../components/doPost/GavetaComentariosDoPost.vue';
import {
  ICONE_DA_REDE,
  agentesDasPortas,
  motivosDasPortas,
  estadoDoCuidado,
  redesDoCuidado,
  tituloDaLegenda,
  useAgenteDoPost,
  useFlags,
} from '../composables/useAgentesDoPost';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

// #2469 (PR 3a do #2436) — a página do cartão de um post ou anúncio em Agentes. Três gavetas, uma ação em cada: o que
// sabe (a base do agente da porta e o que é só deste post), testar e os comentários (respondidos, esperando você,
// não respondo). Pausar, voltar a cuidar e editar (os passos do cuidado) para quem pode mudar o cuidado. `?gaveta=`
// abre uma direto, e `&grupo=` escolhe o grupo dos comentários (a faixa "N esperando você" do cartão).
const props = defineProps({
  careId: { type: String, required: true },
});

const { t } = useI18n();
const route = useRoute();
const KEY = 'AGENTS.AGENTE_DO_POST';
const GAVETAS = [
  { chave: 'sabe', icone: 'i-lucide-book-open', titulo: 'SABE' },
  {
    chave: 'testar',
    icone: 'i-lucide-message-circle-question',
    titulo: 'TESTAR',
  },
  {
    chave: 'comentarios',
    icone: 'i-lucide-messages-square',
    titulo: 'COMENTARIOS',
  },
];
const GRUPOS = ['respondidos', 'esperando', 'nao_respondo'];
const ERRO = {
  acesso: 'ACESSO',
  sumiu: 'SUMIU',
  rede: 'ERRO',
};

const {
  detalhe,
  carregando,
  erro,
  motivo,
  mudando,
  carregar,
  mudarEstado,
  testar,
} = useAgenteDoPost(() => props.careId);

const estado = computed(() => estadoDoCuidado(detalhe.value?.status));
// Quantos esperam o dono; null quando a Meta não deixou ler os comentários (nunca um zero falso).
const esperando = computed(() => {
  const comentarios = detalhe.value?.comentarios;
  return comentarios?.status === 'ready' ? comentarios.esperando.length : null;
});
const legenda = computed(() => tituloDaLegenda(detalhe.value?.legenda || ''));
const redes = computed(() => redesDoCuidado(detalhe.value?.network));
const agentes = computed(() => agentesDasPortas(detalhe.value?.portas));
// #2487 — o motivo de verdade de cada porta que não escreve, no lugar do "Sem agente para escrever".
const motivos = computed(() => motivosDasPortas(detalhe.value?.portas, t));
const ehAnuncio = computed(() => detalhe.value?.kind === 'ad');
const textoDoErro = computed(() =>
  motivo.value === 'not_inbox_member'
    ? t(`${KEY}.PAGINA.NAO_VE_CAIXA`)
    : t(`${KEY}.PAGINA.${ERRO[erro.value]}`)
);

const aberta = ref(
  GAVETAS.some(g => g.chave === route.query.gaveta) ? route.query.gaveta : null
);
const grupo = ref(
  GRUPOS.includes(route.query.grupo) ? route.query.grupo : 'esperando'
);
const abrir = (chave, noGrupo) => {
  if (noGrupo) grupo.value = noGrupo;
  aberta.value = chave;
};
const fechar = () => {
  aberta.value = null;
};

// Onde estão todos os comentários (para responder) e onde o cuidado se edita: o post no Seus posts ou o anúncio.
// #2520: o post por dentro pede seus_posts_comentarios; sem ela, não há onde responder no post, e o link some.
const comPostPorDentro = useFlags(FEATURE_FLAGS.SEUS_POSTS_COMENTARIOS);
const rotaDoAlvo = computed(() => {
  if (ehAnuncio.value)
    return {
      name: 'campaigns_meta_ads_index',
      query: { aba: 'resultado', anuncio: detalhe.value.target_id },
    };
  if (!comPostPorDentro.value) return null;
  return {
    name: 'seus_posts_post',
    params: { postId: detalhe.value.target_id },
    query: { perfil: detalhe.value.perfil },
  };
});
const rotaDoCuidado = computed(() => {
  if (!detalhe.value?.can_manage) return null;
  return ehAnuncio.value
    ? {
        name: 'campaigns_meta_ads_cuidar',
        params: { adId: detalhe.value.target_id },
      }
    : {
        name: 'seus_posts_cuidar',
        params: { postId: detalhe.value.target_id },
        query: { perfil: detalhe.value.perfil },
      };
});

const mudar = async status => {
  if (!(await mudarEstado(status))) useAlert(t(`${KEY}.PAGINA.ERRO_MUDAR`));
};
</script>

<template>
  <div class="w-full h-full overflow-y-auto bg-n-background">
    <div
      data-post-pagina
      class="relative flex flex-col w-full max-w-[55rem] gap-6 px-4 py-6 mx-auto md:px-6"
    >
      <router-link
        :to="{ name: 'autonomia_agents_index' }"
        class="inline-flex items-center gap-2 text-sm font-semibold min-h-11 w-fit text-n-blue-11"
      >
        <span
          class="i-lucide-arrow-left size-4 rtl:rotate-180"
          aria-hidden="true"
        />
        {{ t('AGENTS.JORNADA.PAGINA.VOLTAR_LISTA') }}
      </router-link>

      <div
        v-if="!detalhe"
        data-post-estado
        class="flex flex-col items-start gap-3 p-6 rounded-3xl bg-n-solid-1 ring-1 ring-inset ring-n-weak"
        :role="erro ? 'alert' : 'status'"
      >
        <p class="m-0 text-base text-n-slate-12">
          {{ erro ? textoDoErro : t(`${KEY}.PAGINA.LENDO`) }}
        </p>
        <AgenteBotao
          v-if="erro === 'rede'"
          variante="fantasma"
          :desabilitado="carregando"
          @click="carregar"
        >
          {{ t(`${KEY}.PAGINA.TENTAR`) }}
        </AgenteBotao>
      </div>

      <template v-else>
        <header
          class="flex flex-col gap-5 px-6 py-6 text-white rounded-3xl bg-[#0D2344] dark:bg-[#12305E] sm:flex-row sm:items-center"
        >
          <span class="relative shrink-0 w-fit">
            <img
              v-if="detalhe.capa"
              :src="detalhe.capa"
              alt=""
              class="object-cover size-20 rounded-2xl"
            />
            <span
              v-else
              class="block size-20 rounded-2xl bg-white/10"
              aria-hidden="true"
            />
            <span class="absolute flex -bottom-1 -end-1">
              <span
                v-for="rede in redes"
                :key="rede"
                role="img"
                :aria-label="t(`${KEY}.REDE.${rede.toUpperCase()}`)"
                class="grid bg-white rounded-full size-7 place-items-center"
              >
                <span class="size-5" :class="ICONE_DA_REDE[rede]" />
              </span>
            </span>
          </span>
          <span class="flex flex-col min-w-0 gap-2">
            <span
              class="text-xs font-semibold tracking-wide uppercase text-white/70"
            >
              {{ t(`${KEY}.TIPO.${detalhe.kind.toUpperCase()}`) }}
            </span>
            <h1 class="m-0 text-2xl font-bold text-white">
              {{ legenda.titulo || t(`${KEY}.CARTAO.SEM_LEGENDA`) }}
            </h1>
            <span
              v-if="legenda.resto"
              class="text-sm line-clamp-2 text-white/80"
            >
              {{ legenda.resto }}
            </span>
            <router-link
              v-if="rotaDoAlvo"
              data-ver-post
              :to="rotaDoAlvo"
              class="inline-flex items-center gap-1 text-sm font-semibold text-white underline min-h-11 w-fit"
            >
              {{ t(`${KEY}.PAGINA.${ehAnuncio ? 'VER_ANUNCIO' : 'VER_POST'}`) }}
              <span class="i-lucide-arrow-up-right size-4" aria-hidden="true" />
            </router-link>
          </span>
        </header>

        <section
          data-controles
          class="flex flex-col gap-4 p-5 rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak sm:flex-row sm:items-center"
        >
          <span class="flex flex-col gap-1 grow">
            <span
              data-estado
              class="inline-flex items-center gap-1.5 px-2.5 py-0.5 text-xs font-medium rounded-full w-fit text-n-slate-12"
              :class="estado === 'cuidando' ? 'bg-n-teal-3' : 'bg-n-amber-3'"
            >
              <span
                aria-hidden="true"
                class="rounded-full size-2"
                :class="estado === 'cuidando' ? 'bg-n-teal-9' : 'bg-n-amber-9'"
              />
              {{ t(`${KEY}.ESTADO.${estado.toUpperCase()}`) }}
            </span>
            <span class="text-sm leading-6 text-n-slate-12">
              {{
                estado === 'cuidando'
                  ? t(`${KEY}.PAGINA.TEXTO_CUIDANDO`, {
                      alvo: t(
                        `${KEY}.PAGINA.ALVO.${detalhe.kind.toUpperCase()}`
                      ),
                    })
                  : t(`${KEY}.PAGINA.TEXTO_PAUSADO`)
              }}
            </span>
          </span>
          <span v-if="detalhe.can_manage" class="flex flex-wrap gap-2">
            <AgenteBotao
              data-mudar-estado
              variante="fantasma"
              :desabilitado="mudando"
              @click="mudar(estado === 'cuidando' ? 'paused' : 'on')"
            >
              {{
                t(
                  `${KEY}.PAGINA.${estado === 'cuidando' ? 'PAUSAR' : 'RETOMAR'}`
                )
              }}
            </AgenteBotao>
            <router-link
              data-editar
              :to="rotaDoCuidado"
              class="inline-flex items-center justify-center px-4 text-sm font-semibold no-underline rounded-xl min-h-11 bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-1"
            >
              {{ t(`${KEY}.PAGINA.EDITAR`) }}
            </router-link>
          </span>
        </section>

        <p
          v-if="agentes.length || !motivos.length"
          data-usa
          class="flex flex-wrap items-center gap-2 p-4 m-0 text-sm rounded-2xl bg-n-blue-2 ring-1 ring-inset ring-n-blue-6 text-n-slate-12"
        >
          <span
            class="i-lucide-book-open size-5 shrink-0 text-n-blue-11"
            aria-hidden="true"
          />
          <template v-if="agentes.length">
            {{
              agentes.length > 1
                ? t(`${KEY}.CARTAO.USA_DOIS`, {
                    um: agentes[0].name,
                    outro: agentes[1].name,
                  })
                : t(`${KEY}.CARTAO.USA`, { nome: agentes[0].name })
            }}
            <router-link
              v-for="agente in agentes"
              :key="agente.id"
              :to="{
                name: 'autonomia_agent_panel',
                params: { agentId: agente.id },
              }"
              class="inline-flex items-center font-semibold underline min-h-11 text-n-blue-11"
            >
              {{ t(`${KEY}.PAGINA.VER_PORTA`, { nome: agente.name }) }}
            </router-link>
          </template>
          <template v-else-if="!motivos.length">
            {{ t(`${KEY}.CARTAO.SEM_PORTA`) }}
          </template>
        </p>
        <div
          v-if="motivos.length"
          data-motivos-das-portas
          class="flex flex-col gap-1 p-4 rounded-2xl bg-n-amber-2 ring-1 ring-inset ring-n-amber-6 text-sm leading-6 text-n-slate-12"
        >
          <p v-for="frase in motivos" :key="frase" class="m-0">
            {{ frase }}
          </p>
          <p class="m-0 text-n-slate-11">
            {{ t(`${KEY}.MOTIVO_DA_PORTA.FRASES_FIXAS`) }}
          </p>
        </div>

        <button
          type="button"
          data-esperando
          class="flex items-center w-full gap-3 p-5 m-0 text-base font-semibold border-0 text-start rounded-2xl ring-1 ring-inset focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-blue-11"
          :class="
            esperando
              ? 'bg-n-amber-2 ring-n-amber-6 text-n-slate-12 hover:bg-n-amber-3'
              : 'bg-n-solid-1 ring-n-weak text-n-slate-11 hover:bg-n-alpha-1'
          "
          @click="abrir('comentarios', 'esperando')"
        >
          <span
            class="i-lucide-hand size-5 shrink-0 text-n-amber-11"
            aria-hidden="true"
          />
          <template v-if="esperando === null">
            {{ t(`${KEY}.CARTAO.SEM_LEITURA`) }}
          </template>
          <template v-else>
            {{ t(`${KEY}.CARTAO.ESPERANDO`, { n: esperando }, esperando) }}
          </template>
          <span
            class="i-lucide-chevron-right ms-auto size-5 shrink-0 text-n-slate-10 rtl:rotate-180"
            aria-hidden="true"
          />
        </button>

        <ul class="grid grid-cols-1 gap-4 p-0 m-0 list-none sm:grid-cols-3">
          <li v-for="gaveta in GAVETAS" :key="gaveta.chave">
            <button
              v-if="gaveta.chave !== 'testar' || detalhe.can_manage"
              type="button"
              :data-abrir-gaveta="gaveta.chave"
              class="flex flex-col w-full h-full gap-2 p-5 transition border-0 shadow-sm text-start rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak dark:ring-n-slate-6 hover:ring-n-slate-7 hover:shadow-md focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-blue-11"
              @click="abrir(gaveta.chave)"
            >
              <span
                class="grid rounded-xl size-11 place-items-center bg-n-alpha-2"
                aria-hidden="true"
              >
                <span class="size-5 text-n-slate-12" :class="gaveta.icone" />
              </span>
              <span class="text-base font-semibold text-n-slate-12">
                {{ t(`${KEY}.${gaveta.titulo}.TITULO`) }}
              </span>
              <span class="text-sm text-n-slate-11">
                {{ t(`${KEY}.${gaveta.titulo}.TEXTO`) }}
              </span>
            </button>
          </li>
        </ul>
      </template>
    </div>

    <template v-if="detalhe">
      <GavetaSabeDoPost
        v-if="aberta === 'sabe'"
        :detalhe="detalhe"
        :rota-do-cuidado="rotaDoCuidado"
        @fechar="fechar"
      />
      <GavetaTestarDoPost
        v-if="aberta === 'testar' && detalhe.can_manage"
        :detalhe="detalhe"
        :testar="testar"
        @fechar="fechar"
      />
      <GavetaComentariosDoPost
        v-if="aberta === 'comentarios'"
        v-model:grupo="grupo"
        :detalhe="detalhe"
        :rota-do-alvo="rotaDoAlvo"
        @fechar="fechar"
      />
    </template>
  </div>
</template>
