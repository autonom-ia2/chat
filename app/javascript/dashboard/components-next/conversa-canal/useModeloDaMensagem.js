// O modelo de WhatsApp que a mensagem usou (#1702), lido do modelo aprovado guardado na
// caixa (`message_templates`) pelo nome e idioma gravados na mensagem. Modelo apagado
// ou renomeado na Meta: nada aparece (o balão fica só com o texto, sem espaço vazio).
// Limite conhecido: mostra o modelo de hoje; guardar a foto dos botões no envio fica
// para depois (combinado com o Modelos WhatsApp).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';

const ICONE = {
  QUICK_REPLY: 'i-ph-arrow-bend-up-left-bold',
  URL: 'i-ph-arrow-square-out-bold',
  PHONE_NUMBER: 'i-ph-phone-bold',
  VOICE_CALL: 'i-ph-phone-call-bold',
  COPY_CODE: 'i-ph-copy-bold',
  OTP: 'i-ph-copy-bold',
  FLOW: 'i-ph-note-pencil-bold',
  CATALOG: 'i-ph-storefront-bold',
  MPM: 'i-ph-storefront-bold',
  SPM: 'i-ph-storefront-bold',
};
// Botões que o app escreve por conta própria (o modelo não traz o texto).
const TEXTO_DO_APP = {
  COPY_CODE: 'CONVERSA_CANAL.MODELO.COPIAR_CODIGO',
  CATALOG: 'CONVERSA_CANAL.MODELO.VER_CATALOGO',
  MPM: 'CONVERSA_CANAL.MODELO.VER_ITENS',
  SPM: 'CONVERSA_CANAL.MODELO.VER_ITEM',
};
const ICONE_DA_MIDIA = {
  IMAGE: 'i-ph-image',
  VIDEO: 'i-ph-video',
  DOCUMENT: 'i-ph-file-text',
  PRODUCT: 'i-ph-storefront',
};
const PADRAO = 'i-ph-arrow-bend-up-left-bold';

// `mensagem`: computed com { additionalAttributes, inboxId }.
export const useModeloDaMensagem = mensagem => {
  const { t } = useI18n();
  const caixaPorId = useMapGetter('inboxes/getInbox');

  const modelo = computed(() => {
    const params = mensagem.value?.additionalAttributes?.templateParams;
    if (!params?.name) return null;
    const modelos = caixaPorId.value(mensagem.value.inboxId)?.message_templates;
    const doNome = (modelos || []).filter(m => m.name === params.name);
    // Com idioma gravado, só o modelo daquele idioma: os botões de outro idioma
    // mostrariam ao atendente algo que o cliente não recebeu. Sem idioma (jornada
    // de campanha grava só o nome), só quando o nome tem um idioma só.
    if (!params.language) return doNome.length === 1 ? doNome[0] : null;
    return doNome.find(m => m.language === params.language) || null;
  });

  const componente = tipo =>
    (modelo.value?.components || []).find(c => c.type === tipo);

  const botao = b => ({
    tipo: b.type,
    texto: b.text || (TEXTO_DO_APP[b.type] ? t(TEXTO_DO_APP[b.type]) : ''),
    icone: ICONE[b.type] || PADRAO,
  });

  const botoes = computed(() =>
    (componente('BUTTONS')?.buttons || []).map(botao)
  );

  const cartoes = computed(() =>
    (componente('CAROUSEL')?.cards || []).map(cartao => {
      const partes = cartao.components || [];
      const topo = partes.find(c => c.type === 'HEADER');
      return {
        midia: ICONE_DA_MIDIA[topo?.format] || 'i-ph-image',
        texto: partes.find(c => c.type === 'BODY')?.text || '',
        botoes: (partes.find(c => c.type === 'BUTTONS')?.buttons || []).map(
          botao
        ),
      };
    })
  );

  const oferta = computed(() => componente('LIMITED_TIME_OFFER') || null);
  const produto = computed(() => componente('HEADER')?.format === 'PRODUCT');

  return { modelo, botoes, cartoes, oferta, produto };
};
