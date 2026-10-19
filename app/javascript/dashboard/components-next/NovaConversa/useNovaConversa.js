import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { ExceptionWithMessage } from 'shared/helpers/CustomErrors';
import { createPendingMessage } from 'dashboard/helper/commons';
import {
  appendSignature,
  removeSignature,
  getEffectiveChannelType,
  stripUnsupportedMarkdown,
} from 'dashboard/helper/editorHelper';
import {
  prepareAttachmentPayload,
  prepareNewMessagePayload,
  prepareWhatsAppMessagePayload,
} from 'dashboard/components-next/NewConversation/helpers/composeConversationHelper';
import {
  MODOS,
  TIPOS,
  chaveDoCanal,
  linhaDoCanal,
  oQueFalta,
  tipoDeMensagem,
  usaModelo,
} from './novaConversa';
import { useModeloDoEmailNaGaveta } from './useModeloDoEmailNaGaveta';
import { useCaixaDeEmailNova } from 'dashboard/components-next/conversa-canal/email/caixaDeEmailNova';
import { assuntoDaResposta } from 'dashboard/components-next/conversa-canal/email/dadosDoEmail';

// #1459 — a mensagem e o envio. Conversa nova: a mesma chamada da tela antiga
// (`contactConversations/create`), com os mesmos formatos de payload.
// #1505 — continuando uma conversa (`continuar`, de useContinuarConversa), a
// mensagem entra nela pelo mesmo caminho da resposta normal da conversa
// (`sendMessageWithData` → MessageApi.create), nunca criando outra.
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
  // #1809: modelo de e-mail do "+" (useModeloDoEmailNaGaveta).
  modeloDoEmail: null,
  valoresDoModelo: {},
  // #1809: "Não enviar o histórico" ao continuar uma conversa de e-mail.
  historicoDesligado: false,
});

const formatoDe = canal =>
  getEffectiveChannelType(canal?.channelType || '', canal?.medium || '');

// O que o servidor disse sobre o erro, quando disse em texto.
const textoDoErro = error => {
  const doServidor =
    error instanceof ExceptionWithMessage
      ? error.data
      : error?.response?.data?.error;
  return typeof doServidor === 'string' ? doServidor : '';
};

export function useNovaConversa({ contato, canal, continuar = null }) {
  const store = useStore();
  const { t } = useI18n();
  const { fetchSignatureFlagFromUISettings } = useUISettings();
  const usuario = useMapGetter('getCurrentUser');
  const config = useMapGetter('globalConfig/get');
  const assinatura = useMapGetter('getMessageSignature');
  const contaAtual = useMapGetter('getCurrentAccountId');

  const form = reactive(formVazio());
  const enviando = ref(false);
  const erro = ref('');
  const enviada = ref(null);

  // A conversa em que a mensagem vai entrar (#1505), ou null para criar.
  const destino = computed(() => continuar?.conversa.value ?? null);
  const tipo = computed(
    () => (destino.value && continuar.tipo.value) || tipoDeMensagem(canal.value)
  );
  const comModelo = computed(() =>
    usaModelo({ tipo: tipo.value, modo: form.modo })
  );
  const comAssinatura = computed(
    () =>
      tipo.value === TIPOS.EMAIL &&
      Boolean(fetchSignatureFlagFromUISettings(canal.value?.channelType))
  );
  const falta = computed(() => {
    if (continuar?.esperando.value) return 'CONVERSA';
    return oQueFalta({
      contato: contato.value,
      canal: canal.value,
      ...form,
      tipo: tipo.value,
      comAssunto: !destino.value,
    });
  });
  const previa = computed(() =>
    comModelo.value ? form.textoDoModelo : form.mensagem
  );
  const modeloDoEmail = useModeloDoEmailNaGaveta({
    form,
    contato,
    canal,
    destino,
  });

  // #1809 — continuando uma conversa de e-mail (com a chave conversa_email_nova), o
  // último e-mail vai como histórico no fim, como na resposta: sempre, a não ser que
  // a pessoa tire. O assunto é o da conversa, com "Re: ".
  const ehCaixaDeEmailNova = useCaixaDeEmailNova();
  const historico = computed(() => {
    const emailNovo =
      tipo.value === TIPOS.EMAIL && ehCaixaDeEmailNova(canal.value?.id);
    return emailNovo && destino.value
      ? (continuar?.ultimoEmail.value ?? null)
      : null;
  });
  const comHistorico = computed(
    () => Boolean(historico.value) && !form.historicoDesligado
  );
  const assuntoDaConversa = computed(() =>
    destino.value ? assuntoDaResposta(continuar?.assunto.value) : ''
  );
  // O assunto que o e-mail leva: o da conversa ("Re: ...") ou o digitado na nova.
  const assuntoNaPrevia = computed(() =>
    destino.value ? assuntoDaConversa.value : form.assunto
  );
  const comCitacao = atributos =>
    comHistorico.value
      ? {
          ...atributos,
          email_citacao: { tipo: 'historico', message_id: historico.value.id },
        }
      : atributos;

  const limpar = () => {
    modeloDoEmail.cancelar();
    Object.assign(form, formVazio());
  };

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

  // #1809: "Não enviar o histórico" vale para esta conversa; mudar de destino volta ao
  // padrão (vai junto), como cada Responder na resposta.
  watch(
    () => destino.value?.displayId ?? null,
    () => {
      form.historicoDesligado = false;
    }
  );

  watch(canal, (novo, antigo) => {
    if (novo?.id !== antigo?.id) aoTrocarDeCanal(novo, antigo);
  });

  // Trocar de contato (ou ficar sem contato) zera tudo: o que foi escrito
  // para uma pessoa nunca segue para outra. O rascunho só sobrevive enquanto
  // o contato for o mesmo. Fica DEPOIS do watch do canal de propósito: na
  // troca de contato os dois disparam, e é este que dá a palavra final.
  watch(
    () => contato.value?.id ?? null,
    (novo, antigo) => {
      if (String(novo) === String(antigo)) return;
      limpar();
      erro.value = '';
    }
  );

  // Cria a conversa com a primeira mensagem; devolve onde ela entrou.
  const criarConversa = (params, isFromWhatsApp) => async () => {
    const conversa = await store.dispatch('contactConversations/create', {
      params,
      isFromWhatsApp,
    });
    return { id: conversa.id, contaId: conversa.account_id, numero: null };
  };

  // Responde dentro da conversa que já existe, como a caixa de resposta. Sem
  // `crm_card_id`: a gaveta não tem o seletor de assunto do CRM, então a
  // mensagem fica no assunto atual da conversa, como uma resposta em conversa
  // de um assunto só.
  const responderNaConversa = dados => async () => {
    const id = destino.value.displayId;
    await store.dispatch(
      'sendMessageWithData',
      createPendingMessage({ conversationId: id, private: false, ...dados })
    );
    return { id, contaId: contaAtual.value, numero: id };
  };

  // `texto` é o que a pessoa vê na confirmação: a mensagem como foi enviada.
  // Ponto único de envio: enquanto um envio está no ar, outro não sai (clique
  // duplo, Ctrl+Enter repetido, ou o seletor do Twilio confirmando de novo).
  // O retrato do envio é tirado ANTES de esperar o servidor: se a pessoa
  // trocar de contato ou de canal no meio, a confirmação fala do que foi
  // enviado, e o rascunho novo não é apagado.
  const retratoDoEnvio = texto => {
    const email = tipo.value === TIPOS.EMAIL;
    return {
      contatoId: contato.value?.id ?? null,
      nome: contato.value?.name || '',
      texto,
      assunto: email ? assuntoNaPrevia.value : '',
      email,
      chaveDoCanal: chaveDoCanal(canal.value),
      caixa: canal.value?.name || '',
      endereco: linhaDoCanal(canal.value),
      oculta: Boolean(continuar?.oculta.value),
    };
  };

  const despachar = async (mandar, texto) => {
    if (enviando.value) return;
    enviando.value = true;
    erro.value = '';
    const retrato = retratoDoEnvio(texto);
    try {
      const onde = await mandar();
      const { contatoId, ...confirmacao } = retrato;
      // #1809: entrou numa conversa que continua; o próximo e-mail cita o que acabou
      // de sair, então a gaveta pergunta de novo ao servidor.
      if (destino.value) continuar?.carregar();
      enviada.value = { ...onde, ...confirmacao };
      if (String(contato.value?.id ?? null) === String(contatoId)) limpar();
    } catch (error) {
      erro.value = textoDoErro(error) || t('NOVA_CONVERSA.ERRO.PADRAO');
    } finally {
      enviando.value = false;
    }
  };

  // `pronta` é o que o preenchedor de modelo entrega: { message, templateParams }.
  const criarComPronta = pronta =>
    criarConversa(
      prepareWhatsAppMessagePayload({
        targetInbox: canal.value,
        selectedContact: contato.value,
        message: pronta.message,
        templateParams: pronta.templateParams,
        currentUser: usuario.value,
      }),
      true
    );

  // Mesmo formato do envio de mensagem pronta da caixa de resposta.
  const responderComPronta = pronta =>
    responderNaConversa({
      message: pronta.message,
      templateParams: pronta.templateParams,
    });

  const enviarPronta = pronta =>
    despachar(
      destino.value ? responderComPronta(pronta) : criarComPronta(pronta),
      form.textoDoModelo || pronta.pendingMessageContent || pronta.message
    );

  // #1809: com modelo de e-mail, a mensagem leva o `email_modelo` (o servidor monta
  // e limpa o HTML no MessageBuilder, como na resposta).
  const comAtributos = (params, atributos) =>
    atributos
      ? {
          ...params,
          message: { ...params.message, content_attributes: atributos },
        }
      : params;

  const criarComEscrita = ({ mensagem, atributos }) =>
    criarConversa(
      comAtributos(
        prepareNewMessagePayload({
          targetInbox: canal.value,
          selectedContact: contato.value,
          message: mensagem,
          subject: tipo.value === TIPOS.EMAIL ? form.assunto : '',
          ccEmails: tipo.value === TIPOS.EMAIL ? form.cc : '',
          bccEmails: tipo.value === TIPOS.EMAIL ? form.bcc : '',
          currentUser: usuario.value,
          attachedFiles: form.anexos,
          directUploadsEnabled: Boolean(config.value.directUploadsEnabled),
        }),
        atributos
      ),
      false
    );

  // Mesmo formato da caixa de resposta: texto, anexos e cópias do e-mail. O
  // assunto é o da conversa, que já existe.
  const responderComEscrita = ({ mensagem, atributos }) => {
    const email = tipo.value === TIPOS.EMAIL;
    const anexos = form.anexos.length
      ? {
          files: prepareAttachmentPayload(
            form.anexos,
            Boolean(config.value.directUploadsEnabled)
          ),
        }
      : {};
    return responderNaConversa({
      message: mensagem,
      ccEmails: email ? form.cc : '',
      bccEmails: email ? form.bcc : '',
      ...anexos,
      ...(atributos ? { contentAttributes: atributos } : {}),
    });
  };

  const enviarEscrita = () => {
    const doTexto =
      tipo.value === TIPOS.EMAIL
        ? modeloDoEmail.noEnvio(form.mensagem)
        : { mensagem: form.mensagem, atributos: null };
    const envio = { ...doTexto, atributos: comCitacao(doTexto.atributos) };
    return despachar(
      destino.value ? responderComEscrita(envio) : criarComEscrita(envio),
      envio.mensagem
    );
  };

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
    destino,
    comModelo,
    modeloDoEmail,
    historico,
    comHistorico,
    assuntoNaPrevia,
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
