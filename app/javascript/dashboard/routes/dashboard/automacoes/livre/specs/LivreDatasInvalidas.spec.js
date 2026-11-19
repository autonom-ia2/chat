import { mount } from '@vue/test-utils';
import LivreDatasInvalidas from '../components/LivreDatasInvalidas.vue';

// #2556 — o editor avisa quantos contatos ou cards o gatilho de data deixou
// de fora pela data escrita em outro formato, com o nome do campo da tela.
// Sem contagem, não aparece nada.
const t = vi.hoisted(() =>
  vi.fn((chave, { n, campo }, quantos) => `${chave}|${n}|${campo}|${quantos}`)
);
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t }) }));

const montar = aviso =>
  mount(LivreDatasInvalidas, { props: aviso === undefined ? {} : { aviso } });

describe('o aviso das datas que ficaram de fora', () => {
  it.each([
    ['contato', 'CONTATOS'],
    ['card', 'CARDS'],
  ])('%s: diz quantos e o nome do campo', (alvo, chave) => {
    const wrapper = montar({ quantos: 12, alvo, campo: 'Aniversário' });

    expect(wrapper.find('[data-datas-invalidas]').text()).toBe(
      `AUTOMACAO_LIVRE.EDITOR.DATAS_INVALIDAS.${chave}|12|Aniversário|12`
    );
  });

  it.each([
    ['sem aviso', undefined],
    ['aviso vazio', null],
    ['contagem zero', { quantos: 0, alvo: 'contato', campo: 'Aniversário' }],
  ])('%s: não mostra nada', (_caso, aviso) => {
    expect(montar(aviso).find('[data-datas-invalidas]').exists()).toBe(false);
  });
});
