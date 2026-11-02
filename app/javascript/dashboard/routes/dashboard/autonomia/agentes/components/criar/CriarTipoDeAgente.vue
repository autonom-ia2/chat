<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import SeusPostsAPI from 'dashboard/api/seusPosts';
import AgenteGaveta from '../AgenteGaveta.vue';
import {
  ICONE_DA_REDE,
  tituloDaLegenda,
} from '../../composables/useAgentesDoPost';

// #2469 (PR 3a do #2436): com o cuidado dos comentários ligado na conta, "Criar agente" em Agentes pergunta o tipo
// antes. "Atender conversas" segue a criação de hoje; "Cuidar dos comentários de um post ou anúncio" pergunta qual post
// (os do perfil, dos últimos 30 dias, lidos pelo Seus posts) e leva ao passo 1 do cuidado, com o "Voltar" para Agentes.
// O anúncio se escolhe em Anúncios, onde cada um já tem "Cuidar dos comentários". A entrada pelo próprio post continua.
const emit = defineEmits(['fechar', 'atender', 'post', 'anuncio']);

const { t } = useI18n();
const KEY = 'AGENTS.AGENTE_DO_POST.CRIAR';
const DIAS = 30;
const ESCOLHA =
  'flex w-full min-h-11 items-start gap-4 rounded-2xl border-0 bg-n-solid-1 p-5 text-start ring-1 ring-inset ring-n-weak transition hover:bg-n-alpha-1 hover:ring-n-blue-8 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand';

// 'tipo' (as duas escolhas) ou 'post' (qual post).
const etapa = ref('tipo');
// 'lendo' | 'pronto' | 'erro' | 'acesso'
const leitura = ref('lendo');
const perfis = ref([]);
const perfil = ref(null);

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

const escolherPost = () => {
  etapa.value = 'post';
  if (!perfil.value) lerPerfil();
};
</script>

<template>
  <AgenteGaveta
    :titulo="etapa === 'tipo' ? t(`${KEY}.TITULO`) : t(`${KEY}.QUAL_POST`)"
    @fechar="emit('fechar')"
  >
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
          class="inline-flex items-center gap-2 px-4 text-sm font-medium border-0 rounded-full min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
          :class="
            perfil?.id === item.id
              ? 'bg-n-slate-12 text-n-solid-1'
              : 'bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-1'
          "
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
      <ul v-else data-criar-posts class="flex flex-col gap-3 p-0 m-0 list-none">
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
      <button
        type="button"
        data-criar-anuncio
        class="inline-flex items-center gap-1 px-0 text-sm font-semibold bg-transparent border-0 min-h-11 w-fit text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
        @click="emit('anuncio')"
      >
        {{ t(`${KEY}.ANUNCIO`) }}
        <span
          class="i-lucide-arrow-right size-4 rtl:rotate-180"
          aria-hidden="true"
        />
      </button>
    </template>
  </AgenteGaveta>
</template>
