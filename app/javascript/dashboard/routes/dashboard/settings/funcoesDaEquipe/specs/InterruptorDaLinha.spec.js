import { mount } from '@vue/test-utils';
import InterruptorDaLinha from '../guiada/InterruptorDaLinha.vue';
import { global } from './montar';

// #2308, especificação 9 e 14 › Acessibilidade: o nome do interruptor é o título; a descrição é só o que existe
// além dele, para o leitor não ler nada duas vezes.
const montar = props =>
  mount(InterruptorDaLinha, {
    props: { titulo: 'Apagar contatos', ...props },
    global: global(),
  });

const descritos = wrapper => {
  const interruptor = wrapper.find('[role="switch"]');
  const ids = (interruptor.attributes('aria-describedby') || '')
    .split(' ')
    .filter(Boolean);
  return ids.map(id => wrapper.find(`[id="${id}"]`).text());
};

describe('InterruptorDaLinha', () => {
  it('só com o título: nome sem descrição', () => {
    const wrapper = montar();
    const interruptor = wrapper.find('[role="switch"]');
    expect(interruptor.attributes('aria-label')).toBe('Apagar contatos');
    expect(interruptor.attributes('aria-describedby')).toBeUndefined();
  });

  it('a descrição aponta texto, nota e motivo, nessa ordem, e nunca o título', () => {
    const wrapper = montar({
      texto: 'Some da conta.',
      nota: 'Ao ligar, também mexe nos contatos.',
      trava: 'Vem com "Cuida de tudo nas vendas".',
      ligado: true,
    });
    expect(descritos(wrapper)).toEqual([
      'Some da conta.',
      'Ao ligar, também mexe nos contatos.',
      'Vem com "Cuida de tudo nas vendas".',
    ]);
    expect(wrapper.find('[role="switch"]').attributes('aria-disabled')).toBe(
      'true'
    );
  });

  it('travado desligado: sem interruptor, com o motivo à vista', () => {
    const wrapper = montar({ trava: 'Você não tem isto, então não pode dar.' });
    expect(wrapper.find('[role="switch"]').exists()).toBe(false);
    expect(wrapper.text()).toContain('Você não tem isto, então não pode dar.');
  });
});
