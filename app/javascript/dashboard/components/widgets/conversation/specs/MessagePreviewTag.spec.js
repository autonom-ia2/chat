import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { withFullI18n } from 'test-i18n';
import MessagePreview from '../MessagePreview.vue';
import { gettersDaMontagem } from 'dashboard/components-next/message/specs/montarMensagem';

// #2202: a prévia é `div`, como sempre; o card da lista nova pede `span` (fica dentro de um <button>).
withFullI18n('pt_BR');
const loja = createStore({
  getters: { ...gettersDaMontagem, 'inboxes/getInbox': () => () => ({}) },
});
const montar = (extra = {}) =>
  mount(MessagePreview, {
    props: { message: { id: 1, content: 'Oi', message_type: 0 }, ...extra },
    global: { plugins: [loja], stubs: { FluentIcon: true } },
  });

describe('MessagePreview: tag (#2202)', () => {
  it('sem a prop, a raiz é div, como antes', () => {
    expect(montar().element.tagName).toBe('DIV');
  });

  it('com tag="span", a raiz é span, com o mesmo texto e as mesmas classes', () => {
    const div = montar();
    const span = montar({ tag: 'span' });
    expect(span.element.tagName).toBe('SPAN');
    expect(span.text()).toBe(div.text());
    expect(span.classes()).toEqual(div.classes());
  });
});
