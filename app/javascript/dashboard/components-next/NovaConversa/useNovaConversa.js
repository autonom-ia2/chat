import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { nomeDoContatoNaTela } from 'dashboard/components-next/conversa-canal/mais/telefoneDoPais';
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
  umAnexoPorMensagem,
  usaCaixaDoWhatsapp,
  usaModelo,
} from './novaConversa';
import { reabreAoEscrever } from './continuarConversa';
import { partesDoWhatsapp } from './envioNoWhatsapp';
import { useModeloDoEmailNaGaveta } from './useModeloDoEmailNaGaveta';
import { useCaixaDeEmailNova } from 'dashboard/components-next/conversa-canal/email/caixaDeEmailNova';
import { assuntoDaResposta } from 'dashboard/components-next/conversa-canal/email/dadosDoEmail';
import {
  camposDoEnvio,
  useFicarComAConversa,
} from 'dashboard/components-next/conversa-canal/atribuir/useFicarComAConversa';

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

// `donoDoRascunho` (#2211): de quem é o que está escrito. Por padrão, o id do contato. A
// conversa vazia com um telefone novo cria o contato só ao enviar: o dono é o número, e o
// texto não se perde quando o contato ganha id no meio do envio.
export function useNovaConversa({
  contato,
  canal,
  continuar = null,
  donoDoRascunho = null,
}) {
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
  // #2067: na conversa que já existe, o mesmo ícone "ficar com a conversa ao enviar" da
  // caixa de resposta (a mesma escolha guardada, pela mesma conversa). Conversa nova: não.
  const ficar = useFicarComAConversa({
    conversa: computed(() =>
      destino.value && continuar?.meta?.value
        ? { id: destino.value.displayId, meta: continuar.meta.value }
        : null
    ),
  });
  // A decisão do envio em curso: uma para todas as partes (texto, modelo, anexos).
  let decisaoDoEnvio = null;
  // O servidor respondeu que não deu para ficar com a conversa (trava ocupada, outro dono).
  let naoDeuFicar = false;
  // #2067: partes já mandadas neste envio (só a 1ª pede para ficar).
  let partesDoEnvio = 0;
  const tipo = computed(
    () => (destino.value && continuar.tipo.value) || tipoDeMensagem(canal.value)
  );
  const comModelo = computed(() =>
    usaModelo({ tipo: tipo.value, modo: form.modo })
  );
  // #1988 — a caixa do WhatsApp (texto livre no oficial e no comum), com a barra.
  const caixaDoWhatsapp = computed(
    () =>
      !comModelo.value &&
      usaCaixaDoWhatsapp({ canal: canal.value, tipo: tipo.value })
  );
  const comAssinatura = computed(
    () =>
      (tipo.value === TIPOS.EMAIL || caixaDoWhatsapp.value) &&
      Boolean(fetchSignatureFlagFromUISettings(canal.value?.channelType))
  );
  // #1988: no WhatsApp a assinatura não entra no campo; vai no fim do texto que sai,
  // como na caixa de resposta. Sem texto (só a gravação), vai sem assinatura.
  const textoQueSai = computed(() => {
    const texto = form.mensagem;
    if (!caixaDoWhatsapp.value || !comAssinatura.value) return texto;
    if (!assinatura.value || !texto.trim()) return texto;
    return appendSignature(texto, assinatura.value, formatoDe(canal.value));
  });
  const falta = computed(() => {
    if (continuar?.esperando.value) return 'CONVERSA';
    return oQueFalta({
      contato: contato.value,
      canal: canal.value,
      ...form,
      // #1988: no WhatsApp a gravação ou o anexo já bastam; em outro canal, não.
      anexos: caixaDoWhatsapp.value ? form.anexos : [],
      tipo: tipo.value,
      comAssunto: !destino.value,
    });
  });
  const previa = computed(() =>
    comModelo.value ? form.textoDoModelo : textoQueSai.value
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

  // #1988: a conversa em que as primeiras partes de um envio do WhatsApp já entraram,
  // quando uma parte do meio falhou. O Enviar de novo manda só o resto, nela.
  const retomada = ref(null);

  const limpar = () => {
    modeloDoEmail.cancelar();
    retomada.value = null;
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
    // No WhatsApp a assinatura vai só no envio (textoQueSai).
    if (
      novo &&
      tipo.value === TIPOS.EMAIL &&
      comAssinatura.value &&
      assinatura.value
    ) {
      texto = appendSignature(texto, assinatura.value, formatoDe(novo));
    }
    retomada.value = null;
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
      retomada.value = null;
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
    () => (donoDoRascunho ? donoDoRascunho.value : (contato.value?.id ?? null)),
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
  const responderEm = async (id, dados) => {
    const data = await store.dispatch(
      'sendMessageWithData',
      createPendingMessage({
        conversationId: id,
        private: false,
        ...dados,
        ...camposDoEnvio(decisaoDoEnvio, { parte: partesDoEnvio }),
        // #2216: a conversa visível da caixa com "Reabrir a mesma conversa" reabre.
        reabrirAoEscrever: reabreAoEscrever(destino.value),
      })
    );
    partesDoEnvio += 1;
    if (data?.ficar_com_a_conversa_nao_deu) naoDeuFicar = true;
    return data;
  };
  const responderNaConversa = dados => async () => {
    const id = destino.value.displayId;
    await responderEm(id, dados);
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
      nome: nomeDoContatoNaTela(contato.value),
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
    // #2067: uma decisão por envio, só na conversa que já existe (a nova segue a regra da
    // caixa). As partes leem esta mesma (responderEm).
    decisaoDoEnvio = destino.value ? ficar.decidir() : null;
    naoDeuFicar = false;
    partesDoEnvio = 0;
    const retrato = retratoDoEnvio(texto);
    try {
      const onde = await mandar();
      const { contatoId, ...confirmacao } = retrato;
      // #1809: entrou numa conversa que continua; o próximo e-mail cita o que acabou
      // de sair, então a gaveta pergunta de novo ao servidor.
      if (destino.value) continuar?.carregar();
      enviada.value = { ...onde, ...confirmacao };
      if (naoDeuFicar) useAlert(t('CONVERSA_CANAL.FICAR.NAO_DEU'));
      if (String(contato.value?.id ?? null) === String(contatoId)) limpar();
    } catch (error) {
      erro.value = textoDoErro(error) || t('NOVA_CONVERSA.ERRO.PADRAO');
      ficar.restaurar(decisaoDoEnvio);
    } finally {
      enviando.value = false;
      decisaoDoEnvio = null;
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

  // #1988 — WhatsApp: cada parte é uma mensagem (partesDoWhatsapp). A primeira cria a
  // conversa ou entra na que continua; as outras entram, na ordem, na mesma conversa.
  // A gravação sai como mensagem de voz (`is_voice_message`), como na caixa de resposta.
  const diretos = () => Boolean(config.value.directUploadsEnabled);
  const dadosDaParte = ({ texto, anexos, voz }) => ({
    message: texto,
    ...(anexos.length
      ? { files: prepareAttachmentPayload(anexos, diretos()) }
      : {}),
    ...(voz ? { isVoiceMessage: true } : {}),
  });
  const criarComParte = async ({ texto, anexos, voz }) => {
    const params = prepareNewMessagePayload({
      targetInbox: canal.value,
      selectedContact: contato.value,
      message: texto,
      currentUser: usuario.value,
      attachedFiles: anexos,
      directUploadsEnabled: diretos(),
    });
    return criarConversa(
      voz
        ? { ...params, message: { ...params.message, is_voice_message: true } }
        : params,
      false
    )();
  };
  const enviarNoWhatsapp = () => {
    const partes = partesDoWhatsapp({
      texto: textoQueSai.value,
      anexos: form.anexos,
      umPorMensagem: umAnexoPorMensagem(canal.value),
    });
    const contatoId = String(contato.value?.id ?? '');
    const mesmoContato = () => String(contato.value?.id ?? '') === contatoId;
    // Com várias partes, o que já saiu sai do rascunho (e a conversa fica guardada): se
    // uma parte do meio falhar, nada é mandado duas vezes ao cliente.
    const jaSaiu = (parte, onde) => {
      if (partes.length < 2 || !mesmoContato()) return;
      retomada.value = onde;
      if (parte.texto) form.mensagem = '';
      form.anexos = form.anexos.filter(anexo => !parte.anexos.includes(anexo));
    };
    const mandarParte = async (onde, parte) => {
      if (onde) {
        await responderEm(onde.id, dadosDaParte(parte));
        return onde;
      }
      return destino.value
        ? responderNaConversa(dadosDaParte(parte))()
        : criarComParte(parte);
    };
    // Uma por vez, para chegarem na ordem em que foram anexadas.
    const mandar = async () => {
      const onde = await partes.reduce(async (anterior, parte) => {
        const agora = await mandarParte(await anterior, parte);
        jaSaiu(parte, agora);
        return agora;
      }, Promise.resolve(retomada.value));
      retomada.value = null;
      return onde;
    };
    return despachar(mandar, textoQueSai.value);
  };

  const enviarEscrita = () => {
    if (caixaDoWhatsapp.value) return enviarNoWhatsapp();
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
    caixaDoWhatsapp,
    falta,
    previa,
    enviando,
    erro,
    enviada,
    limpar,
    enviar,
    enviarPronta,
    ficar,
  };
}
