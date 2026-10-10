import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import EtapaPronto from '../../components/criar/EtapaPronto.vue';

withFullI18n('pt_BR');

const montar = props =>
  mount(EtapaPronto, {
    props: {
      nome: 'Duda',
      canal: 'WhatsApp da Loja',
      ultimo: { pergunta: 'Vocês abrem no sábado?', resposta: 'Abrimos sim.' },
      ...props,
    },
  });

describe('EtapaPronto', () => {
  it('celebrates where the agent answers now, with every step done', () => {
    const wrapper = montar();
    expect(wrapper.get('h1').text()).toBe(
      'Duda já está atendendo no WhatsApp da Loja'
    );
    expect(wrapper.get('[data-agora]').text()).toBe(
      'Quem mandar mensagem no WhatsApp da Loja agora fala com Duda.'
    );
    expect(wrapper.text()).toContain(
      'Quando não souber, Duda passa a conversa para a equipe.'
    );
    expect(wrapper.get('[data-compacto]').text()).toBe('Pronto');
  });

  it('says when it answers if not always', () => {
    expect(
      montar({ quando: 'business_hours' }).get('[data-agora]').text()
    ).toBe('Duda responde no WhatsApp da Loja só no horário de atendimento.');
    expect(
      montar({ quando: 'outside_business_hours' }).get('[data-agora]').text()
    ).toBe(
      'Duda responde no WhatsApp da Loja só fora do horário de atendimento.'
    );
  });

  it('tells who stopped answering after a swap', () => {
    expect(montar({ saiu: 'Bia' }).get('[data-saiu]').text()).toBe(
      'Bia parou de responder no WhatsApp da Loja.'
    );
    expect(montar().find('[data-saiu]').exists()).toBe(false);
  });

  it('repeats the last test answer in the phone, when there was one', () => {
    expect(montar().get('[data-celular]').text()).toContain('Abrimos sim.');
    expect(montar({ ultimo: null }).find('[data-celular]').exists()).toBe(
      false
    );
  });

  it('opens the agent page or goes back to the list', async () => {
    const wrapper = montar();
    expect(wrapper.get('[data-ver]').text()).toBe('Ver Duda');
    await wrapper.get('[data-ver]').trigger('click');
    await wrapper.get('[data-voltar]').trigger('click');
    expect(wrapper.emitted('ver')).toHaveLength(1);
    expect(wrapper.emitted('voltar')).toHaveLength(1);
  });

  it('pins the actions to the bottom on the phone', () => {
    const acoes = montar({ celular: true }).get('[data-acoes]');
    expect(acoes.classes()).toContain('fixed');
    expect(acoes.get('[data-ver]').classes()).toContain('min-h-14');
  });

  it('has one navy moment only', () => {
    expect(montar().findAll('[data-heroi]')).toHaveLength(1);
  });

  it('never says "Ligar"', () => {
    expect(montar().text()).not.toContain('Ligar');
  });
});
