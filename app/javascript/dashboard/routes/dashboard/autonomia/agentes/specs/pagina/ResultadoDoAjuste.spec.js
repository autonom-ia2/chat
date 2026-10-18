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
      'Também mudei, sem você pedir: Saudação nova. Se não quiser, é só me dizer o que tirar.'
    );
    expect(wrapper.find('[data-conferido]').classes()).toContain(
      'bg-n-amber-2'
    );
  });

  it('never says Pronto in green with zero requests', () => {
    const wrapper = montar({
      itens: [{ estado: 'sem_pedido', texto: 'Saudação nova' }],
    });

    expect(wrapper.text()).not.toContain('Pronto');
    expect(wrapper.find('[data-conferido]').classes()).not.toContain(
      'bg-n-teal-2'
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
  // #1428 (entrega B) — as perguntas de prova, como no protótipo aprovado: "Testando…", depois ✓ ou ⚠
  // com a lista que abre e fecha; indisponível é uma linha neutra, nunca ✓.
  describe('proof questions', () => {
    const PRONTA = {
      status: 'pronta',
      ok: 2,
      total: 2,
      perguntas: [
        {
          pergunta: 'Quanto custa?',
          resposta: 'Passo para a equipe.',
          equipe: false,
        },
        { pergunta: 'Tem vida?', resposta: null, equipe: true },
      ],
    };

    it('shows the testing line while pending', () => {
      const prova = montar({ prova: { status: 'pendente', total: 3 } }).find(
        '[data-prova]'
      );

      expect(prova.text()).toBe('Testando com 3 perguntas de prova…');
      expect(prova.find('.i-lucide-circle-check').exists()).toBe(false);
    });

    it('shows the score with a check, and the list only when opened', async () => {
      const wrapper = montar({ prova: PRONTA });
      const prova = wrapper.find('[data-prova]');

      expect(prova.text()).toContain('2 de 2 perguntas de prova ok');
      expect(prova.find('.i-lucide-circle-check').exists()).toBe(true);
      expect(prova.findAll('li')).toHaveLength(0);

      await wrapper.find('[data-ver-prova]').trigger('click');

      const linhas = prova.findAll('li').map(linha => linha.text());
      expect(linhas).toEqual([
        'Cliente: Quanto custa?Bia: Passo para a equipe.',
        'Cliente: Tem vida?Bia: Passaria a conversa para a equipe.',
      ]);
      expect(wrapper.find('[data-ver-prova]').text()).toBe(
        'Esconder as perguntas'
      );
      expect(wrapper.find('[data-ver-prova]').attributes('aria-expanded')).toBe(
        'true'
      );
    });

    it('warns when some answer missed the change', () => {
      const prova = montar({ prova: { ...PRONTA, ok: 1 } }).find(
        '[data-prova]'
      );

      expect(prova.text()).toContain('1 de 2 perguntas de prova ok');
      expect(prova.find('.i-lucide-triangle-alert').exists()).toBe(true);
      expect(prova.find('.i-lucide-circle-check').exists()).toBe(false);
    });

    it('no check when no question touched the change (only those count)', async () => {
      const wrapper = montar({ prova: { ...PRONTA, ok: 0, total: 0 } });
      const prova = wrapper.find('[data-prova]');

      expect(prova.find('[data-sem-teste]').text()).toBe(
        'As perguntas não testaram a mudança.'
      );
      expect(prova.text()).not.toContain('perguntas de prova ok');
      expect(prova.find('.i-lucide-circle-check').exists()).toBe(false);
      expect(prova.find('.i-lucide-triangle-alert').exists()).toBe(false);
      await wrapper.find('[data-ver-prova]').trigger('click');
      expect(prova.findAll('li')).toHaveLength(2);
    });

    it('says it could not test on a neutral line, without a check', () => {
      const prova = montar({
        prova: { status: 'indisponivel', total: 3 },
      }).find('[data-prova]');

      expect(prova.text()).toBe(
        'Não consegui testar agora. Use o teste ao lado para ver como ficou.'
      );
      expect(prova.find('.i-lucide-circle-check').exists()).toBe(false);
      expect(prova.find('.i-lucide-triangle-alert').exists()).toBe(false);
    });

    it('no proof block without a proof, nor once undone', () => {
      expect(montar().find('[data-prova]').exists()).toBe(false);
      expect(
        montar({ desfeito: true, prova: PRONTA }).find('[data-prova]').exists()
      ).toBe(false);
    });
  });
});
