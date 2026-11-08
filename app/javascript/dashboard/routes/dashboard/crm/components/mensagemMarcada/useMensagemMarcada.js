import { computed, ref, watch } from 'vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import {
  chaveDoDia,
  instanteNaConta,
  somarDias,
} from '../calendario/tempoNaConta';

// #1590 — a Mensagem marcada em quatro passos: para quem, quando, o que dizer
// e confirmar. "Quando" vem antes do texto porque é a hora do envio que decide
// se o WhatsApp aceita texto livre (24 horas desde a última mensagem do
// cliente) ou só mensagem pronta aprovada. Dia e hora no fuso da conta.
export const PASSOS = ['para-quem', 'quando', 'mensagem', 'confirmar'];

const ehWhatsappConectado = caixa =>
  (caixa?.channel_type === 'Channel::Whatsapp' ||
    (caixa?.channel_type === 'Channel::TwilioSms' &&
      caixa?.medium === 'whatsapp')) &&
  caixa?.reauthorization_required !== true;

// A gaveta cobre a caixa oficial do WhatsApp (lista de mensagens prontas da
// própria caixa). Twilio e a caixa API de campanha continuam pelo retorno do
// card, que sabe digitar o nome do modelo ou listar os modelos da caixa API.
const ehOficial = caixa => caixa?.channel_type === 'Channel::Whatsapp';

export const caixaDoCard = (card, caixas) =>
  caixas.find(caixa => caixa.id === Number(card?.inbox_id || card?.inbox?.id));

// O card abre a gaveta nova só quando a conversa dele está na caixa oficial.
export const usaGavetaNova = (card, caixas) =>
  Boolean(card?.conversation_id) && ehOficial(caixaDoCard(card, caixas));

const primeiroNome = nome => String(nome || '').split(' ')[0];

// O 422 da criação traz um código estável; o resto vira uma frase só.
const ERRO_DO_CODIGO = {
  due_at_in_the_past: 'PASSADO',
  template_fallback_required: 'PRONTA',
  card_archived: 'ARQUIVADO',
};

export const useMensagemMarcada = ({ store, fuso, caixasDaTela }) => {
  const passo = ref('para-quem');
  const alvo = ref(null);
  const quando = ref({ dia: '', hora: '' });
  const janela = ref(null);
  const carregandoJanela = ref(false);
  const erroNaJanela = ref(false);
  const mensagem = ref({ texto: '', modelo: null });
  // Fora do objeto da mensagem: o preenchedor avisa a cada tecla, e trocar o
  // objeto a cada aviso redesenharia a lista inteira.
  const camposProntos = ref(false);
  const textoDoModelo = ref('');
  const anotacao = ref('');
  const salvando = ref(false);
  const erro = ref('');
  const feita = ref(null);

  // As caixas que a tela já tem (card, calendário); sem elas, as do store.
  const caixas = computed(() =>
    caixasDaTela?.value?.length
      ? caixasDaTela.value
      : store.getters['inboxes/getInboxes'] || []
  );

  // Um negócio da busca vira "alvo": quem recebe, por qual caixa e onde.
  // Sem conversa numa caixa de WhatsApp conectada não há para onde enviar.
  const paraAlvo = card => {
    const caixa = caixaDoCard(card, caixas.value);
    const conectada =
      Boolean(card.conversation_id) && ehWhatsappConectado(caixa);
    return {
      cardId: card.id,
      nome: card.contact?.name || card.title,
      primeiroNome: primeiroNome(card.contact?.name || card.title),
      negocio: card.contact?.name ? card.title : '',
      telefone: card.contact?.phone_number || '',
      conversaId: card.conversation_id || null,
      caixaId: caixa?.id || null,
      caixaNome: caixa?.name || '',
      dono: card.owner?.name || '',
      conectada,
      oficial: conectada && ehOficial(caixa),
    };
  };

  const hoje = () => chaveDoDia(new Date(), fuso.value);
  const dueAt = computed(() =>
    quando.value.dia && quando.value.hora
      ? instanteNaConta(quando.value.dia, quando.value.hora, fuso.value)
      : ''
  );
  const noPassado = computed(
    () => Boolean(dueAt.value) && new Date(dueAt.value) <= new Date()
  );

  // Fora das 24 h na hora marcada: só mensagem pronta, a não ser que o
  // WhatsApp do celular (Híbrido) leve o texto livre.
  const soPronta = computed(
    () =>
      janela.value?.requires_template === true &&
      janela.value?.whatsapp_api_available !== true
  );
  const peloCelular = computed(
    () =>
      janela.value?.requires_template === true &&
      janela.value?.whatsapp_api_available === true
  );
  const modelos = computed(() =>
    alvo.value?.caixaId
      ? store.getters['inboxes/getConversationWhatsAppTemplates'](
          alvo.value.caixaId
        ) || []
      : []
  );

  let pedido = 0;
  const carregarJanela = async () => {
    pedido += 1;
    const meu = pedido;
    janela.value = null;
    erroNaJanela.value = false;
    if (!alvo.value?.conversaId || !dueAt.value) return;
    carregandoJanela.value = true;
    try {
      const { data } = await CrmKanbanAPI.getFollowUpMessagingWindow(
        alvo.value.conversaId,
        dueAt.value
      );
      if (meu === pedido) janela.value = data;
    } catch {
      if (meu === pedido) erroNaJanela.value = true;
    } finally {
      if (meu === pedido) carregandoJanela.value = false;
    }
  };
  watch(dueAt, carregarJanela);

  // O que sai para o cliente, ao vivo na prévia.
  const textoQueSai = computed(() =>
    soPronta.value ? textoDoModelo.value : mensagem.value.texto.trim()
  );

  const faltaNaMensagem = () => {
    if (carregandoJanela.value) return 'CONFERINDO';
    if (erroNaJanela.value) return 'JANELA';
    if (soPronta.value) {
      if (!mensagem.value.modelo) return 'PRONTA';
      return camposProntos.value ? '' : 'CAMPOS';
    }
    return mensagem.value.texto.trim() ? '' : 'TEXTO';
  };
  const faltaNoPasso = computed(() => {
    if (passo.value === 'para-quem') return alvo.value ? '' : 'PARA_QUEM';
    if (passo.value === 'quando') {
      if (!quando.value.dia || !quando.value.hora) return 'QUANDO';
      return noPassado.value ? 'PASSADO' : '';
    }
    if (passo.value === 'mensagem') return faltaNaMensagem();
    return '';
  });

  const avancar = () => {
    if (faltaNoPasso.value) return;
    const indice = PASSOS.indexOf(passo.value);
    passo.value = PASSOS[Math.min(indice + 1, PASSOS.length - 1)];
  };
  const voltarPara = nome => {
    passo.value = nome;
  };

  const escolherAlvo = card => {
    alvo.value = paraAlvo(card);
    mensagem.value = { texto: '', modelo: null };
    camposProntos.value = false;
    // Outra pessoa, outra conversa: a janela da hora marcada é conferida de novo.
    carregarJanela();
    if (alvo.value.oficial) passo.value = 'quando';
  };

  const reiniciar = ({ dia } = {}) => {
    pedido += 1;
    passo.value = 'para-quem';
    alvo.value = null;
    quando.value = { dia: dia || '', hora: '' };
    janela.value = null;
    carregandoJanela.value = false;
    erroNaJanela.value = false;
    mensagem.value = { texto: '', modelo: null };
    camposProntos.value = false;
    textoDoModelo.value = '';
    anotacao.value = '';
    erro.value = '';
    feita.value = null;
  };

  // Mensagem pronta: o texto já preenchido vai como message_body (é o que
  // aparece na conversa e na atividade do card) e os campos vão como
  // template_processed_params, no formato { body: { "1": "…" } } que o envio
  // do WhatsApp entende (Whatsapp::TemplateProcessorService).
  const metadata = montada => {
    if (!soPronta.value || !montada) return { message_body: textoQueSai.value };
    const {
      name,
      language,
      namespace,
      processed_params: campos,
    } = montada.templateParams;
    return {
      message_body: montada.pendingMessageContent || montada.message,
      template_name: name,
      template_language: language,
      ...(namespace ? { template_namespace: namespace } : {}),
      template_processed_params: campos,
    };
  };

  const criar = async ({ titulo, montada }) => {
    // Clique duplo em "Marcar mensagem": só uma ida ao servidor (#1590).
    if (salvando.value) return false;
    salvando.value = true;
    erro.value = '';
    try {
      await store.dispatch('crmKanban/createFollowUp', {
        card_id: alvo.value.cardId,
        conversation_id: alvo.value.conversaId,
        title: titulo,
        description: anotacao.value.trim(),
        follow_up_type: 'task',
        automation_mode: 'auto_send_message',
        due_at: dueAt.value,
        timezone: fuso.value,
        metadata: metadata(montada),
      });
      feita.value = {
        nome: alvo.value.nome,
        dia: quando.value.dia,
        hora: quando.value.hora,
      };
      return true;
    } catch (resposta) {
      erro.value = ERRO_DO_CODIGO[resposta?.response?.data?.code] || 'GERAL';
      return false;
    } finally {
      salvando.value = false;
    }
  };

  return {
    passo,
    alvo,
    paraAlvo,
    quando,
    janela,
    carregandoJanela,
    erroNaJanela,
    mensagem,
    textoDoModelo,
    camposProntos,
    anotacao,
    salvando,
    erro,
    feita,
    dueAt,
    noPassado,
    soPronta,
    peloCelular,
    modelos,
    textoQueSai,
    faltaNoPasso,
    hoje,
    amanha: () => somarDias(hoje(), 1),
    avancar,
    voltarPara,
    escolherAlvo,
    reiniciar,
    criar,
    carregarJanela,
  };
};
