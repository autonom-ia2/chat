import { ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import JanelaDeEmojis from '../JanelaDeEmojis.vue';

// #1895 — a janela de emojis do painel, agora comum a todos os canais: com o painel
// em português, "coracao" (sem acento) acha o ❤️ pelo nome em português.
const idioma = vi.hoisted(() => ({ atual: 'pt_BR' }));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: chave => chave, locale: ref(idioma.atual) }),
}));

const montar = () =>
  mount(JanelaDeEmojis, {
    global: {
      stubs: { Icon: true, TeleportWithDirection: { template: '<slot />' } },
    },
  });

const emojisNaGrade = wrapper =>
  wrapper.findAll('[data-janela-de-emojis] .grid button').map(b => b.text());

describe('JanelaDeEmojis', () => {
  beforeEach(() => {
    idioma.atual = 'pt_BR';
  });

  it('em português, "coracao" acha o ❤️', async () => {
    const wrapper = montar();
    await wrapper.find('[data-buscar-emoji]').setValue('coracao');

    // Os nomes em português chegam por import() dinâmico, só no locale pt.
    await vi.waitFor(() => expect(emojisNaGrade(wrapper)).toContain('❤️'), {
      timeout: 5000,
    });
  });

  it('Enter escolhe o primeiro achado', async () => {
    idioma.atual = 'en';
    const wrapper = montar();
    await flushPromises();
    const campo = wrapper.find('[data-buscar-emoji]');
    await campo.setValue('heart');
    const [primeiro] = emojisNaGrade(wrapper);
    await campo.trigger('keydown.enter');

    expect(wrapper.emitted('escolher')).toEqual([[primeiro]]);
  });

  it('fora do português, "coracao" não acha nada', async () => {
    idioma.atual = 'en';
    const wrapper = montar();
    await flushPromises();
    await wrapper.find('[data-buscar-emoji]').setValue('coracao');

    expect(emojisNaGrade(wrapper)).toEqual([]);
    expect(wrapper.text()).toContain('CONVERSA_CANAL.EMAIL.EMOJIS.NADA');
  });
});
