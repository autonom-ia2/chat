import { computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { usePermissionGranted } from 'dashboard/composables/useCanManage';
import { useFacebookPageConnect } from 'dashboard/composables/useFacebookPageConnect';
import FBChannel from 'dashboard/api/channel/fbChannel';
import instagramClient from 'dashboard/api/channel/instagramClient';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

// Seus posts (#2302): o "Libere o acesso" da lista e do post. Caixa sem a permissão de números (ou, na F2 #2305, de
// comentários) reautoriza a mesma caixa (integration_manage, a régua do servidor para trocar a credencial). Página →
// Entrar com Facebook com os escopos dela, e a tela relê; Instagram → login do Instagram, que volta para Seus posts. A
// volta do login do Instagram também exige inbox_manage (OauthBinding). O servidor decide os escopos do Instagram pelo
// `purpose`: com os comentários ligados, números e comentários juntos, para a autorização nova não perder os números.
//
// perfil: computed com { rede, inboxId }; precisa: computed, true quando falta a permissão; reler: lê de novo.
export const useLiberarAcesso = ({ perfil, precisa, reler }) => {
  const { t } = useI18n();
  const { isCloudFeatureEnabled } = useAccount();
  const podeCriarCaixa = usePermissionGranted('inbox_manage');
  const podeReautorizar = usePermissionGranted('integration_manage');
  const comComentarios = computed(() =>
    isCloudFeatureEnabled(FEATURE_FLAGS.SEUS_POSTS_COMENTARIOS)
  );

  const podeLiberar = computed(() => {
    if (!perfil.value?.inboxId || !podeReautorizar.value) return false;
    return perfil.value.rede === 'facebook' || podeCriarCaixa.value;
  });

  const { preloadSdk, login } = useFacebookPageConnect();
  watch(
    () => precisa.value && perfil.value?.rede === 'facebook',
    sim => {
      if (sim) preloadSdk().catch(() => {});
    },
    { immediate: true }
  );

  const escoposDaPagina = () =>
    comComentarios.value
      ? ['read_insights', 'pages_read_user_content', 'pages_manage_engagement']
      : ['read_insights'];

  const liberar = async () => {
    const { rede, inboxId } = perfil.value;
    try {
      if (rede === 'facebook') {
        const token = await login(escoposDaPagina());
        if (!token) return;
        await FBChannel.reauthorizeFacebookPage({
          omniauthToken: token,
          inboxId,
        });
        await reler();
        return;
      }
      const { data } = await instagramClient.generateAuthorization({
        inbox_id: inboxId,
        return_to: 'meta_ads',
        purpose: comComentarios.value ? 'seus_posts_comentarios' : 'seus_posts',
      });
      window.location.href = data.url;
    } catch {
      useAlert(t('SEUS_POSTS.NO_PERMISSION.ERROR'));
    }
  };

  return { podeLiberar, liberar };
};
