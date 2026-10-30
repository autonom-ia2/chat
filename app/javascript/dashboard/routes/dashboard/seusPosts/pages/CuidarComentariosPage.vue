<script setup>
import { computed, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import SeusPostsAPI from 'dashboard/api/seusPosts';
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

const dados = ref(null);
// Sem o post (falhou a leitura), a tela de cuidar ainda mostra o estado, sem os botões de escrita.
const lerPost = async () => {
  dados.value = null;
  try {
    const { data } = await SeusPostsAPI.getPost({
      perfil: perfilId.value,
      postId: postId.value,
    });
    dados.value = data;
  } catch {
    dados.value = null;
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
      <CuidarComentarios
        :target="target"
        :post="cabecalho"
        origin="post"
        :can-manage="Boolean(dados?.can_manage)"
        :inbox-path="caixa"
        @back="voltar"
      />
    </div>
  </section>
</template>
