import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';

// Anúncios da Meta: gestão mínima do anúncio (#2161). A tela pede por aqui a situação do anúncio (no ar ou pausado),
// o post da Página por trás dele e a Página da conexão, e pede para pausar ou ativar. Tudo ao vivo na Meta, pelo
// servidor (Crm::MetaAds::AdManagement).

// Falha ao ler: a tela segue sem a situação e sem o post (o resto do anúncio vem do banco e continua).
export const lerGestao = async adId => {
  try {
    const { data } = await CrmMetaAdsConnectionAPI.adManagement(adId);
    return data.management;
  } catch {
    return null;
  }
};

// Recusa da Meta sobe para a tela, que avisa; `cannot_change` diz que falta entrar de novo com o Facebook.
export const mudarStatus = async (adId, status) => {
  const { data } = await CrmMetaAdsConnectionAPI.setAdStatus(adId, status);
  return data;
};

export const lerPagina = async () => {
  try {
    const { data } = await CrmMetaAdsConnectionAPI.pages();
    return data.pages?.length
      ? { name: data.pages.map(page => page.name).join(', ') }
      : null;
  } catch {
    return null;
  }
};
