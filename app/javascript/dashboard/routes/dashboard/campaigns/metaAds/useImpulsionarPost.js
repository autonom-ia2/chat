import { computed, ref } from 'vue';
import { lerPostsParaImpulsionar } from './criacaoNaMeta';

// Anúncios da Meta (#2198 PR 2, #2339), impulsionar post: os posts da Página escolhida (e do Instagram dela), lidos
// quando a pessoa chega no passo do post, e o post escolhido no formato da conferência e da prévia.
//
// - A aba do Instagram abre primeiro quando há post de lá que pode ser impulsionado: é ele que leva o WhatsApp.
// - O primeiro post que pode ser impulsionado já vem marcado.
// - Falha ao ler (rede ou `posts_error` do servidor): a tela diz que não conseguiu ler e oferece tentar de novo.
// - Nenhum post nos dois lados: `semPosts`, e a tela oferece o anúncio novo.
export const useImpulsionarPost = ({ draft, numbers }) => {
  const lidos = ref(null);
  const lidosDaPagina = ref(null);
  const lendo = ref(false);
  const falhou = ref(false);
  // Cada leitura leva um número; só vale a resposta da mais recente.
  let ultimaLeitura = 0;

  const posts = computed(() => lidos.value?.posts || []);
  const postsDoInstagram = computed(() => lidos.value?.instagram_posts || []);
  const semPosts = computed(
    () =>
      Boolean(lidos.value) &&
      !falhou.value &&
      !posts.value.length &&
      !postsDoInstagram.value.length
  );

  const marcarPrimeiro = () => {
    const doInstagram = postsDoInstagram.value.find(post => post.eligible);
    const daPagina = posts.value.find(post => post.eligible);
    draft.value = {
      ...draft.value,
      post_source: doInstagram ? 'instagram' : 'facebook',
      post_id: (doInstagram || daPagina)?.id || null,
    };
  };

  // Resposta de uma leitura anterior (outra Página, ou a mesma lida de novo) que chegou atrasada é descartada.
  const lerPosts = async () => {
    const pageId = draft.value.page_id;
    if (!pageId) return;
    ultimaLeitura += 1;
    const leitura = ultimaLeitura;
    const atual = () => leitura === ultimaLeitura;
    lidos.value = null;
    lidosDaPagina.value = null;
    lendo.value = true;
    falhou.value = false;
    try {
      const data = await lerPostsParaImpulsionar(pageId);
      if (!atual()) return;
      lidos.value = data;
      lidosDaPagina.value = pageId;
      falhou.value = Boolean(data.posts_error);
      if (!falhou.value) marcarPrimeiro();
    } catch {
      if (atual()) falhou.value = true;
    } finally {
      if (atual()) lendo.value = false;
    }
  };

  // Lê na primeira vez e quando a Página mudou.
  const lerSePreciso = () => {
    if (lidosDaPagina.value === draft.value.page_id && !falhou.value) return;
    lerPosts();
  };

  // O post escolhido: { text, media, eligible }. A mídia vai como foto para a prévia.
  const postEscolhido = computed(() => {
    const { post_source: source, post_id: id } = draft.value;
    if (!id) return null;
    const lista = source === 'instagram' ? postsDoInstagram.value : posts.value;
    const post = lista.find(item => item.id === id);
    if (!post) return null;
    return {
      text: source === 'instagram' ? post.caption : post.message,
      media: post.image_url ? { kind: 'image', url: post.image_url } : null,
      eligible: post.eligible,
    };
  });

  // O botão do post: WhatsApp no post do Instagram quando a conta tem número; nenhum no da Página, que leva ao post.
  const botaoDoPost = computed(() =>
    draft.value.post_source === 'instagram' && numbers.value.length
      ? 'WHATSAPP'
      : null
  );

  return {
    posts,
    postsDoInstagram,
    lendo,
    falhou,
    semPosts,
    lerPosts,
    lerSePreciso,
    postEscolhido,
    botaoDoPost,
  };
};
