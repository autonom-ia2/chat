// #1619 — horário do canal (flag horario_unico_caixa): sem campo de fuso, horas em 24 h pelo
// ChoiceSelect, aviso de que a IA e o SLA seguem este horário no fuso da conta, e o salvamento pela
// mesma API de hoje, sem `timezone`.
import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { withFullI18n } from 'test-i18n';
import HorarioDoCanal from '../HorarioDoCanal.vue';
import {
  diasDaCaixa,
  opcoesDeFechar,
  paraWorkingHours,
} from '../horarioDoCanal';

withFullI18n('pt_BR');
// jsdom não rola: o ChoiceSelect chama scrollIntoView na opção ativa.
Element.prototype.scrollIntoView = () => {};

const alerta = vi.hoisted(() => vi.fn());
vi.mock('dashboard/composables', () => ({ useAlert: alerta }));

const linha = (dia, abre, fecha) => ({
  day_of_week: dia,
  closed_all_day: false,
  open_all_day: false,
  open_hour: Math.floor(abre / 60),
  open_minutes: abre % 60,
  close_hour: Math.floor(fecha / 60),
  close_minutes: fecha % 60,
});

const CAIXA = {
  id: 5,
  name: 'WhatsApp Vendas',
  channel_type: 'Channel::Whatsapp',
  working_hours_enabled: true,
  out_of_office_message: 'Voltamos às 9h.',
  // Com a flag, o servidor já devolve o fuso efetivo da caixa (o da conta, ou o padrão do CRM).
  timezone: 'America/Sao_Paulo',
  working_hours: [
    { day_of_week: 0, closed_all_day: true },
    ...[1, 2, 3, 4, 5].map(d => linha(d, 540, 1080)),
    { day_of_week: 6, closed_all_day: true },
  ],
};

const montar = ({ inbox = CAIXA, papel = 'administrator' } = {}) => {
  const dispatch = vi.fn().mockResolvedValue();
  const store = createStore({
    getters: {
      getCurrentAccountId: () => 1,
      getCurrentRole: () => papel,
      getCurrentUser: () => ({ id: 1, accounts: [] }),
      getCurrentCustomRoleId: () => null,
      'accounts/isFeatureEnabledonAccount': () => () => true,
      'accounts/getAccount': () => () => ({
        id: 1,
        // Diferente do da caixa: a tela mostra o que o servidor devolve na caixa.
        custom_attributes: { timezone: 'America/Cuiaba' },
      }),
      'inboxes/getUIFlags': () => ({ isUpdating: false }),
    },
  });
  store.dispatch = dispatch;
  const wrapper = mount(HorarioDoCanal, {
    props: { inbox },
    attachTo: document.body,
    global: {
      plugins: [store],
      stubs: {
        WootMessageEditor: { template: '<div data-editor />' },
        'router-link': {
          props: ['to'],
          template: '<a :data-to="to.name"><slot /></a>',
        },
      },
    },
  });
  return { wrapper, dispatch };
};

describe('HorarioDoCanal', () => {
  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('mostra o aviso com o fuso da conta e o atalho para mudar, sem campo de fuso', () => {
    const { wrapper } = montar();
    const aviso = wrapper.find('[data-aviso]').text();
    expect(aviso).toContain('Este é o horário do canal.');
    expect(aviso).toContain(
      'O agente de IA que atende "só no horário" e os prazos do SLA seguem este horário.'
    );
    expect(aviso).toContain(
      'As horas valem no fuso da conta: America/Sao Paulo.'
    );
    expect(aviso).not.toContain('Brasília');
    expect(wrapper.find('[data-mudar-fuso]').attributes('data-to')).toBe(
      'general_settings_index'
    );
    expect(wrapper.text()).not.toContain('Selecionar fuso horário');
    expect(wrapper.text()).not.toContain('Cuiaba');
  });

  it('caixa sem fuso: a frase sem o nome, nunca com espaço em branco', () => {
    const { wrapper } = montar({ inbox: { ...CAIXA, timezone: '' } });
    expect(wrapper.find('[data-aviso]').text()).toContain(
      'As horas valem no fuso da conta.'
    );
    expect(wrapper.find('[data-aviso]').text()).not.toContain('conta: ');
  });

  it('ligar o horário sem clicar em Salvar não grava nada', async () => {
    const { wrapper, dispatch } = montar({
      inbox: { ...CAIXA, working_hours_enabled: false, working_hours: [] },
    });
    await wrapper.find('[role="switch"]').trigger('click');
    await flushPromises();
    // A sugestão seg. a sex., 09:00 às 18:00 aparece, mas só vai ao servidor no Salvar.
    expect(wrapper.findAll('[data-total]')).toHaveLength(5);
    expect(dispatch).not.toHaveBeenCalled();
  });

  it('esconde o atalho do fuso de quem não é administrador', () => {
    const { wrapper } = montar({ papel: 'agent' });
    expect(wrapper.find('[data-mudar-fuso]').exists()).toBe(false);
  });

  it('usa o ChoiceSelect em 24 h e nenhum <select> nativo', () => {
    const { wrapper } = montar();
    expect(wrapper.find('select').exists()).toBe(false);
    const escolhas = wrapper.findAll('[role="combobox"]');
    // Seg. a sex.: abre e fecha.
    expect(escolhas).toHaveLength(10);
    expect(escolhas[0].text()).toBe('09:00');
    expect(escolhas[1].text()).toBe('18:00');
    expect(wrapper.text()).not.toContain('AM');
    expect(wrapper.findAll('[data-dia]')).toHaveLength(7);
    expect(wrapper.text()).toContain('Domingo');
    expect(wrapper.text()).toContain('Fechado');
    expect(wrapper.findAll('[data-total]')[0].text()).toBe('9h');
  });

  it('sem horário ligado explica o que acontece e esconde os dias', () => {
    const { wrapper } = montar({
      inbox: { ...CAIXA, working_hours_enabled: false },
    });
    expect(wrapper.find('[data-sem-horario]').text()).toBe(
      'Sem horário, o agente de IA deste canal atende a qualquer hora e o prazo do SLA conta o tempo corrido.'
    );
    expect(wrapper.find('[data-aviso]').exists()).toBe(false);
    expect(wrapper.find('[data-dia]').exists()).toBe(false);
  });

  it('escolher a hora pela lista muda o total e salva sem mandar o fuso', async () => {
    const { wrapper, dispatch } = montar();
    const fecha = wrapper.findAll('[role="combobox"]')[1];
    await fecha.trigger('click');
    const lista = wrapper.find(`[id="${fecha.attributes('aria-controls')}"]`);
    const opcao = lista
      .findAll('[role="option"]')
      .find(item => item.text() === '17:30');
    await opcao.trigger('click');
    expect(wrapper.findAll('[data-total]')[0].text()).toBe('8h 30min');

    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledTimes(1);
    const [acao, dados] = dispatch.mock.calls[0];
    expect(acao).toBe('inboxes/updateInbox');
    expect(dados).not.toHaveProperty('timezone');
    expect(dados).toMatchObject({
      id: 5,
      formData: false,
      working_hours_enabled: true,
      out_of_office_message: 'Voltamos às 9h.',
    });
    expect(dados.working_hours[1]).toEqual({
      day_of_week: 1,
      closed_all_day: false,
      open_all_day: false,
      open_hour: 9,
      open_minutes: 0,
      close_hour: 17,
      close_minutes: 30,
    });
    expect(dados.working_hours[0].closed_all_day).toBe(true);
    expect(alerta).toHaveBeenCalledWith(
      'Horário salvo. O agente de IA e o SLA já seguem este horário.'
    );
  });

  it('fechar antes de abrir mostra o erro e trava o salvar', async () => {
    const inbox = {
      ...CAIXA,
      working_hours: [linha(1, 600, 540)],
    };
    const { wrapper, dispatch } = montar({ inbox });
    expect(wrapper.find('[data-erro]').text()).toBe(
      'A hora de fechar precisa ser depois da hora de abrir.'
    );
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(dispatch).not.toHaveBeenCalled();
  });
});

describe('horarioDoCanal (conversão)', () => {
  it('caixa sem linhas começa seg. a sex., 09:00 às 18:00', () => {
    const dias = diasDaCaixa({ working_hours: [] });
    expect(dias.filter(dia => dia.ligado).map(dia => dia.dia)).toEqual([
      1, 2, 3, 4, 5,
    ]);
    expect(dias[1]).toMatchObject({ abre: '09:00', fecha: '18:00' });
  });

  it('o dia todo vai como 00:00–23:59 e hora fora do passo continua na lista', () => {
    const [dia] = paraWorkingHours([
      { dia: 2, ligado: true, diaTodo: true, abre: '09:00', fecha: '18:00' },
    ]);
    expect(dia).toMatchObject({
      open_all_day: true,
      close_hour: 23,
      close_minutes: 59,
    });
    const fechar = opcoesDeFechar('17:45').map(opcao => opcao.value);
    expect(fechar).toContain('17:45');
    expect(fechar.at(-1)).toBe('23:59');
    expect(fechar[0]).toBe('00:30');
  });
});
