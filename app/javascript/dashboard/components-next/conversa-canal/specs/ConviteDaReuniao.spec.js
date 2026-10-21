import { mount, flushPromises } from '@vue/test-utils';
import ConviteDaReuniao from '../email/ConviteDaReuniao.vue';
import { diaDoConvite } from '../email/conviteDaReuniao';
import ConversaCanalAPI from 'dashboard/api/conversaCanal';

// #1984 — o cartão do convite: só a caixa convidada responde, a resposta vai ao
// servidor e a recusa dele aparece na tela.
vi.mock('dashboard/api/conversaCanal', () => ({
  default: { responderConvite: vi.fn() },
}));
vi.mock('dashboard/composables/store', async () => {
  const { ref } = await import('vue');
  return { useMapGetter: () => ref(1) };
});

// Sempre no futuro: o cartão de reunião que já terminou não pergunta nada.
const DAQUI_A_DOIS_DIAS = Math.floor(Date.now() / 1000) + 2 * 86400;

const convite = (extra = {}) => ({
  uid: 'uid-1@google.com',
  metodo: 'REQUEST',
  titulo: 'Alinhamento',
  inicio: DAQUI_A_DOIS_DIAS,
  fim: DAQUI_A_DOIS_DIAS + 3600,
  link: 'https://meet.google.com/abc-defg-hij',
  organizador: { nome: 'Diana', email: 'diana@agencia.example' },
  convidados: [
    { nome: 'Diana', email: 'diana@agencia.example' },
    { email: 'vendas@empresa.example' },
  ],
  ...extra,
});

const montar = (props = {}) =>
  mount(ConviteDaReuniao, {
    props: {
      convite: convite(),
      mensagemId: 7,
      conversationId: 3,
      caixa: { email: 'vendas@empresa.example' },
      fuso: 'America/Sao_Paulo',
      ...props,
    },
    global: {
      stubs: {
        Icon: true,
        Avatar: true,
        Spinner: true,
        RouterLink: { props: ['to'], template: '<a :href="to"><slot /></a>' },
      },
    },
  });

describe('ConviteDaReuniao (#1984)', () => {
  it('a caixa convidada responde e o cartão mostra a resposta', async () => {
    ConversaCanalAPI.responderConvite.mockResolvedValue({
      data: { id: 7, convite: { minha_resposta: 'talvez' } },
    });
    const cartao = montar();

    await cartao.get('[data-responder="talvez"]').trigger('click');
    await flushPromises();

    expect(ConversaCanalAPI.responderConvite).toHaveBeenCalledWith(
      3,
      7,
      'talvez'
    );
    expect(cartao.find('[data-convite-respondido]').exists()).toBe(true);
    expect(cartao.find('[data-responder]').exists()).toBe(false);
  });

  it('caixa em cópia só vê as informações', () => {
    const cartao = montar({ caixa: { email: 'outra@empresa.example' } });

    expect(cartao.find('[data-convite-so-informativo]').exists()).toBe(true);
    expect(cartao.find('[data-responder]').exists()).toBe(false);
  });

  it('convidada pelo endereço da agenda ligada, sem diferença de maiúscula', () => {
    const cartao = montar({
      convite: convite({ convidados: [{ email: 'Agenda@Empresa.example' }] }),
      caixa: {
        email: 'vendas@empresa.example',
        calendar_identity: 'agenda@empresa.example',
      },
    });

    expect(cartao.findAll('[data-responder]')).toHaveLength(3);
  });

  it('convite cancelado não pergunta nada', () => {
    const cartao = montar({ convite: convite({ metodo: 'CANCEL' }) });

    expect(cartao.find('[data-responder]').exists()).toBe(false);
    expect(cartao.find('[data-convite-so-informativo]').exists()).toBe(false);
  });

  it('a recusa do servidor aparece e a pergunta continua', async () => {
    ConversaCanalAPI.responderConvite.mockRejectedValue({
      response: { data: { error: 'Esta caixa não envia e-mail.' } },
    });
    const cartao = montar();

    await cartao.get('[data-responder="aceito"]').trigger('click');
    await flushPromises();

    expect(cartao.get('[role="alert"]').text()).toBe(
      'Esta caixa não envia e-mail.'
    );
    expect(cartao.findAll('[data-responder]')).toHaveLength(3);
  });

  it('reunião que já terminou não pergunta nada', () => {
    const ontem = Math.floor(Date.now() / 1000) - 86400;
    const cartao = montar({
      convite: convite({ inicio: ontem - 3600, fim: ontem }),
    });

    expect(cartao.find('[data-convite-passou]').exists()).toBe(true);
    expect(cartao.find('[data-responder]').exists()).toBe(false);
  });

  it('série que já começou continua respondível', () => {
    const ontem = Math.floor(Date.now() / 1000) - 86400;
    const cartao = montar({
      convite: convite({ inicio: ontem - 3600, fim: ontem, recorrente: true }),
    });

    expect(cartao.findAll('[data-responder]')).toHaveLength(3);
    expect(cartao.find('[data-convite-recorrente]').exists()).toBe(true);
  });

  it('série que já acabou não pergunta nada (#1995)', () => {
    const ontem = Math.floor(Date.now() / 1000) - 86400;
    const cartao = montar({
      convite: convite({
        inicio: ontem - 30 * 86400,
        fim: ontem - 30 * 86400 + 3600,
        recorrente: true,
        fimDaSerie: ontem,
      }),
    });

    expect(cartao.find('[data-convite-passou]').exists()).toBe(true);
    expect(cartao.find('[data-responder]').exists()).toBe(false);
  });

  it('convite mudado num e-mail mais novo avisa e não pergunta (#1995)', () => {
    const cartao = montar({
      convite: convite({ substituidoPor: 99, minhaResposta: 'aceito' }),
    });

    expect(cartao.get('[data-convite-substituido]').text()).toContain(
      'CONVERSA_CANAL.EMAIL.CONVITE.SUBSTITUIDO'
    );
    expect(cartao.find('[data-responder]').exists()).toBe(false);
    expect(cartao.find('[data-convite-respondido]').exists()).toBe(false);
  });

  it('convite cancelado num e-mail mais novo diz que foi cancelado e some o "Entrar" (#1995)', () => {
    const cartao = montar({
      convite: convite({ substituidoPor: 99, substituidoCancelado: true }),
    });

    expect(cartao.get('[data-convite-substituido]').text()).toContain(
      'CONVERSA_CANAL.EMAIL.CONVITE.CANCELADA_DEPOIS'
    );
    expect(cartao.find('[data-entrar-na-reuniao]').exists()).toBe(false);
  });

  it('a versão nova em outra conversa ganha o link; na mesma, não (#1995)', () => {
    const fora = montar({
      convite: convite({ substituidoPor: 99, substituidoNaConversa: 40 }),
    });
    expect(fora.get('[data-convite-novo]').attributes('href')).toBe(
      '/app/accounts/1/conversations/40'
    );

    const aqui = montar({
      convite: convite({ substituidoPor: 99, substituidoNaConversa: 3 }),
    });
    expect(aqui.find('[data-convite-novo]').exists()).toBe(false);
  });

  it('o cancelamento desfeito por um convite novo não aparece como cancelado (#1995)', () => {
    const cartao = montar({
      convite: convite({ metodo: 'CANCEL', substituidoPor: 99 }),
    });

    expect(cartao.find('[data-convite-substituido]').exists()).toBe(true);
    expect(cartao.text()).not.toContain(
      'CONVERSA_CANAL.EMAIL.CONVITE.CANCELADA_TEXTO'
    );
  });

  it('quem só lê vê o convite sem os botões', () => {
    const cartao = montar({ podeOperar: false });

    expect(cartao.find('[data-responder]').exists()).toBe(false);
    expect(cartao.find('[data-convite-so-informativo]').exists()).toBe(false);
  });

  it('quem só lê vê a resposta dada, sem "Mudar resposta"', () => {
    const cartao = montar({
      podeOperar: false,
      convite: convite({ minhaResposta: 'aceito' }),
    });

    expect(cartao.find('[data-convite-respondido]').exists()).toBe(true);
    expect(cartao.find('[data-convite-respondido] button').exists()).toBe(
      false
    );
  });

  it('dia inteiro mostra o dia certo, sem horário nem duração', () => {
    const cartao = montar({
      convite: convite({
        diaInteiro: true,
        inicio: Date.UTC(2030, 10, 5, 12) / 1000,
        fim: Date.UTC(2030, 10, 6, 12) / 1000,
      }),
      fuso: 'Pacific/Kiritimati',
    });

    expect(cartao.text()).toContain('CONVERSA_CANAL.EMAIL.CONVITE.DIA_INTEIRO');
    expect(cartao.text()).not.toContain('(');
    // Em Kiritimati (UTC+14) o meio-dia UTC já é o dia 6: a data tem de seguir o dia 5.
    expect(cartao.text()).toContain('5');
    expect(cartao.text()).not.toContain('6');
  });

  it('avisa quando o convite não diz o fuso', () => {
    const cartao = montar({ convite: convite({ fusoIncerto: true }) });

    expect(cartao.find('[data-convite-sem-fuso]').exists()).toBe(true);
  });

  it('o organizador repetido entre os convidados aparece uma vez', () => {
    const cartao = montar();

    expect(cartao.findAllComponents({ name: 'Avatar' })).toHaveLength(2);
  });

  it('"Manter a resposta" desiste da troca', async () => {
    const cartao = montar({ convite: convite({ minhaResposta: 'aceito' }) });

    await cartao.get('[data-convite-respondido] button').trigger('click');
    expect(cartao.findAll('[data-responder]')).toHaveLength(3);
    await cartao.get('[data-manter-resposta]').trigger('click');

    expect(cartao.find('[data-convite-respondido]').exists()).toBe(true);
  });

  it('dia inteiro de amanhã, às 22h no fuso da conta, é "Amanhã"', () => {
    // 21/10 22:00 em São Paulo já é 22/10 em UTC; o evento de dia inteiro é 22/10.
    const agora = Date.UTC(2030, 9, 22, 1) / 1000;
    const inicio = Date.UTC(2030, 9, 22, 12) / 1000;

    expect(
      diaDoConvite({
        inicio,
        agora,
        fuso: 'America/Sao_Paulo',
        fusoDoInicio: 'UTC',
        t: chave => chave,
      })
    ).toBe('CONVERSA_CANAL.EMAIL.CONVITE.AMANHA');
  });

  it('convite sem organizador válido diz o motivo certo', () => {
    const cartao = montar({ convite: convite({ organizador: { nome: 'X' } }) });

    expect(cartao.get('[data-convite-so-informativo]').text()).toContain(
      'CONVERSA_CANAL.EMAIL.CONVITE.SEM_ORGANIZADOR'
    );
  });

  it('a resposta de outro atendente chega pela mensagem atualizada', async () => {
    const cartao = montar();
    expect(cartao.find('[data-convite-respondido]').exists()).toBe(false);

    await cartao.setProps({ convite: convite({ minhaResposta: 'aceito' }) });

    expect(cartao.find('[data-convite-respondido]').exists()).toBe(true);
  });
});
