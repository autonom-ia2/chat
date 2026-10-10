import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import EtapaConte from '../../components/criar/EtapaConte.vue';
import EtapaConfira from '../../components/criar/EtapaConfira.vue';
import EtapaComece from '../../components/criar/EtapaComece.vue';

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
    expect(vazio.get('[data-pergunte]').text()).toBe(
      'Faça uma pergunta para ver como Duda responde.'
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
      'Aqui Duda passaria a conversa para a equipe.'
    );
    expect(respondida.get('[data-depois]').text()).toBe(
      'Agora não, terminar depois'
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
