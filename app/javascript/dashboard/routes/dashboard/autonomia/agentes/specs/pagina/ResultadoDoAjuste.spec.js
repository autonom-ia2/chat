import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import ResultadoDoAjuste from '../../components/pagina/ResultadoDoAjuste.vue';

// #1428 (parte 3) — o resultado do ajuste pedido por pedido, com a cópia real em pt_BR: o que o dono
// não pediu fica à parte e não conta, sem conferência nunca há ✓, e o Desfazer some quando o agente
// mudou depois.
withFullI18n('pt_BR');

const RESULTADO = {
  itens: [
    { estado: 'aplicado', texto: 'Respostas curtas.' },
    { estado: 'nao_aplicado', texto: 'preço com a equipe' },
    { estado: 'sem_pedido', texto: 'Saudação nova' },
  ],
  faltou_fora: false,
  conferido: true,
  desfeito: false,
  desfeito_sozinho: false,
  pode_desfazer: true,
};

const montar = (resultado = {}, props = {}) =>
  mount(ResultadoDoAjuste, {
    props: { resultado: { ...RESULTADO, ...resultado }, nome: 'Bia', ...props },
  });

describe('ResultadoDoAjuste', () => {
  it('counts only what the owner asked, and shows what he did not ask on a neutral line', () => {
    const wrapper = montar();

    expect(wrapper.text()).toContain('Mudei 1 de 2 pedidos em Bia.');
    expect(
      wrapper.findAll('[data-item]').map(item => item.attributes('data-item'))
    ).toEqual(['aplicado', 'nao_aplicado']);
    expect(wrapper.find('[data-item="nao_aplicado"]').text()).toBe(
      'Não consegui aplicar: “preço com a equipe”.'
    );
    expect(wrapper.find('[data-sem-pedido]').text()).toBe(
      'Também mudei, sem você pedir: Saudação nova.'
    );
    expect(wrapper.find('[data-conferido]').classes()).toContain(
      'bg-n-amber-2'
    );
  });

  it('says Pronto only when everything asked went in', () => {
    const wrapper = montar({
      itens: [
        { estado: 'aplicado', texto: 'Curto.' },
        { estado: 'aplicado', texto: 'Formal.' },
      ],
    });

    expect(wrapper.text()).toContain('Pronto. Mudei 2 coisas em Bia.');
    expect(wrapper.find('[data-conferido]').classes()).toContain('bg-n-teal-2');
  });

  it('does not say Pronto when part of the request was left out of the list', () => {
    const wrapper = montar({
      itens: [{ estado: 'aplicado', texto: 'Curto.' }],
      faltou_fora: true,
    });

    expect(wrapper.text()).toContain('Mudei 1 coisa em Bia.');
    expect(wrapper.text()).not.toContain('Pronto');
    expect(wrapper.find('[data-faltou-fora]').exists()).toBe(true);
  });

  it('without the check, the card is neutral and has no check marks', () => {
    const wrapper = montar({
      conferido: false,
      itens: [{ estado: 'aplicado', texto: 'Curto.' }],
    });

    expect(wrapper.text()).toContain('Mudei Bia, mas não consegui conferir.');
    expect(wrapper.find('[data-conferido]').attributes('data-tom')).toBe(
      'neutro'
    );
    expect(wrapper.find('.i-lucide-circle-check').exists()).toBe(false);
  });

  it('asks to undo and shows it working', async () => {
    const wrapper = montar();

    await wrapper.find('[data-desfazer]').trigger('click');
    expect(wrapper.emitted('desfazer')).toHaveLength(1);

    await wrapper.setProps({ desfazendo: true });
    expect(wrapper.find('[data-desfazer]').text()).toContain('Desfazendo…');
  });

  it('after a 409 tells the agent changed and hides the undo', () => {
    const wrapper = montar({}, { erro: 'mudou' });

    expect(wrapper.find('[data-desfazer]').exists()).toBe(false);
    expect(wrapper.find('[data-erro-desfazer]').text()).toContain(
      'Bia mudou depois desta conversa'
    );
  });

  it('keeps the undo after a generic failure', () => {
    const wrapper = montar({}, { erro: 'falhou' });

    expect(wrapper.find('[data-desfazer]').exists()).toBe(true);
    expect(wrapper.find('[data-erro-desfazer]').text()).toBe(
      'Não consegui desfazer agora. Tente de novo.'
    );
  });

  it('does not offer undo when the server says it is no longer possible', () => {
    expect(
      montar({ pode_desfazer: false }).find('[data-desfazer]').exists()
    ).toBe(false);
  });

  it('says undone, and says what the builder undid by itself', () => {
    expect(montar({ desfeito: true }).find('[data-desfeito]').text()).toBe(
      'Desfeito. Bia voltou a ser como antes.'
    );
    expect(
      montar({ desfeito_sozinho: true, itens: [] })
        .find('[data-desfeito]')
        .text()
    ).toBe('Desfiz o que você não tinha pedido. Bia continua como antes.');
  });
});
