import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import AddLabel from '../AddLabel.vue';

// #2138 — fora do painel do contato, o "+ etiqueta" é o do Chatwoot (LabelBox,
// Configurações); a área de toque de 44 px e a lista presa a quem está em volta
// só valem com anchorMenuToParent.
const i18n = createI18n({
  legacy: false,
  locale: 'en',
  missingWarn: false,
  messages: { en: { LABEL: { TAG_BUTTON: 'tag' } } },
});
const CLASSES_DO_CHATWOOT =
  'flex items-center gap-1 px-2 py-1 rounded-md outline-dashed h-6 outline-1 outline-n-slate-6 hover:bg-n-alpha-2';

const montar = props =>
  mount(AddLabel, {
    props,
    global: {
      plugins: [i18n],
      directives: { onClickaway: {} },
      stubs: { DropdownMenu: true },
    },
  });

describe('AddLabel', () => {
  it('sem anchorMenuToParent: igual ao Chatwoot (raiz relative, botão sem pseudo-elemento)', () => {
    const wrapper = montar({});
    expect(wrapper.classes()).toEqual(['relative']);
    expect(wrapper.get('button').attributes('class')).toBe(CLASSES_DO_CHATWOOT);
  });

  it('com anchorMenuToParent: a raiz solta a lista e o botão ganha a área de toque', () => {
    const wrapper = montar({ anchorMenuToParent: true });
    expect(wrapper.classes()).not.toContain('relative');
    const classes = wrapper.get('button').classes();
    expect(classes).toEqual(
      expect.arrayContaining([
        'relative',
        'before:absolute',
        'before:inset-x-0',
        'before:-inset-y-2.5',
      ])
    );
  });
});
