// #1872 — o ✨ do e-mail com a IA do cliente (copiloto da Autonom.ia), nunca o Captain.
import { defineComponent, h, nextTick, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import {
  ESPERA_MAXIMA_MS,
  INSTRUCAO_DE_CORRECAO,
  LIMITE_DA_INSTRUCAO,
  LIMITE_DO_TEXTO,
  VALIDADE_DO_SIM_MS,
  esquecerDisponibilidade,
  pedidoDaAcao,
  respostaComIa,
  useIaDoEmail,
  variaveisDoTexto,
} from '../email/useIaDoEmail';
import MenuDaIaDoEmail from '../email/MenuDaIaDoEmail.vue';
import {
  MessageMarkdownSerializer,
  MessageMarkdownTransformer,
  buildMessageSchema,
} from '@chatwoot/prosemirror-schema';
import { getFormattingForEditor } from 'dashboard/helper/editorHelper';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import NovaConversaCaixaDoEmail from '../../NovaConversa/NovaConversaCaixaDoEmail.vue';

const estado = vi.hoisted(() => ({
  config: { crmKanbanEnabled: true, crmCopilotEnabled: true },
  conta: 7,
  alerta: vi.fn(),
  api: { status: vi.fn(), run: vi.fn(), runText: vi.fn() },
  // O Captain: se alguém o chamar, estes espiões contam.
  captain: { useCaptain: vi.fn(), tarefa: vi.fn() },
}));

vi.mock('dashboard/composables/useCaptain', () => ({
  useCaptain: estado.captain.useCaptain,
}));
vi.mock('dashboard/api/captain/tasks', () => ({
  default: new Proxy({}, { get: () => estado.captain.tarefa }),
}));

vi.mock('dashboard/api/autonomiaCopilot', () => ({ default: estado.api }));
vi.mock('dashboard/composables', () => ({ useAlert: estado.alerta }));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useMapGetter: nome =>
      computed(() =>
        nome === 'globalConfig/get' ? estado.config : estado.conta
      ),
  };
});
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, valores) =>
      valores ? `${chave} ${JSON.stringify(valores)}` : chave,
    locale: { value: 'pt_BR' },
  }),
}));

// Monta o composable dentro de um componente (useI18n e companhia pedem setup).
const usar = opcoes => {
  let ia;
  mount(
    defineComponent({
      setup() {
        ia = useIaDoEmail(opcoes);
        return () => h('div');
      },
    })
  );
  return ia;
};

const resposta = data => Promise.resolve({ status: 200, data });

beforeEach(() => {
  esquecerDisponibilidade();
  estado.config = { crmKanbanEnabled: true, crmCopilotEnabled: true };
  estado.alerta.mockReset();
  estado.api.status.mockReset().mockReturnValue(resposta({ available: true }));
  estado.api.run.mockReset();
  estado.api.runText.mockReset();
});

describe('ações do menu → tarefas do copiloto (#1872)', () => {
  it.each([
    ['improve', { task: 'rewrite', draft: 'oi' }],
    ['professional', { task: 'rewrite', draft: 'oi', tone: 'professional' }],
    ['casual', { task: 'rewrite', draft: 'oi', tone: 'casual' }],
    ['straightforward', { task: 'rewrite', draft: 'oi', tone: 'direct' }],
    ['confident', { task: 'rewrite', draft: 'oi', tone: 'confident' }],
    ['friendly', { task: 'rewrite', draft: 'oi', tone: 'friendly' }],
    [
      'fix_spelling_grammar',
      { task: 'refine', draft: 'oi', instruction: INSTRUCAO_DE_CORRECAO },
    ],
    ['summarize', { task: 'summarize' }],
    ['reply_suggestion', { task: 'draft' }],
  ])('%s', (acao, pedido) => {
    expect(pedidoDaAcao(acao, 'oi')).toEqual(pedido);
  });

  it('ação que o e-mail não tem (perguntar ao Captain) não vira pedido', () => {
    expect(pedidoDaAcao('ask_copilot', 'oi')).toBeNull();
  });

  it('o ✨ da gaveta chama a IA do cliente e nunca o Captain (useCaptain, TasksAPI)', async () => {
    estado.api.runText.mockReturnValue(
      resposta({ text: 'Olá, Marina!', available: true })
    );
    // O editor de verdade (ProseMirror) fica de fora; o menu do ✨ é o de verdade, pelo slot.
    const EditorFalso = defineComponent({
      name: 'WootEditor',
      emits: ['executeCopilotAction'],
      setup:
        (_, { emit, slots }) =>
        () =>
          h('div', [
            slots['copilot-menu']?.({
              hasContent: true,
              run: acao => emit('executeCopilotAction', acao, 'Oi Marina'),
              close: () => {},
              root: null,
            }),
          ]),
    });
    const wrapper = mount(NovaConversaCaixaDoEmail, {
      props: {
        canal: { id: 4, channelType: INBOX_TYPES.EMAIL },
        mensagem: 'Oi Marina',
      },
      global: {
        mocks: { $t: chave => chave },
        stubs: {
          WootEditor: EditorFalso,
          NovaConversaBarraDoEmail: true,
          CopilotEditorSection: true,
          CopilotReplyBottomPanel: true,
          AttachmentPreviews: true,
          AvisoDeAssinatura: true,
          CampoDeEnderecos: true,
        },
      },
    });
    await flushPromises();

    await wrapper.find('[data-acao="straightforward"]').trigger('click');
    await flushPromises();

    expect(estado.api.runText).toHaveBeenCalledWith(
      { task: 'rewrite', draft: 'Oi Marina', tone: 'direct' },
      expect.anything()
    );
    expect(estado.captain.useCaptain).not.toHaveBeenCalled();
    expect(estado.captain.tarefa).not.toHaveBeenCalled();
  });
});

describe('o ✨ só onde o copiloto está disponível', () => {
  it('pergunta ao servidor uma vez por conta e liga o ✨', async () => {
    const ia = usar();
    await flushPromises();
    const outra = usar();
    await flushPromises();
    expect(ia.disponivel.value).toBe(true);
    expect(outra.disponivel.value).toBe(true);
    expect(estado.api.status).toHaveBeenCalledTimes(1);
  });

  it('sem chave na conta (ou copiloto desligado nela), o ✨ não aparece', async () => {
    estado.api.status.mockReturnValue(resposta({ available: false }));
    const ia = usar();
    await flushPromises();
    expect(ia.disponivel.value).toBe(false);
    // O "não" não fica guardado: a pessoa pode conectar a chave e abrir de novo.
    estado.api.status.mockReturnValue(resposta({ available: true }));
    const depois = usar();
    await flushPromises();
    expect(depois.disponivel.value).toBe(true);
    expect(estado.api.status).toHaveBeenCalledTimes(2);
  });

  it('fora do e-mail novo (WhatsApp, por exemplo), não pergunta; ao virar e-mail, pergunta', async () => {
    const emailNovo = ref(false);
    const ia = usar({ ativo: () => emailNovo.value });
    await flushPromises();
    expect(estado.api.status).not.toHaveBeenCalled();
    emailNovo.value = true;
    await flushPromises();
    expect(estado.api.status).toHaveBeenCalledTimes(1);
    expect(ia.disponivel.value).toBe(true);
  });

  it('com o copiloto desligado na instalação, nem pergunta', async () => {
    estado.config = { crmKanbanEnabled: true, crmCopilotEnabled: false };
    const ia = usar();
    await flushPromises();
    expect(ia.disponivel.value).toBe(false);
    expect(estado.api.status).not.toHaveBeenCalled();
  });

  it('se a consulta falha, o ✨ fica fora e a próxima tela pergunta de novo', async () => {
    estado.api.status.mockReturnValueOnce(Promise.reject(new Error('rede')));
    const ia = usar();
    await flushPromises();
    expect(ia.disponivel.value).toBe(false);
    const depois = usar();
    await flushPromises();
    expect(depois.disponivel.value).toBe(true);
  });

  it('o "sim" guardado vale 5 minutos; depois pergunta de novo', async () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    usar();
    await flushPromises();
    vi.setSystemTime(Date.now() + VALIDADE_DO_SIM_MS - 1000);
    usar();
    await flushPromises();
    expect(estado.api.status).toHaveBeenCalledTimes(1);
    vi.setSystemTime(Date.now() + 2000);
    usar();
    await flushPromises();
    expect(estado.api.status).toHaveBeenCalledTimes(2);
    vi.useRealTimers();
  });

  it('trocar de conta descarta o "sim" da conta de antes', async () => {
    usar();
    await flushPromises();
    estado.conta = 8;
    estado.api.status.mockReturnValue(resposta({ available: false }));
    const naOutra = usar();
    await flushPromises();
    expect(estado.api.status).toHaveBeenCalledTimes(2);
    expect(naOutra.disponivel.value).toBe(false);
    estado.conta = 7;
  });
});

// O caminho do aceitar: o texto da IA entra no editor (Markdown do Chatwoot, markdown-it com
// html: false) como texto, e volta igual para o envio. O HTML do envio é conferido no rspec.
describe('aceitar: o editor guarda HTML da IA como texto, nunca como HTML', () => {
  const schema = () => {
    const formato = getFormattingForEditor('Channel::Email', false);
    return buildMessageSchema(formato.marks, formato.nodes);
  };
  const noEditor = texto =>
    new MessageMarkdownTransformer(schema()).parse(texto);

  it.each([
    ['a<b', 'a<b'],
    ['R&D', 'R&D'],
    ['<script>alert(1)</script>Olá', '<script>alert(1)</script>Olá'],
    ['<img src=x onerror=alert(1)>', '<img src=x onerror=alert(1)>'],
  ])('%s fica literal e volta igual', (texto, literal) => {
    const doc = noEditor(texto);
    expect(doc.textContent).toBe(literal);
    const tipos = [];
    doc.descendants(no => {
      tipos.push(no.type.name);
    });
    expect(tipos).not.toContain('image');
    expect(MessageMarkdownSerializer.serialize(doc)).toBe(texto);
  });

  it('um endereço entre < > vira link de e-mail, com o texto à vista', () => {
    const doc = noEditor('Fale com <suporte@x.com>');
    expect(doc.textContent).toBe('Fale com suporte@x.com');
    expect(MessageMarkdownSerializer.serialize(doc)).toBe(
      'Fale com [suporte@x.com](mailto:suporte@x.com)'
    );
  });
});

describe('pedir, aceitar e descartar', () => {
  it('na resposta (com conversa), chama o copiloto da conversa e mostra a sugestão', async () => {
    estado.api.run.mockReturnValue(
      resposta({ text: 'Melhor', available: true })
    );
    const ia = usar({ conversaId: () => 42 });
    await ia.execute('straightforward', 'texto meu');
    expect(estado.api.run).toHaveBeenCalledWith(
      42,
      { task: 'rewrite', draft: 'texto meu', tone: 'direct' },
      expect.objectContaining({ timeoutMs: ESPERA_MAXIMA_MS })
    );
    expect(ia.generatedContent.value).toBe('Melhor');
    expect(ia.showEditor.value).toBe(true);
    expect(ia.isGenerating.value).toBe(false);
  });

  it('na gaveta (sem conversa), vai pelo caminho só de texto', async () => {
    estado.api.runText.mockReturnValue(
      resposta({ text: 'Ok', available: true })
    );
    const ia = usar();
    await ia.execute('improve', 'texto meu');
    expect(estado.api.runText).toHaveBeenCalledWith(
      { task: 'rewrite', draft: 'texto meu' },
      expect.objectContaining({ timeoutMs: ESPERA_MAXIMA_MS })
    );
    expect(estado.api.run).not.toHaveBeenCalled();
  });

  it('na gaveta, resumir ou sugerir resposta avisam que precisam de conversa', async () => {
    const ia = usar();
    await ia.execute('summarize', 'texto');
    await ia.execute('reply_suggestion', 'texto');
    expect(estado.alerta).toHaveBeenCalledWith(
      'CONVERSA_CANAL.EMAIL.IA.PRECISA_DA_CONVERSA'
    );
    expect(estado.alerta).toHaveBeenCalledTimes(2);
    expect(estado.api.runText).not.toHaveBeenCalled();
  });

  it('a assinatura não vai para a IA e volta ao aceitar', async () => {
    estado.api.runText.mockReturnValue(
      resposta({ text: 'Olá, tudo certo.', available: true })
    );
    const ia = usar({
      assinatura: () => ({ texto: 'Ana', canal: 'Channel::Email' }),
    });
    await ia.execute('improve', 'oi tudo bem\n\n--\n\nAna');
    expect(estado.api.runText.mock.calls[0][0].draft).toBe('oi tudo bem');
    ia.setContentReady();
    expect(ia.accept()).toBe('Olá, tudo certo.\n\n--\n\nAna');
    expect(ia.isActive.value).toBe(false);
  });

  it('sem texto, avisa para escrever antes', async () => {
    const ia = usar({ rascunho: () => '   ' });
    await ia.execute('improve');
    expect(estado.alerta).toHaveBeenCalledWith(
      'CONVERSA_CANAL.EMAIL.IA.ESCREVA_ANTES'
    );
  });

  it('texto maior que o limite do servidor: avisa em vez de cortar calado', async () => {
    const ia = usar();
    await ia.execute('improve', 'a'.repeat(LIMITE_DO_TEXTO + 1));
    expect(estado.alerta).toHaveBeenCalledWith(
      'CONVERSA_CANAL.EMAIL.IA.TEXTO_LONGO {"limite":"6.000"}'
    );
    expect(estado.api.runText).not.toHaveBeenCalled();
  });

  it('IA sem resposta (sem chave, por exemplo): aviso claro, nunca silêncio', async () => {
    estado.api.runText.mockReturnValue(
      resposta({ text: null, available: false })
    );
    const ia = usar();
    await ia.execute('improve', 'texto');
    expect(estado.alerta).toHaveBeenCalledWith(
      'CONVERSA_CANAL.EMAIL.IA.SEM_RESPOSTA'
    );
    expect(ia.isActive.value).toBe(false);
  });

  it('o provedor falhou com a chave certa (ai_failed): "tente de novo", não "confira a chave"', async () => {
    estado.api.runText.mockReturnValue(
      resposta({ text: null, available: false, error: 'ai_failed' })
    );
    const ia = usar();
    await ia.execute('improve', 'texto');
    expect(estado.alerta).toHaveBeenCalledWith(
      'CONVERSA_CANAL.EMAIL.IA.FALHOU'
    );
    expect(estado.alerta).not.toHaveBeenCalledWith(
      'CONVERSA_CANAL.EMAIL.IA.SEM_RESPOSTA'
    );
    expect(ia.showEditor.value).toBe(false);
  });

  it('erro na chamada: aviso claro e o texto fica como estava', async () => {
    estado.api.runText.mockReturnValue(Promise.reject(new Error('500')));
    const ia = usar();
    await ia.execute('improve', 'texto');
    expect(estado.alerta).toHaveBeenCalledWith(
      'CONVERSA_CANAL.EMAIL.IA.FALHOU'
    );
    expect(ia.isActive.value).toBe(false);
  });

  it('descartar enquanto a IA pensa ignora a resposta que chega depois', async () => {
    let responder;
    estado.api.runText.mockReturnValue(
      new Promise(resolve => {
        responder = resolve;
      })
    );
    const ia = usar();
    const pedido = ia.execute('improve', 'texto');
    expect(ia.isGenerating.value).toBe(true);
    ia.reset();
    responder({ data: { text: 'tarde demais', available: true } });
    await pedido;
    expect(ia.generatedContent.value).toBe('');
    expect(ia.isActive.value).toBe(false);
  });

  it('descartar para o poll: o AbortSignal do pedido fica abortado', async () => {
    estado.api.runText.mockReturnValue(new Promise(() => {}));
    const ia = usar();
    ia.execute('improve', 'texto');
    await flushPromises();
    const { signal } = estado.api.runText.mock.calls[0][1];
    expect(signal.aborted).toBe(false);
    ia.reset();
    expect(signal.aborted).toBe(true);
  });

  const recusa = (status, error) =>
    Object.assign(new Error(error), { response: { status, data: { error } } });

  it('servidor recusou por tamanho (422 text_too_long): aviso de texto longo', async () => {
    estado.api.runText.mockReturnValue(
      Promise.reject(recusa(422, 'text_too_long'))
    );
    const ia = usar();
    await ia.execute('improve', 'texto');
    expect(estado.alerta).toHaveBeenCalledWith(
      'CONVERSA_CANAL.EMAIL.IA.TEXTO_LONGO {"limite":"6.000"}'
    );
  });

  it('passou do limite de pedidos (429 too_many_requests): aviso próprio', async () => {
    estado.api.runText.mockReturnValue(
      Promise.reject(recusa(429, 'too_many_requests'))
    );
    const ia = usar();
    await ia.execute('improve', 'texto');
    expect(estado.alerta).toHaveBeenCalledWith(
      'CONVERSA_CANAL.EMAIL.IA.MUITOS_PEDIDOS'
    );
  });

  it('o pedido de ajuste confere os tetos antes de ir ao servidor', async () => {
    estado.api.runText.mockReturnValue(
      resposta({ text: 'Primeira', available: true })
    );
    const ia = usar();
    await ia.execute('improve', 'texto');
    await ia.sendFollowUp('a'.repeat(LIMITE_DA_INSTRUCAO + 1));
    expect(estado.alerta).toHaveBeenCalledWith(
      'CONVERSA_CANAL.EMAIL.IA.INSTRUCAO_LONGA {"limite":"1.000"}'
    );
    expect(estado.api.runText).toHaveBeenCalledTimes(1);
    expect(ia.generatedContent.value).toBe('Primeira');
  });

  it('a IA demorou além da espera: aviso próprio, sem ficar pensando', async () => {
    const erro = Object.assign(new Error('ai_request_timeout'), {
      code: 'ai_request_timeout',
    });
    estado.api.runText.mockReturnValue(Promise.reject(erro));
    const ia = usar();
    await ia.execute('improve', 'texto');
    expect(estado.alerta).toHaveBeenCalledWith(
      'CONVERSA_CANAL.EMAIL.IA.DEMOROU'
    );
    expect(ia.isGenerating.value).toBe(false);
  });

  it('variáveis: acha as {{variáveis}} sem regex, em ordem', () => {
    expect(
      variaveisDoTexto('Oi {{contact.name}}, {{ agent.name }} e {{}} {{x')
    ).toEqual(['{{agent.name}}', '{{contact.name}}']);
  });

  it('a sugestão mudou as variáveis: avisa, sem bloquear o Aceitar', async () => {
    estado.api.runText.mockReturnValue(
      resposta({ text: 'Olá, cliente!', available: true })
    );
    const ia = usar();
    await ia.execute('improve', 'Oi {{contact.name}}');
    expect(ia.avisoDasVariaveis.value).toBe(
      'CONVERSA_CANAL.EMAIL.IA.VARIAVEIS_MUDARAM {"antes":"{{contact.name}}","agora":"CONVERSA_CANAL.EMAIL.IA.NENHUMA_VARIAVEL"}'
    );
    ia.setContentReady();
    expect(ia.isButtonDisabled.value).toBe(false);
    expect(ia.accept()).toBe('Olá, cliente!');
  });

  it('mesmas variáveis: sem aviso', async () => {
    estado.api.runText.mockReturnValue(
      resposta({ text: 'Olá, {{contact.name}}!', available: true })
    );
    const ia = usar();
    await ia.execute('improve', 'Oi {{contact.name}}');
    expect(ia.avisoDasVariaveis.value).toBeNull();
  });

  it('o pedido livre embaixo da sugestão ajusta a sugestão (refine)', async () => {
    estado.api.runText
      .mockReturnValueOnce(resposta({ text: 'Primeira', available: true }))
      .mockReturnValueOnce(resposta({ text: 'Curta', available: true }));
    const ia = usar();
    await ia.execute('improve', 'texto');
    await ia.sendFollowUp('mais curto');
    expect(estado.api.runText).toHaveBeenLastCalledWith(
      { task: 'refine', draft: 'Primeira', instruction: 'mais curto' },
      expect.anything()
    );
    expect(ia.generatedContent.value).toBe('Curta');
  });

  it('o ajuste mantém a sugestão na tela enquanto a nova não chega', async () => {
    let entregar;
    estado.api.runText
      .mockReturnValueOnce(resposta({ text: 'Primeira', available: true }))
      .mockReturnValueOnce(
        new Promise(resolve => {
          entregar = resolve;
        })
      );
    const ia = usar();
    await ia.execute('improve', 'texto');
    const pedido = ia.sendFollowUp('mais curto');
    expect(ia.isGenerating.value).toBe(true);
    expect(ia.showEditor.value).toBe(true);
    expect(ia.generatedContent.value).toBe('Primeira');
    entregar({ status: 200, data: { text: 'Curta', available: true } });
    await pedido;
    expect(ia.generatedContent.value).toBe('Curta');
  });

  it('o ajuste falhou: a sugestão anterior continua, com o aviso', async () => {
    estado.api.runText
      .mockReturnValueOnce(resposta({ text: 'Primeira', available: true }))
      .mockReturnValueOnce(Promise.reject(new Error('500')));
    const ia = usar();
    await ia.execute('improve', 'texto');
    await ia.sendFollowUp('mais curto');
    expect(estado.alerta).toHaveBeenCalledWith(
      'CONVERSA_CANAL.EMAIL.IA.FALHOU'
    );
    expect(ia.generatedContent.value).toBe('Primeira');
    expect(ia.showEditor.value).toBe(true);
    expect(ia.isGenerating.value).toBe(false);
    expect(ia.accept()).toBe('Primeira');
  });

  it('servidor recusou a instrução (422 instruction_too_long): aviso próprio', async () => {
    estado.api.runText.mockReturnValue(
      Promise.reject(recusa(422, 'instruction_too_long'))
    );
    const ia = usar();
    await ia.execute('improve', 'texto');
    expect(estado.alerta).toHaveBeenCalledWith(
      'CONVERSA_CANAL.EMAIL.IA.INSTRUCAO_LONGA {"limite":"1.000"}'
    );
  });

  it('servidor recusou a ação (422 task_invalid): ação indisponível, não "precisa de conversa"', async () => {
    estado.api.runText.mockReturnValue(
      Promise.reject(recusa(422, 'task_invalid'))
    );
    const ia = usar();
    await ia.execute('improve', 'texto');
    expect(estado.alerta).toHaveBeenCalledWith(
      'CONVERSA_CANAL.EMAIL.IA.ACAO_INDISPONIVEL'
    );
    expect(estado.alerta).not.toHaveBeenCalledWith(
      'CONVERSA_CANAL.EMAIL.IA.PRECISA_DA_CONVERSA'
    );
  });
});

describe('respostaComIa: o mesmo `copilot` na caixa de resposta', () => {
  const falso = () => ({
    showEditor: ref(false),
    isGenerating: ref(false),
    isContentReady: ref(false),
    generatedContent: ref(''),
    isActive: ref(false),
    isButtonDisabled: ref(false),
    editorTransitionKey: ref('rich'),
    reset: vi.fn(),
    toggleEditor: vi.fn(),
    setContentReady: vi.fn(),
    execute: vi.fn(),
    sendFollowUp: vi.fn(),
    accept: vi.fn(() => 'aceito'),
  });

  it('no e-mail novo vai para a IA do cliente; nos outros canais, para o padrão', async () => {
    const emailNovo = ref(true);
    const padrao = falso();
    const ia = falso();
    const copilot = respostaComIa(emailNovo, padrao, ia);

    copilot.execute('improve', 'oi');
    expect(ia.execute).toHaveBeenCalledWith('improve', 'oi');
    expect(padrao.execute).not.toHaveBeenCalled();
    ia.generatedContent.value = 'da IA';
    expect(copilot.generatedContent.value).toBe('da IA');
    copilot.showEditor.value = true;
    expect(ia.showEditor.value).toBe(true);

    emailNovo.value = false;
    await nextTick();
    copilot.execute('improve', 'oi');
    expect(padrao.execute).toHaveBeenCalledWith('improve', 'oi');
    expect(copilot.generatedContent.value).toBe('');
  });

  it('trocar de conversa zera as duas', () => {
    const padrao = falso();
    const ia = falso();
    respostaComIa(ref(true), padrao, ia).reset();
    expect(padrao.reset).toHaveBeenCalled();
    expect(ia.reset).toHaveBeenCalled();
  });
});

describe('MenuDaIaDoEmail', () => {
  const montar = props =>
    mount(MenuDaIaDoEmail, {
      props,
      global: { mocks: { $t: chave => chave } },
    });
  const acoes = wrapper =>
    wrapper.findAll('[data-acao]').map(b => b.attributes('data-acao'));

  it('na resposta com texto: mexer no texto e as ações da conversa', () => {
    expect(acoes(montar({ temTexto: true, temConversa: true }))).toEqual([
      'improve',
      'fix_spelling_grammar',
      'professional',
      'casual',
      'straightforward',
      'confident',
      'friendly',
      'reply_suggestion',
      'summarize',
    ]);
  });

  it('na gaveta (sem conversa): só as ações de texto, sem resumir nem sugerir', () => {
    const lista = acoes(montar({ temTexto: true, temConversa: false }));
    expect(lista).not.toContain('summarize');
    expect(lista).not.toContain('reply_suggestion');
    expect(lista).toContain('improve');
  });

  it('sem texto na gaveta: pede para escrever antes', () => {
    const wrapper = montar({ temTexto: false, temConversa: false });
    expect(acoes(wrapper)).toEqual([]);
    expect(wrapper.find('[data-escreva-antes]').exists()).toBe(true);
  });

  it('clicar executa a ação', async () => {
    const wrapper = montar({ temTexto: true, temConversa: true });
    await wrapper.find('[data-acao="straightforward"]').trigger('click');
    expect(wrapper.emitted('executar')).toEqual([['straightforward']]);
  });

  it('teclado: o foco entra no menu; o Esc no menu ou no editor fecha e devolve o foco ao texto', () => {
    // A raiz do editor (o slot do Editor a passa) com o texto e o menu dentro, como na tela.
    const raiz = document.createElement('div');
    const texto = document.createElement('div');
    texto.setAttribute('contenteditable', 'true');
    texto.tabIndex = 0;
    raiz.appendChild(texto);
    const lugarDoMenu = document.createElement('div');
    raiz.appendChild(lugarDoMenu);
    document.body.appendChild(raiz);

    const wrapper = mount(MenuDaIaDoEmail, {
      props: { temTexto: true, temConversa: true, editor: raiz },
      global: { mocks: { $t: chave => chave } },
      attachTo: lugarDoMenu,
    });
    const menu = wrapper.find('[data-menu-da-ia]');
    expect(menu.attributes('tabindex')).toBe('-1');
    expect(document.activeElement).toBe(menu.element);

    // Esc fora do menu e do editor (em outro campo da tela) não é com ele.
    document.body.dispatchEvent(
      new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })
    );
    expect(wrapper.emitted('fechar')).toBeUndefined();

    menu.element.dispatchEvent(
      new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })
    );
    expect(wrapper.emitted('fechar')).toHaveLength(1);
    expect(document.activeElement).toBe(texto);

    wrapper.unmount();
    raiz.remove();
  });

  it('a seta "descer" não tira o foco do menu; com o foco perdido no BODY, o Esc ainda fecha', async () => {
    const raiz = document.createElement('div');
    const texto = document.createElement('div');
    texto.setAttribute('contenteditable', 'true');
    texto.tabIndex = 0;
    const lugarDoMenu = document.createElement('div');
    raiz.append(texto, lugarDoMenu);
    document.body.appendChild(raiz);
    const wrapper = mount(MenuDaIaDoEmail, {
      props: { temTexto: true, temConversa: true, editor: raiz },
      global: { mocks: { $t: chave => chave } },
      attachTo: lugarDoMenu,
    });
    const menu = wrapper.find('[data-menu-da-ia]').element;
    expect(document.activeElement).toBe(menu);

    // Pela Tab, a seta pode ter o foco e sumir com ele no fim da lista.
    menu.blur();
    expect(document.activeElement).toBe(document.body);
    document.body.dispatchEvent(
      new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })
    );
    expect(wrapper.emitted('fechar')).toHaveLength(1);
    expect(document.activeElement).toBe(texto);

    wrapper.unmount();
    raiz.remove();
  });

  // A tela como no navegador (900 px de altura): o texto do editor, o ✨ e o menu (fixed, preso à
  // tela, fora da rolagem da caixa de resposta).
  const montarNaTela = async ({ brilho: [topo, base], alturaDoMenu }) => {
    const raiz = document.createElement('div');
    const texto = document.createElement('div');
    texto.setAttribute('contenteditable', 'true');
    const brilho = document.createElement('div');
    brilho.className = 'ProseMirror-copilot';
    brilho.getBoundingClientRect = () => ({
      top: topo,
      bottom: base,
      left: 40,
    });
    const lugarDoMenu = document.createElement('div');
    raiz.append(texto, brilho, lugarDoMenu);
    document.body.appendChild(raiz);

    const espioes = [
      vi.spyOn(window, 'innerHeight', 'get').mockReturnValue(900),
      vi.spyOn(window, 'innerWidth', 'get').mockReturnValue(1440),
      vi
        .spyOn(HTMLElement.prototype, 'scrollHeight', 'get')
        .mockReturnValue(alturaDoMenu),
    ];
    const focar = vi.spyOn(HTMLElement.prototype, 'focus');
    const wrapper = mount(MenuDaIaDoEmail, {
      props: { temTexto: true, temConversa: true, editor: raiz },
      global: { mocks: { $t: chave => chave } },
      attachTo: lugarDoMenu,
    });
    await flushPromises();
    const limpar = () => {
      wrapper.unmount();
      raiz.remove();
      [...espioes, focar].forEach(espiao => espiao.mockRestore());
    };
    return { wrapper, texto, focar, limpar };
  };
  const estilo = wrapper => wrapper.find('[data-menu-da-ia]').element.style;

  it('cabe embaixo do ✨: abre embaixo, sem rolar a caixa (o menu cobria o ✨ e o clique o fechava)', async () => {
    const tela = await montarNaTela({ brilho: [100, 124], alturaDoMenu: 395 });
    expect(tela.focar).toHaveBeenCalledWith({ preventScroll: true });
    expect(estilo(tela.wrapper).top).toBe('132px');
    expect(estilo(tela.wrapper).left).toBe('40px');
    expect(estilo(tela.wrapper).maxHeight).toBe('');
    expect(tela.wrapper.find('[data-menu-da-ia]').classes()).toContain('fixed');
    tela.limpar();
  });

  it('na resposta (✨ em 531–555 numa tela de 900): mais espaço em cima, abre para cima inteiro', async () => {
    // Embaixo: 900 - 555 - 16 = 329 px, não cabem 395. Em cima: 531 - 16 = 515 px.
    const tela = await montarNaTela({ brilho: [531, 555], alturaDoMenu: 395 });
    expect(estilo(tela.wrapper).top).toBe(`${531 - 8 - 395}px`);
    expect(estilo(tela.wrapper).maxHeight).toBe('395px');
    tela.limpar();
  });

  it('nenhum lado cabe: o lado maior, com altura máxima e rolagem própria', async () => {
    // Em cima: 300 - 16 = 284; embaixo: 900 - 324 - 16 = 560 → embaixo, 560 px.
    const tela = await montarNaTela({ brilho: [300, 324], alturaDoMenu: 700 });
    expect(estilo(tela.wrapper).top).toBe('332px');
    expect(estilo(tela.wrapper).maxHeight).toBe('560px');
    expect(tela.wrapper.find('[data-lista-da-ia]').classes()).toContain(
      'overflow-y-auto'
    );
    tela.limpar();
  });

  it('quando rola por dentro, mostra o indicador da gaveta (esmaecido e seta que rola)', async () => {
    const tela = await montarNaTela({ brilho: [300, 324], alturaDoMenu: 700 });
    const lista = tela.wrapper.find('[data-lista-da-ia]').element;
    // jsdom não tem layout: a lista mostra 560 px dos 700.
    Object.defineProperty(lista, 'clientHeight', { value: 560 });
    lista.scrollTop = 0;
    lista.scrollBy = vi.fn();
    lista.dispatchEvent(new Event('scroll'));
    await flushPromises();

    expect(
      tela.wrapper.findComponent({ name: 'NovaConversaMaisAbaixo' }).exists()
    ).toBe(true);
    expect(tela.wrapper.find('[data-esmaecido-da-gaveta]').exists()).toBe(true);
    const seta = tela.wrapper.find('[data-mais-abaixo]');
    expect(seta.attributes('aria-controls')).toBe(lista.id);
    await seta.trigger('click');
    expect(lista.scrollBy).toHaveBeenCalled();
    tela.limpar();
  });

  it('tudo à vista: sem o indicador', async () => {
    const tela = await montarNaTela({ brilho: [100, 124], alturaDoMenu: 395 });
    const lista = tela.wrapper.find('[data-lista-da-ia]').element;
    Object.defineProperty(lista, 'clientHeight', { value: 395 });
    lista.dispatchEvent(new Event('scroll'));
    await flushPromises();
    expect(tela.wrapper.find('[data-mais-abaixo]').exists()).toBe(false);
    tela.limpar();
  });

  it('Esc com o foco no menu: o foco volta ao texto do editor, não ao BODY', async () => {
    const tela = await montarNaTela({ brilho: [100, 124], alturaDoMenu: 395 });
    tela.focar.mockRestore();
    const menu = tela.wrapper.find('[data-menu-da-ia]').element;
    menu.focus();
    menu.dispatchEvent(
      new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })
    );
    expect(tela.wrapper.emitted('fechar')).toHaveLength(1);
    expect(document.activeElement).toBe(tela.texto);
    tela.limpar();
  });

  it('o menu sai da tela com o foco nele (ação escolhida, clique fora): o foco volta ao texto', async () => {
    const tela = await montarNaTela({ brilho: [100, 124], alturaDoMenu: 395 });
    tela.focar.mockRestore();
    tela.wrapper.find('[data-acao="improve"]').element.focus();
    tela.wrapper.unmount();
    expect(document.activeElement).toBe(tela.texto);
    tela.wrapper.unmount = () => {};
    tela.limpar();
  });

  it('botões com alvo de toque de 44 px', () => {
    const wrapper = montar({ temTexto: true, temConversa: true });
    wrapper.findAll('button').forEach(botao => {
      expect(botao.classes()).toContain('min-h-11');
    });
  });
});
