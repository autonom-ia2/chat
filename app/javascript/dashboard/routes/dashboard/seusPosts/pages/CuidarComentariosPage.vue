<script setup>
import { computed, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import SeusPostsAPI from 'dashboard/api/seusPosts';
import Button from 'dashboard/components-next/button/Button.vue';
import { frontendURL } from 'dashboard/helper/URLHelper';
import CuidarComentarios from '../../campaigns/metaAds/comentariosIa/CuidarComentarios.vue';

// Seus posts (#2212, B1): "Cuidar dos comentários" de um post. A tela é a do #2212 (CuidarComentarios), a mesma do
// anúncio (B2); esta página só a coloca no endereço do post, lê o post (foto, legenda, caixa e `can_manage`, o mesmo
// do F2) e volta para ele. O cuidado em si vem de GET seus_posts/posts/:post_id/cuidado.
const route = useRoute();
const router = useRouter();

const perfilId = computed(() => route.query.perfil);
const postId = computed(() => route.params.postId);
const target = computed(() => ({
  kind: 'post',
  id: postId.value,
  perfil: perfilId.value,
}));

const KEY = 'META_ADS_COMMENTS_AI.SCREEN';
const dados = ref(null);
// 'acesso' (403) ou 'rede' (o resto). A tela de cuidar só abre com o post lido: sem ele não há `can_manage`, e quem
// pode mudar veria só leitura, sem explicação. Falhou, a tela diz e oferece tentar de novo.
const erro = ref(null);
// Trocar de post no meio de uma leitura: só a resposta da leitura mais nova vale.
let leitura = 0;
const lerPost = async () => {
  leitura += 1;
  const minha = leitura;
  dados.value = null;
  erro.value = null;
  try {
    const { data } = await SeusPostsAPI.getPost({
      perfil: perfilId.value,
      postId: postId.value,
    });
    if (minha === leitura) dados.value = data;
  } catch (error) {
    if (minha === leitura)
      erro.value = error?.response?.status === 403 ? 'acesso' : 'rede';
  }
};
watch(() => [perfilId.value, postId.value], lerPost, { immediate: true });

const cabecalho = computed(() =>
  dados.value?.post
    ? {
        image_url: dados.value.post.image_url,
        text: dados.value.post.text,
        network: dados.value.perfil?.network,
      }
    : null
);
const caixa = computed(() =>
  dados.value?.perfil?.inbox_id
    ? frontendURL(
        `accounts/${route.params.accountId}/inbox/${dados.value.perfil.inbox_id}`
      )
    : ''
);

const voltar = () =>
  router.push({
    name: 'seus_posts_post',
    params: { accountId: route.params.accountId, postId: postId.value },
    query: { perfil: perfilId.value, dias: route.query.dias },
  });
</script>

<template>
  <section
    data-seus-posts-cuidar-tela
    class="flex h-full w-full min-w-0 flex-col overflow-y-auto bg-n-slate-2"
  >
    <div
      class="mx-auto flex w-full max-w-3xl flex-col gap-5 p-4 pb-24 sm:p-5 lg:p-8"
    >
      <template v-if="!dados">
        <button
          type="button"
          data-seus-posts-cuidar-voltar
          class="inline-flex min-h-11 items-center gap-2 self-start rounded-xl border-0 bg-n-solid-1 px-4 text-sm font-medium text-n-slate-12 ring-1 ring-inset ring-n-weak transition hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          @click="voltar"
        >
          <span class="i-lucide-arrow-left size-4" aria-hidden="true" />
          {{ $t(`${KEY}.BACK_POST`) }}
        </button>
        <div
          v-if="erro"
          data-seus-posts-cuidar-erro
          role="alert"
          class="flex flex-col items-start gap-3 rounded-2xl bg-n-solid-1 p-6 ring-1 ring-inset ring-n-weak"
        >
          <p class="m-0 text-base font-semibold text-n-slate-12">
            {{
              erro === 'acesso' ? $t(`${KEY}.NO_ACCESS`) : $t(`${KEY}.ERROR`)
            }}
          </p>
          <Button
            v-if="erro !== 'acesso'"
            data-seus-posts-cuidar-de-novo
            icon="i-lucide-refresh-cw"
            :label="$t(`${KEY}.RETRY`)"
            class="!min-h-11 !rounded-xl"
            @click="lerPost"
          />
        </div>
        <p
          v-else
          data-seus-posts-cuidar-lendo
          role="status"
          aria-busy="true"
          class="m-0 text-sm text-n-slate-11"
        >
          {{ $t(`${KEY}.READING`) }}
        </p>
      </template>
      <CuidarComentarios
        v-else
        :target="target"
        :post="cabecalho"
        origin="post"
        :can-manage="Boolean(dados.can_manage)"
        :inbox-path="caixa"
        @back="voltar"
      />
    </div>
  </section>
</template>
