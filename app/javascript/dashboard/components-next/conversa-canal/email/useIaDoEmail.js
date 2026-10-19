// #1872 — o ✨ do editor de e-mail com a IA do cliente: o copiloto da Autonom.ia (a chave
// da conta, o consumo na Gestão IA), nunca o Captain. Traduz as ações do menu do ✨ para as
// tarefas do copiloto, roda em segundo plano (pollAiRequest) e devolve o texto sugerido
// para a tela mostrar no lugar do editor, com Descartar e Aceitar. Expõe o mesmo formato
// de estado que a caixa de resposta já usa para isso (CopilotEditorSection e
// CopilotReplyBottomPanel, que são só visual).
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import AutonomiaCopilotAPI from 'dashboard/api/autonomiaCopilot';
import {
  appendSignature,
  getEffectiveChannelType,
  removeSignature,
} from 'dashboard/helper/editorHelper';

// Os tons do menu → o código do tom no copiloto.
export const TONS = {
  professional: 'professional',
  casual: 'casual',
  straightforward: 'direct',
  confident: 'confident',
  friendly: 'friendly',
};

// O copiloto escreve em português do Brasil (as instruções dele são em português).
export const INSTRUCAO_DE_CORRECAO =
  'Corrija só a ortografia, a acentuação e a gramática. Não mude o tom, as palavras escolhidas nem o sentido.';

// Ações que mexem só no texto (valem sem conversa) e as que leem a conversa.
export const ACOES_DE_TEXTO = [
  'improve',
  ...Object.keys(TONS),
  'fix_spelling_grammar',
];
export const ACOES_DA_CONVERSA = ['reply_suggestion', 'summarize'];
const TAREFAS_SEM_CONVERSA = ['rewrite', 'refine'];

// Os mesmos tetos do servidor (MAX_QUERY_CHARS e TextCopilotController::MAX_INSTRUCTION_CHARS):
// melhor avisar antes de pedir.
export const LIMITE_DO_TEXTO = 6000;
export const LIMITE_DA_INSTRUCAO = 1000;
// A IA responde em segundos; passando disto, desiste e avisa (o poll padrão iria até 30 min).
export const ESPERA_MAXIMA_MS = 90 * 1000;
// O servidor separa a falha do provedor (ai_failed) de IA indisponível (sem chave ou desligada).
export const FALHA_DO_PROVEDOR = 'ai_failed';

// Ação do menu → pedido ao copiloto. null = ação que o e-mail não tem.
export const pedidoDaAcao = (acao, texto) => {
  if (acao === 'improve') return { task: 'rewrite', draft: texto };
  if (TONS[acao]) return { task: 'rewrite', draft: texto, tone: TONS[acao] };
  if (acao === 'fix_spelling_grammar') {
    return { task: 'refine', draft: texto, instruction: INSTRUCAO_DE_CORRECAO };
  }
  if (acao === 'summarize') return { task: 'summarize' };
  if (acao === 'reply_suggestion') return { task: 'draft' };
  return null;
};

// As {{variáveis}} de um texto, em ordem, para comparar o rascunho com a sugestão.
export const variaveisDoTexto = texto =>
  (texto || '')
    .split('{{')
    .slice(1)
    .map(pedaco => {
      const fim = pedaco.indexOf('}}');
      return fim > 0 ? `{{${pedaco.slice(0, fim).trim()}}}` : null;
    })
    .filter(Boolean)
    .sort();

// Disponibilidade da conta. Só o "sim" fica guardado, e por pouco tempo (a chave pode ser
// desconectada); um "não" é perguntado de novo na próxima tela (a pessoa pode ter conectado a
// chave). Guarda uma conta só: trocar de conta descarta o que havia.
export const VALIDADE_DO_SIM_MS = 5 * 60 * 1000;
let simGuardado = null;
export const esquecerDisponibilidade = () => {
  simGuardado = null;
};

const consultar = async contaId => {
  if (simGuardado?.contaId === contaId && Date.now() < simGuardado.ate) {
    return true;
  }
  simGuardado = null;
  try {
    const { data } = await AutonomiaCopilotAPI.status();
    if (data?.available === true) {
      simGuardado = { contaId, ate: Date.now() + VALIDADE_DO_SIM_MS };
    }
    return data?.available === true;
  } catch (erro) {
    // Sem resposta, o ✨ fica fora; status e mensagem ficam no console para quem investiga (o
    // erro inteiro do axios leva os cabeçalhos de login da requisição).
    // eslint-disable-next-line no-console
    console.error(
      'IA do e-mail: falha ao consultar a disponibilidade',
      erro?.response?.status,
      erro?.message
    );
    return false;
  }
};

// `ativo`: só pergunta quando a tela é mesmo de e-mail novo (nada de GET no WhatsApp).
export const useDisponibilidadeDaIa = (ativo = () => true) => {
  const globalConfig = useMapGetter('globalConfig/get');
  const contaId = useMapGetter('getCurrentAccountId');
  const disponivel = ref(false);
  watch(
    ativo,
    sim => {
      // Com o CRM ou o copiloto desligados na instalação, nem pergunta.
      const ligadoNaInstalacao =
        globalConfig.value?.crmKanbanEnabled === true &&
        globalConfig.value?.crmCopilotEnabled === true;
      if (!sim || !ligadoNaInstalacao || !contaId.value) return;
      consultar(contaId.value).then(resposta => {
        disponivel.value = resposta;
      });
    },
    { immediate: true }
  );
  return disponivel;
};

// A assinatura que está no texto do editor (ligada e escrita), no formato que useIaDoEmail pede.
export const assinaturaNoTexto = ({ ligada, texto, channelType, medium }) =>
  ligada && texto
    ? { texto, canal: getEffectiveChannelType(channelType, medium || '') }
    : null;

/**
 * @param {Object} opcoes
 * @param {() => boolean} opcoes.ativo  a tela é de e-mail novo (só então pergunta ao servidor).
 * @param {() => (number|null)} opcoes.conversaId  conversa da resposta; null na gaveta.
 * @param {() => string} opcoes.rascunho  o texto do editor (para quem chama sem texto).
 * @param {() => ({ texto: string, canal: string }|null)} opcoes.assinatura  a assinatura
 *   que está no texto: sai antes de ir para a IA e volta ao aceitar.
 */
export const useIaDoEmail = ({
  ativo = () => true,
  conversaId = () => null,
  rascunho = () => '',
  assinatura = () => null,
} = {}) => {
  const { t, locale } = useI18n();
  const disponivel = useDisponibilidadeDaIa(ativo);

  const showEditor = ref(false);
  const isGenerating = ref(false);
  const isContentReady = ref(false);
  const generatedContent = ref('');
  // O texto que a pessoa tinha antes do primeiro pedido (os ajustes partem da sugestão).
  const textoOriginal = ref(null);
  const isActive = computed(() => showEditor.value || isGenerating.value);
  const isButtonDisabled = computed(
    () => isGenerating.value || !isContentReady.value
  );
  const editorTransitionKey = computed(() =>
    isActive.value ? 'copilot' : 'rich'
  );
  const temConversa = computed(() => Boolean(conversaId()));

  // A sugestão perdeu, ganhou ou trocou {{variáveis}}? Avisa; não bloqueia o Aceitar.
  const avisoDasVariaveis = computed(() => {
    if (textoOriginal.value === null || !generatedContent.value) return null;
    const antes = variaveisDoTexto(textoOriginal.value).join(' ');
    const agora = variaveisDoTexto(generatedContent.value).join(' ');
    if (antes === agora) return null;
    const nenhuma = t('CONVERSA_CANAL.EMAIL.IA.NENHUMA_VARIAVEL');
    return t('CONVERSA_CANAL.EMAIL.IA.VARIAVEIS_MUDARAM', {
      antes: antes || nenhuma,
      agora: agora || nenhuma,
    });
  });

  // Cada pedido tem a sua vez e o seu AbortController: Descartar (ou um pedido novo) para o
  // poll e invalida a resposta que ainda chegaria. Só o acompanhamento para: o job no servidor
  // termina e o consumo é contado na Gestão IA (decisão do #1872: aceitável; o
  // InteractiveRequest não é cancelado).
  let vez = 0;
  let controle = null;

  const reset = () => {
    vez += 1;
    controle?.abort();
    controle = null;
    showEditor.value = false;
    isGenerating.value = false;
    isContentReady.value = false;
    generatedContent.value = '';
    textoOriginal.value = null;
  };

  const semAssinatura = texto => {
    const sig = assinatura();
    return sig?.texto
      ? removeSignature(texto, sig.texto, sig.canal).trimEnd()
      : texto;
  };

  const comAssinatura = texto => {
    const sig = assinatura();
    return sig?.texto ? appendSignature(texto, sig.texto, sig.canal) : texto;
  };

  const chamar = (pedido, polling) => {
    const conversa = conversaId();
    return conversa
      ? AutonomiaCopilotAPI.run(conversa, pedido, polling)
      : AutonomiaCopilotAPI.runText(pedido, polling);
  };

  const formatar = numero =>
    numero.toLocaleString(locale.value.replace('_', '-'));
  const textoLongo = () =>
    t('CONVERSA_CANAL.EMAIL.IA.TEXTO_LONGO', {
      limite: formatar(LIMITE_DO_TEXTO),
    });
  const instrucaoLonga = () =>
    t('CONVERSA_CANAL.EMAIL.IA.INSTRUCAO_LONGA', {
      limite: formatar(LIMITE_DA_INSTRUCAO),
    });

  // Cada recusa do servidor com o seu aviso; o genérico fica só para o que não se sabe.
  const avisarFalha = erro => {
    const codigo = erro?.response?.data?.error;
    if (erro?.code === 'ai_request_timeout') {
      useAlert(t('CONVERSA_CANAL.EMAIL.IA.DEMOROU'));
    } else if (
      codigo === 'too_many_requests' ||
      erro?.response?.status === 429
    ) {
      useAlert(t('CONVERSA_CANAL.EMAIL.IA.MUITOS_PEDIDOS'));
    } else if (codigo === 'text_too_long') {
      useAlert(textoLongo());
    } else if (codigo === 'instruction_too_long') {
      useAlert(instrucaoLonga());
    } else if (codigo === 'task_needs_conversation') {
      useAlert(t('CONVERSA_CANAL.EMAIL.IA.PRECISA_DA_CONVERSA'));
    } else if (codigo === 'task_invalid') {
      useAlert(t('CONVERSA_CANAL.EMAIL.IA.ACAO_INDISPONIVEL'));
    } else {
      useAlert(t('CONVERSA_CANAL.EMAIL.IA.FALHOU'));
    }
  };

  // Pedido novo do zero (menu) limpa a tela; o ajuste da sugestão (manterSugestao) só troca
  // a vez: a sugestão atual fica até a nova chegar e, se o ajuste falhar, continua lá.
  const comecar = manterSugestao => {
    if (!manterSugestao) {
      reset();
      return;
    }
    vez += 1;
    controle?.abort();
    controle = null;
  };

  const rodar = async (pedido, original, { manterSugestao = false } = {}) => {
    comecar(manterSugestao);
    const minhaVez = vez;
    controle = new AbortController();
    textoOriginal.value = original;
    isGenerating.value = true;
    try {
      const { data } = await chamar(pedido, {
        timeoutMs: ESPERA_MAXIMA_MS,
        signal: controle.signal,
      });
      if (minhaVez !== vez) return;
      if (data?.available && data?.text) {
        generatedContent.value = data.text;
        showEditor.value = true;
      } else if (data?.error === FALHA_DO_PROVEDOR) {
        // A chave está lá, o provedor é que falhou (rede, 5xx, tempo): "tente de novo".
        useAlert(t('CONVERSA_CANAL.EMAIL.IA.FALHOU'));
      } else {
        useAlert(t('CONVERSA_CANAL.EMAIL.IA.SEM_RESPOSTA'));
      }
    } catch (erro) {
      if (minhaVez === vez) avisarFalha(erro);
    } finally {
      if (minhaVez === vez) {
        isGenerating.value = false;
        controle = null;
      }
    }
  };

  // O aviso de por que não pedir, ou null quando o pedido pode ir.
  const motivoParaNaoPedir = pedido => {
    if (!pedido) return t('CONVERSA_CANAL.EMAIL.IA.ACAO_INDISPONIVEL');
    if (!temConversa.value && !TAREFAS_SEM_CONVERSA.includes(pedido.task)) {
      return t('CONVERSA_CANAL.EMAIL.IA.PRECISA_DA_CONVERSA');
    }
    if (pedido.draft === undefined) return null;
    if (!pedido.draft.trim()) return t('CONVERSA_CANAL.EMAIL.IA.ESCREVA_ANTES');
    if (pedido.draft.length > LIMITE_DO_TEXTO) return textoLongo();
    if ((pedido.instruction || '').length > LIMITE_DA_INSTRUCAO) {
      return instrucaoLonga();
    }
    return null;
  };

  const execute = async (acao, texto) => {
    const corpo = semAssinatura(texto ?? rascunho() ?? '');
    const pedido = pedidoDaAcao(acao, corpo);
    const motivo = motivoParaNaoPedir(pedido);
    if (motivo) {
      useAlert(motivo);
      return;
    }
    await rodar(pedido, pedido.draft === undefined ? null : corpo);
  };

  // O pedido livre embaixo do texto sugerido ajusta a sugestão (refine).
  const sendFollowUp = async instrucao => {
    const instruction = instrucao?.trim();
    if (!instruction || !generatedContent.value) return;
    const pedido = {
      task: 'refine',
      draft: generatedContent.value,
      instruction,
    };
    const motivo = motivoParaNaoPedir(pedido);
    if (motivo) {
      useAlert(motivo);
      return;
    }
    await rodar(pedido, textoOriginal.value, { manterSugestao: true });
  };

  const accept = () => {
    const texto = comAssinatura(generatedContent.value);
    reset();
    return texto;
  };

  return {
    disponivel,
    temConversa,
    avisoDasVariaveis,
    showEditor,
    isGenerating,
    isContentReady,
    generatedContent,
    isActive,
    isButtonDisabled,
    editorTransitionKey,
    reset,
    toggleEditor: () => {
      showEditor.value = !showEditor.value;
    },
    setContentReady: () => {
      isContentReady.value = true;
    },
    execute,
    sendFollowUp,
    accept,
  };
};

// Na caixa de resposta, o mesmo `copilot` serve aos dois: a IA do cliente no e-mail novo,
// o comportamento do Chatwoot nos outros canais. Escolhe a cada uso, porque a mesma caixa
// troca de conversa (e de canal) sem ser recriada.
const ESTADO = [
  'showEditor',
  'isGenerating',
  'isContentReady',
  'generatedContent',
  'isActive',
  'isButtonDisabled',
  'editorTransitionKey',
];
const ACOES = [
  'toggleEditor',
  'setContentReady',
  'execute',
  'sendFollowUp',
  'accept',
];

export const respostaComIa = (usarIa, padrao, ia) => {
  const atual = () => (usarIa.value ? ia : padrao);
  const estado = Object.fromEntries(
    ESTADO.map(chave => [
      chave,
      computed({
        get: () => atual()[chave].value,
        set: valor => {
          atual()[chave].value = valor;
        },
      }),
    ])
  );
  const acoes = Object.fromEntries(
    ACOES.map(chave => [chave, (...args) => atual()[chave](...args)])
  );
  return {
    ...estado,
    ...acoes,
    // Trocar de conversa zera as duas, seja qual for o canal de antes.
    reset: (...args) => {
      padrao.reset(...args);
      ia.reset();
    },
  };
};
