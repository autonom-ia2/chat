import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { ExceptionWithMessage } from 'shared/helpers/CustomErrors';
import {
  appendSignature,
  removeSignature,
  getEffectiveChannelType,
  stripUnsupportedMarkdown,
} from 'dashboard/helper/editorHelper';
import {
  prepareNewMessagePayload,
  prepareWhatsAppMessagePayload,
} from 'dashboard/components-next/NewConversation/helpers/composeConversationHelper';
import {
  MODOS,
  TIPOS,
  chaveDoCanal,
  oQueFalta,
  tipoDeMensagem,
  usaModelo,
} from './novaConversa';

// #1459 — a mensagem e o envio. O envio é a mesma chamada da tela antiga
// (`contactConversations/create`), com os mesmos formatos de payload.
const formVazio = () => ({
  modo: MODOS.ESCREVER,
  mensagem: '',
  assunto: '',
  cc: '',
  bcc: '',
  anexos: [],
  modelo: null,
  camposProntos: false,
  textoDoModelo: '',
});

const formatoDe = canal =>
  getEffectiveChannelType(canal?.channelType || '', canal?.medium || '');

export function useNovaConversa({ contato, canal }) {
  const store = useStore();
  const { t } = useI18n();
  const { fetchSignatureFlagFromUISettings } = useUISettings();
  const usuario = useMapGetter('getCurrentUser');
  const config = useMapGetter('globalConfig/get');
  const assinatura = useMapGetter('getMessageSignature');

  const form = reactive(formVazio());
  const enviando = ref(false);
  const erro = ref('');
  const enviada = ref(null);

  const tipo = computed(() => tipoDeMensagem(canal.value));
  const comModelo = computed(() =>
    usaModelo({ tipo: tipo.value, modo: form.modo })
  );
  const comAssinatura = computed(
    () =>
      tipo.value === TIPOS.EMAIL &&
      Boolean(fetchSignatureFlagFromUISettings(canal.value?.channelType))
  );
  const falta = computed(() =>
    oQueFalta({ contato: contato.value, canal: canal.value, ...form })
  );
  const previa = computed(() =>
    comModelo.value ? form.textoDoModelo : form.mensagem
  );

  const limpar = () => Object.assign(form, formVazio());

  // Trocar de canal muda o que a mensagem pode ter: a assinatura só vale no
  // e-mail, a formatação que o canal novo não aceita sai, e a mensagem
  // pronta e os anexos eram do canal anterior.
  const aoTrocarDeCanal = (novo, antigo) => {
    let texto = form.mensagem;
    if (antigo && assinatura.value) {
      texto = removeSignature(texto, assinatura.value, formatoDe(antigo));
    }
    if (novo && texto) {
      texto = stripUnsupportedMarkdown(texto, formatoDe(novo), false);
    }
    if (novo && comAssinatura.value && assinatura.value) {
      texto = appendSignature(texto, assinatura.value, formatoDe(novo));
    }
    Object.assign(form, {
      ...formVazio(),
      mensagem: texto,
      assunto: form.assunto,
      cc: form.cc,
      bcc: form.bcc,
    });
  };

  watch(canal, (novo, antigo) => {
    if (novo?.id !== antigo?.id) aoTrocarDeCanal(novo, antigo);
  });

  // `texto` é o que a pessoa vê na confirmação: a mensagem como foi enviada.
  const despachar = async (params, isFromWhatsApp, texto) => {
    enviando.value = true;
    erro.value = '';
    try {
      const conversa = await store.dispatch('contactConversations/create', {
        params,
        isFromWhatsApp,
      });
      enviada.value = {
        id: conversa.id,
        contaId: conversa.account_id,
        nome: contato.value?.name || '',
        texto,
        chaveDoCanal: chaveDoCanal(canal.value),
        caixa: canal.value?.name || '',
      };
      limpar();
    } catch (error) {
      const doServidor =
        error instanceof ExceptionWithMessage ? error.data : '';
      erro.value =
        typeof doServidor === 'string' && doServidor
          ? doServidor
          : t('NOVA_CONVERSA.ERRO.PADRAO');
    } finally {
      enviando.value = false;
    }
  };

  // `pronta` é o que o preenchedor de modelo entrega: { message, templateParams }.
  const enviarPronta = pronta =>
    despachar(
      prepareWhatsAppMessagePayload({
        targetInbox: canal.value,
        selectedContact: contato.value,
        message: pronta.message,
        templateParams: pronta.templateParams,
        currentUser: usuario.value,
      }),
      true,
      form.textoDoModelo || pronta.pendingMessageContent || pronta.message
    );

  const enviarEscrita = () =>
    despachar(
      prepareNewMessagePayload({
        targetInbox: canal.value,
        selectedContact: contato.value,
        message: form.mensagem,
        subject: tipo.value === TIPOS.EMAIL ? form.assunto : '',
        ccEmails: tipo.value === TIPOS.EMAIL ? form.cc : '',
        bccEmails: tipo.value === TIPOS.EMAIL ? form.bcc : '',
        currentUser: usuario.value,
        attachedFiles: form.anexos,
        directUploadsEnabled: Boolean(config.value.directUploadsEnabled),
      }),
      false,
      form.mensagem
    );

  // `montarPronta` devolve o modelo preenchido (ou null se faltar campo).
  const enviar = montarPronta => {
    if (falta.value || enviando.value) return null;
    if (!comModelo.value) return enviarEscrita();
    const pronta = montarPronta();
    return pronta ? enviarPronta(pronta) : null;
  };

  return {
    form,
    tipo,
    comModelo,
    comAssinatura,
    assinatura,
    falta,
    previa,
    enviando,
    erro,
    enviada,
    limpar,
    enviar,
    enviarPronta,
  };
}
