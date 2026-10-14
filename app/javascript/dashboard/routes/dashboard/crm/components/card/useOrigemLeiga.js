import { useI18n } from 'vue-i18n';
import { useCrmOrigin } from '../../composables/useCrmOrigin';
import { useFormato } from './useFormato';

// #1423 — de onde o cliente veio, em palavras simples (OB-05). Os dados são os
// mesmos de useCrmOrigin; só as frases mudam: "um anúncio no Facebook ou no
// Instagram que abre o WhatsApp" em vez de "Meta clique para WhatsApp".
const FONTES = {
  meta_ctwa: 'ANUNCIO_WHATSAPP',
  meta_organic: 'PUBLICACAO',
  meta_paid: 'ANUNCIO_META',
  google_ads: 'ANUNCIO_GOOGLE',
  tiktok_ads: 'ANUNCIO_TIKTOK',
  tracked_link: 'LINK',
  campaign_whatsapp: 'DIVULGACAO_WHATSAPP',
  campaign_email: 'DIVULGACAO_EMAIL',
  campaign_live_chat: 'CHAT_DO_SITE',
  campaign_sms: 'DIVULGACAO_SMS',
};
const NIVEIS = { campaign: 'CAMPANHA', adset: 'GRUPO', ad: 'ANUNCIO' };

export const useOrigemLeiga = () => {
  const { t, locale } = useI18n();
  const origem = useCrmOrigin();
  const formato = useFormato({ t, locale });
  const O = 'CRM_CARD.ORIGEM.FONTE';
  const postagens = () => [
    t('CRM_KANBAN.ORIGIN.INSTAGRAM_POST'),
    t('CRM_KANBAN.ORIGIN.FACEBOOK_POST'),
  ];

  const fonte = item => t(`${O}.${FONTES[item?.source] || 'DESCONHECIDA'}`);
  // A mesma fonte como título de um passo: começa com maiúscula ("Um anúncio
  // no Google"), porque ali não está no meio de uma frase.
  const titulo = item => {
    const texto = fonte(item);
    return (
      texto.charAt(0).toLocaleUpperCase(locale.value.replace('_', '-')) +
      texto.slice(1)
    );
  };

  // O nome que acompanha a fonte: o título do anúncio ou do link, sem
  // repetir a campanha que já vem numa linha própria.
  const nome = item => {
    if (!item) return '';
    if (item.adFromHeadline) return item.headline;
    const rotulo = origem.originLabelOverHierarchy(item);
    const prefixo = `${origem.sourceLabel(item)}: `;
    if (rotulo.startsWith(prefixo)) return rotulo.slice(prefixo.length);
    if (rotulo === origem.sourceLabel(item) || postagens().includes(rotulo))
      return '';
    return rotulo;
  };

  const niveis = item =>
    origem.hierarchyItems(item).map(nivel => ({
      ...nivel,
      level: t(`CRM_CARD.ORIGEM.NIVEL.${NIVEIS[nivel.field]}`),
    }));

  const link = item => {
    const rotulo = origem.sourceUrlLabel(item);
    const [instagram, facebook] = postagens();
    if (rotulo === instagram)
      return t('CRM_CARD.ORIGEM.VER_PUBLICACAO_INSTAGRAM');
    if (rotulo === facebook)
      return t('CRM_CARD.ORIGEM.VER_PUBLICACAO_FACEBOOK');
    return rotulo;
  };

  // A data de cada passo como no resto do card: "1 de outubro · há 12 dias"
  // (com o ano quando não é o ano corrente). O título traz a data completa.
  const data = item => {
    const toque = origem.touchDate(item);
    if (!toque) return null;
    const dia = new Date(toque.iso);
    return {
      ...toque,
      label: `${formato.diaCurto(dia)} · ${formato.ha(dia)}`,
    };
  };

  return {
    fonte,
    titulo,
    nome,
    niveis,
    link,
    data,
    daCampanha: origem.originFromCampaigns,
  };
};
