import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import EtapaConte from '../../components/criar/EtapaConte.vue';
import EtapaConfira from '../../components/criar/EtapaConfira.vue';
import EtapaComece from '../../components/criar/EtapaComece.vue';
import EtapaPronto from '../../components/criar/EtapaPronto.vue';
import { perguntasDeTeste } from '../../constants/criacao';

// Cópia real em pt_BR (protótipo jornada.html, T03–T06): os textos exatos, {nome} neutro e as
// palavras que saíram da tela nova.
const i18n = withFullI18n('pt_BR');

vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return { useMapGetter: () => computed(() => false) };
});
vi.mock('../../composables/usePermissoesDaJornada', async () => {
  const { computed } = await import('vue');
  return {
    usePermissoesDaJornada: () => ({
      podeConectarCanal: computed(() => true),
      podeEscolherQuemRecebe: computed(() => true),
    }),
  };
});
vi.mock('vue-router', () => ({
  useRouter: () => ({ resolve: () => ({ href: '/app/x' }) }),
}));

const PROIBIDAS = [
  'Ligar',
  'Ligue',
  '%',
  'Primeira mensagem',
  'Perguntas iniciais',
  'Transferir',
  'Limite de confiança',
  'confiança',
  'Certeza',
];
const semProibidas = texto =>
  PROIBIDAS.forEach(palavra => expect(texto).not.toContain(palavra));

const respondido = [
  { de: 'cliente', texto: 'Vocês abrem no sábado?' },
  { de: 'agente', texto: 'Abrimos sim.' },
];

describe('cópia da criação em pt_BR', () => {
  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('Conte: the intro, the ideas label and the optional clip line', () => {
    const wrapper = mount(EtapaConte, {
      props: {
        falas: [],
        estadoDoMaterial: () => 'lendo',
        respostas: 1,
        ideias: [],
      },
    });
    expect(wrapper.text()).toContain(
      'Vou te fazer umas perguntas curtas. O agente só começa a atender quando você mandar.'
    );
    expect(wrapper.get('[data-linha-anexo]').text()).toBe(
      'Tem um cardápio, uma tabela ou o seu site? Mande aqui. Não é obrigatório.'
    );
    semProibidas(wrapper.text());
  });

  it('Conte: failure card keeps what was told', () => {
    const wrapper = mount(EtapaConte, {
      props: { falas: [], estadoDoMaterial: () => 'lendo', falhou: true },
    });
    expect(wrapper.get('[data-erro-conversa]').text()).toContain(
      'Não consegui responder agora.'
    );
    expect(wrapper.get('[data-erro-conversa]').text()).toContain(
      'O que você contou está guardado.'
    );
  });

  it('Confira: the test texts and the start button with the channel', () => {
    const rotulo = i18n.global.t('AGENTS.JORNADA.CRIAR.CONFIRA.COMECAR_NO', {
      canal: i18n.global.t('AGENTS.JORNADA.CRIAR.CANAL.WHATSAPP'),
    });
    expect(rotulo).toBe('Começar a atender no WhatsApp');

    const vazio = mount(EtapaConfira, {
      props: { nome: 'Duda', perguntas: ['SABADO'], rotuloComecar: rotulo },
    });
    expect(vazio.text()).toContain('Teste como se fosse seu cliente');
    expect(vazio.text()).toContain(
      'Ninguém recebe estas mensagens. É só um teste.'
    );
    expect(vazio.get('[data-vazio]').text()).toBe(
      'Toque numa pergunta ou escreva a sua.'
    );
    expect(vazio.get('[data-teste-opcional]').text()).toBe(
      'Se quiser, teste antes: faça uma pergunta e veja como Duda responde.'
    );
    expect(vazio.get('[data-comecar]').text()).toContain(
      'Começar a atender no WhatsApp'
    );
    expect(vazio.get('[data-perguntas]').text()).toBe('Vocês abrem no sábado?');

    const respondida = mount(EtapaConfira, {
      props: {
        nome: 'Duda',
        rotuloComecar: rotulo,
        mensagens: [respondido[0], { ...respondido[1], passaria: true }],
        respondidas: 1,
      },
    });
    expect(respondida.get('[data-comecar]').text()).toContain(
      'Começar a atender no WhatsApp'
    );
    expect(respondida.get('[data-comecar]').text()).toContain(
      'Duda passa a responder as mensagens dos seus clientes.'
    );
    expect(respondida.get('[data-aviso]').text()).toBe(
      'Aqui Duda avisaria que vai chamar alguém da equipe.'
    );
    expect(respondida.get('[data-ajustes]').text()).toContain(
      'Fazer ajustes avançados'
    );
    expect(respondida.get('[data-ajustes]').text()).toContain(
      'Duda fica parado até você ligar.'
    );
    semProibidas(respondida.text());
  });

  it.each([
    ['falha', 'Duda não respondeu agora.Isso não afeta seus clientes.'],
    ['demora', 'Está demorando. Tente de novo.'],
    [
      'incompleto',
      'Duda ainda não sabe o suficiente. Conte mais um pouco ao lado.',
    ],
  ])('Confira: the %s state', (problema, texto) => {
    const wrapper = mount(EtapaConfira, {
      props: { nome: 'Duda', mensagens: [respondido[0]], problema },
    });
    expect(wrapper.get('[data-erro-teste]').text()).toContain(texto);
  });

  it('Confira without a channel says what is missing', () => {
    const wrapper = mount(EtapaConfira, {
      props: { nome: 'Duda', mensagens: respondido, respondidas: 1 },
    });
    expect(wrapper.get('[data-sem-canal]').text()).toContain(
      'Duda já pode atender. Falta escolher onde.'
    );
  });

  it('Confira and Pronto for the team copilot talk about the team, never about customers or channels (#1494)', () => {
    const rotulo = i18n.global.t(
      'AGENTS.JORNADA.CRIAR.CONFIRA.COMECAR_COPILOTO'
    );
    expect(rotulo).toBe('Começar a ajudar a equipe');
    const confira = mount(EtapaConfira, {
      props: {
        nome: 'Duda',
        interno: true,
        perguntas: perguntasDeTeste('custom', true),
        rotuloComecar: rotulo,
        mensagens: respondido,
        respondidas: 1,
      },
    });
    expect(confira.text()).toContain('Teste como se fosse da equipe');
    expect(confira.get('[data-perguntas]').text()).toContain(
      'Um cliente pediu desconto. Como respondo?'
    );
    expect(confira.get('[data-perguntas]').text()).toContain(
      'Rascunhe uma resposta sobre o prazo de entrega'
    );
    expect(confira.get('[data-comecar]').text()).toContain(
      'Duda passa a ajudar a equipe dentro das conversas. Nunca fala com cliente.'
    );
    expect(confira.text()).not.toContain('seus clientes');
    expect(confira.text()).not.toContain('canal');
    semProibidas(confira.text());

    const pronto = mount(EtapaPronto, {
      props: { nome: 'Duda', interno: true },
    });
    expect(pronto.get('h1').text()).toBe('Duda já está ajudando a equipe');
    expect(pronto.text()).toContain('Duda nunca fala com cliente.');
    expect(pronto.text()).not.toContain('passa a conversa para a equipe');
    semProibidas(pronto.text());
  });

  it('the team copilot never reads "atender" nor "Atendido por" (#1494)', () => {
    const semAtender = texto => {
      expect(texto).not.toContain('atend');
      expect(texto).not.toContain('Atend');
    };

    const conte = mount(EtapaConte, {
      props: { falas: [], estadoDoMaterial: () => 'lendo', interno: true },
    });
    expect(conte.get('[data-intro]').text()).toBe(
      'Vou te fazer umas perguntas curtas. O agente só começa a ajudar a equipe quando você mandar.'
    );
    semAtender(conte.text());

    const confira = mount(EtapaConfira, {
      props: {
        nome: 'Duda',
        interno: true,
        mensagens: respondido,
        rotuloComecar: 'Começar a ajudar a equipe',
      },
    });
    expect(confira.text()).toContain('Duda · ajuda da equipe');
    // #1504 — o Começar e "Fazer ajustes avançados" aparecem sem teste, e também sem "atender".
    expect(confira.find('[data-comecar]').exists()).toBe(true);
    expect(confira.text()).toContain('Fazer ajustes avançados');
    semAtender(confira.text());

    // Sem rótulo, o copiloto nunca cai em "falta escolher onde" (não tem canal).
    const semRotulo = mount(EtapaConfira, {
      props: { nome: 'Duda', interno: true },
    });
    expect(semRotulo.find('[data-sem-canal]').exists()).toBe(false);
    semAtender(semRotulo.text());

    const pronto = mount(EtapaPronto, {
      props: {
        nome: 'Duda',
        interno: true,
        ultimo: { pergunta: 'Como respondo?', resposta: 'Assim.' },
      },
    });
    expect(pronto.get('[data-celular]').text()).toContain(
      'Duda · ajuda da equipe'
    );
    semAtender(pronto.text());

    const erro = i18n.global.t('AGENTS.JORNADA.CRIAR.COMECE.ERRO_INTERNO', {
      nome: 'Duda',
    });
    expect(erro).toBe(
      'Não deu para começar a ajudar a equipe. Nada mudou: Duda ainda não está ajudando.'
    );
    semAtender(erro);
  });

  it('the copilot test shows the team as the sender, without the hand-off band nor the company (#1494)', () => {
    const confira = mount(EtapaConfira, {
      props: {
        nome: 'Duda',
        empresa: 'Loja da Ana',
        interno: true,
        mensagens: [respondido[0], { ...respondido[1], passaria: true }],
        respondidas: 1,
      },
    });
    expect(confira.find('[data-balao="equipe"]').text()).toContain('Equipe:');
    expect(confira.find('[data-balao="cliente"]').exists()).toBe(false);
    expect(confira.text()).not.toContain('Cliente:');
    expect(confira.find('[data-aviso]').exists()).toBe(false);
    expect(confira.text()).not.toContain('passaria');
    expect(confira.text()).not.toContain('Loja da Ana');

    const falha = mount(EtapaConfira, {
      props: {
        nome: 'Duda',
        interno: true,
        mensagens: [respondido[0]],
        problema: 'falha',
      },
    });
    expect(falha.get('[data-erro-teste]').text()).toContain(
      'É só um teste: ninguém recebe esta resposta.'
    );
    expect(falha.text()).not.toContain('clientes');

    const pronto = mount(EtapaPronto, {
      props: {
        nome: 'Duda',
        empresa: 'Loja da Ana',
        interno: true,
        ultimo: { pergunta: 'Como respondo?', resposta: 'Assim.' },
      },
    });
    const celular = pronto.get('[data-celular]');
    expect(celular.find('[data-balao="equipe"]').text()).toContain('Equipe:');
    expect(celular.text()).not.toContain('Cliente:');
    expect(celular.text()).not.toContain('Loja da Ana');
  });

  it('the customer agent test keeps the customer bubble, the band and the company', () => {
    const confira = mount(EtapaConfira, {
      props: {
        nome: 'Duda',
        empresa: 'Loja da Ana',
        mensagens: [respondido[0], { ...respondido[1], passaria: true }],
        respondidas: 1,
      },
    });
    expect(confira.get('[data-balao="cliente"]').text()).toContain('Cliente:');
    expect(confira.find('[data-aviso]').exists()).toBe(true);
    expect(confira.text()).toContain('Loja da Ana');

    const falha = mount(EtapaConfira, {
      props: { nome: 'Duda', mensagens: [respondido[0]], problema: 'falha' },
    });
    expect(falha.get('[data-erro-teste]').text()).toContain(
      'Isso não afeta seus clientes.'
    );

    const pronto = mount(EtapaPronto, {
      props: {
        nome: 'Duda',
        empresa: 'Loja da Ana',
        canal: 'WhatsApp',
        ultimo: { pergunta: 'Oi', resposta: 'Olá' },
      },
    });
    expect(pronto.get('[data-celular]').text()).toContain('Loja da Ana');
    expect(pronto.get('[data-celular]').text()).toContain('Cliente:');
  });

  it('the customer agent keeps "atender" and "Atendido por" as before', () => {
    const conte = mount(EtapaConte, {
      props: { falas: [], estadoDoMaterial: () => 'lendo' },
    });
    expect(conte.get('[data-intro]').text()).toBe(
      'Vou te fazer umas perguntas curtas. O agente só começa a atender quando você mandar.'
    );
    const confira = mount(EtapaConfira, {
      props: { nome: 'Duda', mensagens: respondido },
    });
    expect(confira.text()).toContain('Atendido por Duda');
    expect(confira.text()).not.toContain('ajuda da equipe');
    const pronto = mount(EtapaPronto, {
      props: {
        nome: 'Duda',
        canal: 'WhatsApp',
        ultimo: { pergunta: 'Oi', resposta: 'Olá' },
      },
    });
    expect(pronto.get('[data-celular]').text()).toContain('Atendido por Duda');
  });

  it('Comece: the drawer, the swap and the start button', async () => {
    const wrapper = mount(EtapaComece, {
      props: {
        nome: 'Duda',
        agenteId: 5,
        ondeInicial: 11,
        canais: [
          {
            inbox_id: 11,
            name: 'WhatsApp do Centro',
            occupied_by: { kind: 'agent', agent_id: 9, agent_name: 'Bia' },
          },
        ],
      },
      attachTo: document.body,
    });
    const texto = document.body.textContent;
    expect(texto).toContain('Onde e quando Duda atende');
    expect(texto).toContain('Trocar e começar a atender');
    expect(texto).toContain(
      'Bia para de responder no WhatsApp do Centro, mas continua na sua lista.'
    );
    expect(texto).toContain('Voltar ao teste');
    semProibidas(texto);
    wrapper.unmount();
  });
});
