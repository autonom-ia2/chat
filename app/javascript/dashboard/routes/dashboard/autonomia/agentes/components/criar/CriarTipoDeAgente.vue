<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import SeusPostsAPI from 'dashboard/api/seusPosts';
import AgentesDoPostAPI from 'dashboard/api/agentesDoPost';
import AgenteGaveta from '../AgenteGaveta.vue';
import {
  ICONE_DA_REDE,
  tituloDaLegenda,
} from '../../composables/useAgentesDoPost';

// #2469 (PR 3a do #2436): com o cuidado dos comentários ligado na conta, "Criar agente" em Agentes pergunta o tipo
// antes. "Atender conversas" segue a criação de hoje; "Cuidar dos comentários de um post ou anúncio" pergunta qual post
// (os do perfil, dos últimos 30 dias, lidos pelo Seus posts) e leva ao passo 1 do cuidado, com o "Voltar" para Agentes.
// #2479: o chip "Posts | Anúncios" troca a lista pelos anúncios (os da lista de Anúncios dos últimos 30 dias, só do
// banco: abrir não lê a Meta). Cada lista aparece só para quem tem as guardas dela (`comPosts`, `comAnuncios`); com uma só,
// sem chip. A entrada pelo próprio post e pelo anúncio continua.
// #2519 (3A): o anúncio com comentário esperando o dono diz quantos (`waiting`) e vem primeiro, mesmo fora dos 30 dias.
const props = defineProps({
  comPosts: { type: Boolean, default: true },
  comAnuncios: { type: Boolean, default: false },
});
const emit = defineEmits(['fechar', 'atender', 'post', 'anuncio']);

const { t } = useI18n();
const KEY = 'AGENTS.AGENTE_DO_POST.CRIAR';
const DIAS = 30;
const ESCOLHA =
  'flex w-full min-h-11 items-start gap-4 rounded-2xl border-0 bg-n-solid-1 p-5 text-start ring-1 ring-inset ring-n-weak transition hover:bg-n-alpha-1 hover:ring-n-blue-8 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand';
const CHIP =
  'inline-flex items-center gap-2 px-4 text-sm font-medium border-0 rounded-full min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11';
const chipClass = ativo =>
  ativo
    ? 'bg-n-slate-12 text-n-solid-1'
    : 'bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-1';

// 'tipo' (as duas escolhas) ou 'post' (qual post ou anúncio).
const etapa = ref('tipo');
// 'posts' | 'anuncios': a lista do "Qual post?".
const fonte = ref(props.comPosts ? 'posts' : 'anuncios');
// 'lendo' | 'pronto' | 'erro' | 'acesso'
const leitura = ref('lendo');
const perfis = ref([]);
const perfil = ref(null);
// 'lendo' | 'pronto' | 'erro' | 'acesso' | 'conexao' (sem a conta de anúncios conectada)
const leituraDosAnuncios = ref('lendo');
const anuncios = ref(null);

const lerAnuncios = async () => {
  leituraDosAnuncios.value = 'lendo';
  try {
    const { data } = await AgentesDoPostAPI.anuncios();
    anuncios.value = data.anuncios || [];
    leituraDosAnuncios.value = 'pronto';
  } catch (error) {
    const { status, data } = error?.response || {};
    if (status === 403) leituraDosAnuncios.value = 'acesso';
    else if (data?.error === 'not_connected')
      leituraDosAnuncios.value = 'conexao';
    else leituraDosAnuncios.value = 'erro';
  }
};

const LEITURA_DOS_ANUNCIOS = {
  lendo: 'LENDO',
  erro: 'ERRO',
  acesso: 'SEM_ACESSO',
  conexao: 'SEM_CONEXAO',
};
const ESTADO_DO_ANUNCIO = { on: 'CUIDANDO', paused: 'PAUSADO' };

const posts = computed(() =>
  (perfil.value?.posts || []).map(post => ({
    ...post,
    titulo: tituloDaLegenda(post.text).titulo || post.id,
  }))
);

const lerPerfil = async id => {
  leitura.value = 'lendo';
  try {
    const { data } = await SeusPostsAPI.get({ perfil: id, days: DIAS });
    perfis.value = data.perfis || [];
    perfil.value = data.perfil;
    leitura.value = 'pronto';
  } catch (error) {
    leitura.value = error?.response?.status === 403 ? 'acesso' : 'erro';
  }
};

const lerFonte = () => {
  if (fonte.value === 'posts' && !perfil.value) lerPerfil();
  if (fonte.value === 'anuncios' && !anuncios.value) lerAnuncios();
};

const escolherPost = () => {
  etapa.value = 'post';
  lerFonte();
};

const trocarFonte = nova => {
  fonte.value = nova;
  lerFonte();
};

const titulo = computed(() => {
  if (etapa.value === 'tipo') return t(`${KEY}.TITULO`);
  return fonte.value === 'posts'
    ? t(`${KEY}.QUAL_POST`)
    : t(`${KEY}.ANUNCIOS.QUAL_ANUNCIO`);
});
</script>

<template>
  <AgenteGaveta :titulo="titulo" @fechar="emit('fechar')">
    <ul
      v-if="etapa === 'tipo'"
      data-criar-tipos
      class="flex flex-col gap-3 p-0 m-0 list-none"
    >
      <li>
        <button
          type="button"
          data-criar-tipo="atender"
          :class="ESCOLHA"
          @click="emit('atender')"
        >
          <span
            class="grid rounded-xl place-items-center size-12 shrink-0 bg-n-blue-3 text-n-blue-11"
          >
            <span class="i-lucide-messages-square size-6" aria-hidden="true" />
          </span>
          <span class="flex flex-col gap-1">
            <span class="text-base font-semibold text-n-slate-12">
              {{ t(`${KEY}.ATENDER.TITULO`) }}
            </span>
            <span class="text-sm leading-6 text-n-slate-11">
              {{ t(`${KEY}.ATENDER.TEXTO`) }}
            </span>
          </span>
        </button>
      </li>
      <li>
        <button
          type="button"
          data-criar-tipo="post"
          :class="ESCOLHA"
          @click="escolherPost"
        >
          <span
            class="grid rounded-xl place-items-center size-12 shrink-0 bg-n-violet-3 text-n-violet-11"
          >
            <span
              class="i-lucide-message-circle-heart size-6"
              aria-hidden="true"
            />
          </span>
          <span class="flex flex-col gap-1">
            <span class="text-base font-semibold text-n-slate-12">
              {{ t(`${KEY}.POST.TITULO`) }}
            </span>
            <span class="text-sm leading-6 text-n-slate-11">
              {{ t(`${KEY}.POST.TEXTO`) }}
            </span>
          </span>
        </button>
      </li>
    </ul>

    <template v-else>
      <button
        type="button"
        data-criar-voltar
        class="inline-flex items-center gap-1 px-0 text-sm font-semibold bg-transparent border-0 min-h-11 w-fit text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
        @click="etapa = 'tipo'"
      >
        <span
          class="i-lucide-arrow-left size-4 rtl:rotate-180"
          aria-hidden="true"
        />
        {{ t(`${KEY}.VOLTAR`) }}
      </button>
      <div
        v-if="comPosts && comAnuncios"
        data-criar-fontes
        role="group"
        :aria-label="t(`${KEY}.ANUNCIOS.FONTE`)"
        class="flex flex-wrap gap-2"
      >
        <button
          v-for="item in ['posts', 'anuncios']"
          :key="item"
          type="button"
          :data-criar-fonte="item"
          :aria-pressed="fonte === item"
          :class="[CHIP, chipClass(fonte === item)]"
          @click="trocarFonte(item)"
        >
          {{ t(`${KEY}.ANUNCIOS.CHIP.${item.toUpperCase()}`) }}
        </button>
      </div>
      <template v-if="fonte === 'posts'">
        <div
          v-if="perfis.length > 1"
          data-criar-perfis
          role="group"
          :aria-label="t(`${KEY}.PERFIL`)"
          class="flex flex-wrap gap-2"
        >
          <button
            v-for="item in perfis"
            :key="item.id"
            type="button"
            :data-criar-perfil="item.id"
            :aria-pressed="perfil?.id === item.id"
            :class="[CHIP, chipClass(perfil?.id === item.id)]"
            @click="lerPerfil(item.id)"
          >
            <span class="size-4" :class="ICONE_DA_REDE[item.network]" />
            {{
              item.name ||
              t(`AGENTS.AGENTE_DO_POST.REDE.${item.network.toUpperCase()}`)
            }}
          </button>
        </div>
        <p
          v-if="leitura !== 'pronto'"
          data-criar-leitura
          class="m-0 text-sm leading-6 text-n-slate-11"
          :role="leitura === 'lendo' ? 'status' : 'alert'"
        >
          {{
            t(
              `${KEY}.${{ lendo: 'LENDO', erro: 'ERRO', acesso: 'SEM_ACESSO' }[leitura]}`
            )
          }}
        </p>
        <p
          v-else-if="!posts.length"
          data-criar-sem-posts
          class="m-0 text-sm leading-6 text-n-slate-11"
        >
          {{ t(`${KEY}.SEM_POSTS`) }}
        </p>
        <ul
          v-else
          data-criar-posts
          class="flex flex-col gap-3 p-0 m-0 list-none"
        >
          <li v-for="post in posts" :key="post.id">
            <button
              type="button"
              :data-criar-post="post.id"
              :class="ESCOLHA"
              class="!items-center !p-3"
              @click="emit('post', { id: post.id, perfil: perfil.id })"
            >
              <span class="relative shrink-0">
                <img
                  v-if="post.image_url"
                  :src="post.image_url"
                  alt=""
                  class="object-cover rounded-xl size-16"
                />
                <span v-else class="block rounded-xl size-16 bg-n-alpha-2" />
                <span
                  class="absolute grid rounded-full -bottom-1 -end-1 place-items-center size-6 bg-n-solid-1 ring-1 ring-n-weak"
                >
                  <span
                    :class="ICONE_DA_REDE[perfil.network]"
                    class="size-4"
                    role="img"
                    :aria-label="
                      t(
                        `AGENTS.AGENTE_DO_POST.REDE.${perfil.network.toUpperCase()}`
                      )
                    "
                  />
                </span>
              </span>
              <span class="flex flex-col min-w-0 gap-1">
                <span class="text-base font-semibold text-n-slate-12">
                  {{ post.titulo }}
                </span>
                <span
                  v-if="post.comments !== null && post.comments !== undefined"
                  class="text-sm text-n-slate-11"
                >
                  {{
                    t(`${KEY}.COMENTARIOS`, { n: post.comments }, post.comments)
                  }}
                </span>
              </span>
              <span
                class="i-lucide-chevron-right size-5 ms-auto shrink-0 text-n-slate-11 rtl:rotate-180"
                aria-hidden="true"
              />
            </button>
          </li>
        </ul>
      </template>
      <template v-else>
        <p
          v-if="leituraDosAnuncios !== 'pronto'"
          data-criar-leitura-anuncios
          class="m-0 text-sm leading-6 text-n-slate-11"
          :role="leituraDosAnuncios === 'lendo' ? 'status' : 'alert'"
        >
          {{ t(`${KEY}.ANUNCIOS.${LEITURA_DOS_ANUNCIOS[leituraDosAnuncios]}`) }}
        </p>
        <p
          v-else-if="!anuncios.length"
          data-criar-sem-anuncios
          class="m-0 text-sm leading-6 text-n-slate-11"
        >
          {{ t(`${KEY}.ANUNCIOS.SEM_ANUNCIOS`) }}
        </p>
        <ul
          v-else
          data-criar-anuncios
          class="flex flex-col gap-3 p-0 m-0 list-none"
        >
          <li v-for="anuncio in anuncios" :key="anuncio.id">
            <button
              type="button"
              :data-criar-anuncio="anuncio.id"
              :class="ESCOLHA"
              class="!items-center !p-3"
              @click="emit('anuncio', { id: anuncio.id })"
            >
              <img
                v-if="anuncio.image_url"
                :src="anuncio.image_url"
                alt=""
                class="object-cover rounded-xl size-16 shrink-0"
              />
              <span
                v-else
                class="grid rounded-xl place-items-center size-16 shrink-0 bg-n-alpha-2 text-n-slate-11"
              >
                <span class="i-lucide-megaphone size-6" aria-hidden="true" />
              </span>
              <span class="flex flex-col min-w-0 gap-1">
                <span
                  class="text-base font-semibold break-words text-n-slate-12"
                >
                  {{
                    anuncio.name ||
                    t(`${KEY}.ANUNCIOS.SEM_NOME`, { id: anuncio.id })
                  }}
                </span>
                <span
                  v-if="ESTADO_DO_ANUNCIO[anuncio.care]"
                  :data-criar-anuncio-estado="anuncio.care"
                  class="text-sm text-n-slate-11"
                >
                  {{ t(`${KEY}.ANUNCIOS.${ESTADO_DO_ANUNCIO[anuncio.care]}`) }}
                </span>
                <span
                  v-if="anuncio.waiting > 0"
                  data-criar-anuncio-esperando
                  class="inline-flex items-center gap-1.5 text-sm font-medium text-n-amber-11"
                >
                  <span
                    class="i-lucide-message-circle-warning size-4 shrink-0"
                    aria-hidden="true"
                  />
                  {{
                    t(
                      `${KEY}.ANUNCIOS.ESPERANDO`,
                      { n: anuncio.waiting },
                      anuncio.waiting
                    )
                  }}
                </span>
              </span>
              <span
                class="i-lucide-chevron-right size-5 ms-auto shrink-0 text-n-slate-11 rtl:rotate-180"
                aria-hidden="true"
              />
            </button>
          </li>
        </ul>
      </template>
    </template>
  </AgenteGaveta>
</template>
