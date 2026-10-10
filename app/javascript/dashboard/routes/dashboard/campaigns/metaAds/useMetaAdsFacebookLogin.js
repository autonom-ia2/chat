import { ref } from 'vue';
import { setupFacebookSdk } from 'dashboard/routes/dashboard/settings/inbox/channels/whatsapp/utils';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';

// "Entrar com o Facebook" nos Anúncios da Meta (#1069): abre o Login do Facebook para Empresas com a
// configuração dos anúncios, recebe o código e manda ao servidor, que troca, testa e grava a conexão.
//
// O SDK é carregado antes (preload) para o clique abrir o popup ainda dentro do gesto da pessoa; carregar
// só no clique deixa o navegador bloquear o popup (o mesmo cuidado de useFacebookPageConnect).
export function useMetaAdsFacebookLogin() {
  const isConnecting = ref(false);
  let sdkReady = null;

  const preload = config => {
    if (!sdkReady) {
      sdkReady = setupFacebookSdk(config.app_id, config.api_version).catch(
        error => {
          sdkReady = null;
          throw error;
        }
      );
    }
    return sdkReady;
  };

  // FB.login nunca rejeita: devolve o código, ou null quando a pessoa fecha o popup ou não autoriza.
  const askCode = configurationId =>
    new Promise(resolve => {
      window.FB.login(
        response => resolve(response?.authResponse?.code || null),
        {
          config_id: configurationId,
          response_type: 'code',
          override_default_response_type: true,
        }
      );
    });

  // Conexão gravada (o mesmo corpo do GET), ou null quando a pessoa desistiu. Erro da API sobe para a tela.
  const connect = async config => {
    if (isConnecting.value) return null;
    isConnecting.value = true;
    try {
      await preload(config);
      const code = await askCode(config.configuration_id);
      if (!code) return null;

      const { data } = await CrmMetaAdsConnectionAPI.facebookLogin(code);
      return data;
    } finally {
      isConnecting.value = false;
    }
  };

  return { isConnecting, preload, connect };
}
