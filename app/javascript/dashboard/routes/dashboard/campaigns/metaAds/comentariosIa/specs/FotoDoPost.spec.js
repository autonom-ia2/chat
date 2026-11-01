import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/metaAdsComentariosIa.json';
import en from 'dashboard/i18n/locale/en/metaAdsComentariosIa.json';
import FotoDoPost from '../FotoDoPost.vue';

// #2454: "O que eu vi na foto" no passo 1 do "Cuidar dos comentários". A leitura é pedida ao abrir (depois do clique),
// o dono corrige, e a correção é guardada no servidor. Dados sintéticos.
const pendente = () => {
  let resolver;
  const promessa = new Promise(resolve => {
    resolver = resolve;
  });
  return [promessa, valor => resolver(valor)];
};

const montadas = [];
const montar = ({ read, fix, locale = 'pt_BR' } = {}) => {
  const wrapper = mount(FotoDoPost, {
    props: {
      read: read || vi.fn().mockResolvedValue(null),
      fix: fix || vi.fn().mockResolvedValue(null),
    },
    global: {
      plugins: [
        createI18n({ legacy: false, locale, messages: { pt_BR: ptBR, en } }),
      ],
    },
  });
  montadas.push(wrapper);
  return wrapper;
};
const bloco = wrapper => wrapper.find('[data-ia-foto]');
const lida = (extra = {}) => ({
  status: 'ready',
  text: 'Um bolo de cenoura com cobertura de chocolate.',
  corrected: false,
  ...extra,
});

describe('FotoDoPost (#2454)', () => {
  afterEach(() => {
    montadas.splice(0).forEach(wrapper => wrapper.unmount());
  });

  it('lendo: "Olhando a foto…", e pede a leitura uma vez ao abrir', async () => {
    const [promessa] = pendente();
    const read = vi.fn().mockReturnValue(promessa);
    const wrapper = montar({ read });
    await flushPromises();

    expect(bloco(wrapper).attributes('data-estado')).toBe('lendo');
    expect(bloco(wrapper).text()).toContain('Olhando a foto…');
    expect(read).toHaveBeenCalledTimes(1);
  });

  it('pronto: "O que eu vi na foto:" com o texto e o botão Corrigir', async () => {
    const wrapper = montar({ read: vi.fn().mockResolvedValue(lida()) });
    await flushPromises();

    expect(bloco(wrapper).attributes('data-estado')).toBe('pronto');
    expect(bloco(wrapper).text()).toContain('O que eu vi na foto:');
    expect(bloco(wrapper).text()).toContain(
      'Um bolo de cenoura com cobertura de chocolate.'
    );
    expect(wrapper.find('[data-ia-foto-corrigir]').text()).toBe('Corrigir');
  });

  it.each([
    ['o servidor não conseguiu ver', { status: 'unavailable' }],
    ['a ida caiu', null],
  ])(
    'falha (%s): "Não consegui ver a foto agora.", com Escrever',
    async (_motivo, resposta) => {
      const wrapper = montar({ read: vi.fn().mockResolvedValue(resposta) });
      await flushPromises();

      expect(bloco(wrapper).attributes('data-estado')).toBe('falhou');
      expect(bloco(wrapper).text()).toContain('Não consegui ver a foto agora.');
      expect(wrapper.find('[data-ia-foto-corrigir]').text()).toBe('Escrever');
    }
  );

  it('sem foto no post: o bloco não aparece', async () => {
    const wrapper = montar({
      read: vi.fn().mockResolvedValue({ status: 'no_image' }),
    });
    await flushPromises();

    expect(bloco(wrapper).exists()).toBe(false);
  });

  it('Corrigir abre o campo com o texto; Guardar grava e mostra o novo texto', async () => {
    const fix = vi
      .fn()
      .mockResolvedValue(
        lida({ text: 'Bolo de cenoura de vó', corrected: true })
      );
    const wrapper = montar({ read: vi.fn().mockResolvedValue(lida()), fix });
    await flushPromises();

    await wrapper.find('[data-ia-foto-corrigir]').trigger('click');
    const campo = wrapper.find('[data-ia-foto-campo]');
    expect(campo.element.value).toBe(
      'Um bolo de cenoura com cobertura de chocolate.'
    );
    await campo.setValue('  Bolo de cenoura de vó ');
    await wrapper.find('[data-ia-foto-guardar]').trigger('click');
    await flushPromises();

    expect(fix).toHaveBeenCalledWith('Bolo de cenoura de vó');
    expect(wrapper.find('[data-ia-foto-campo]').exists()).toBe(false);
    expect(bloco(wrapper).text()).toContain('Bolo de cenoura de vó');
  });

  it('Guardar que falha: o campo fica, com o aviso', async () => {
    const wrapper = montar({
      read: vi.fn().mockResolvedValue(lida()),
      fix: vi.fn().mockResolvedValue(null),
    });
    await flushPromises();
    await wrapper.find('[data-ia-foto-corrigir]').trigger('click');
    await wrapper.find('[data-ia-foto-campo]').setValue('Outro texto');
    await wrapper.find('[data-ia-foto-guardar]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-ia-foto-campo]').exists()).toBe(true);
    expect(wrapper.find('[data-ia-foto-erro]').text()).toBe(
      'Não consegui guardar agora. Tente de novo.'
    );
  });

  it('Cancelar fecha o campo sem gravar', async () => {
    const fix = vi.fn();
    const wrapper = montar({ read: vi.fn().mockResolvedValue(lida()), fix });
    await flushPromises();
    await wrapper.find('[data-ia-foto-corrigir]').trigger('click');
    await wrapper.find('[data-ia-foto-cancelar]').trigger('click');

    expect(wrapper.find('[data-ia-foto-campo]').exists()).toBe(false);
    expect(fix).not.toHaveBeenCalled();
  });

  it('texto vazio não guarda', async () => {
    const wrapper = montar({ read: vi.fn().mockResolvedValue(lida()) });
    await flushPromises();
    await wrapper.find('[data-ia-foto-corrigir]').trigger('click');
    await wrapper.find('[data-ia-foto-campo]').setValue('   ');

    expect(wrapper.find('[data-ia-foto-guardar]').element.disabled).toBe(true);
  });

  it('em inglês também', async () => {
    const wrapper = montar({
      read: vi.fn().mockResolvedValue(lida()),
      locale: 'en',
    });
    await flushPromises();

    expect(bloco(wrapper).text()).toContain('What I saw in the photo:');
  });
});
