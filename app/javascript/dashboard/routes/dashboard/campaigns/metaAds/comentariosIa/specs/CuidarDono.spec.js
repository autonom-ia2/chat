import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/metaAdsComentariosIa.json';
import en from 'dashboard/i18n/locale/en/metaAdsComentariosIa.json';
import CuidarDono from '../CuidarDono.vue';

// #2212: o jeito do dono em três passos. A mensagem do privado (até 1000 bytes UTF-8, sem nada no fim), para
// quem (até 500 letras), e como fica, com a Prévia do servidor. "Ligar" devolve { message, paraQuem, phrase }.
const painel = (extra = {}) => ({
  network: 'instagram',
  private_available: true,
  care: 'off',
  message: '',
  para_quem: '',
  phrases: ['Te mandei no privado!', 'Olha o privado!'],
  unanswered: 0,
  ...extra,
});

const montadas = [];
const i18nPtBR = () =>
  createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: ptBR } });
const montar = ({ data = painel(), preview, i18n, ...props } = {}) => {
  const wrapper = mount(CuidarDono, {
    props: {
      data,
      preview: preview || vi.fn().mockResolvedValue(null),
      ...props,
    },
    global: {
      plugins: [i18n || i18nPtBR()],
    },
  });
  montadas.push(wrapper);
  return wrapper;
};
const proximo = wrapper => wrapper.find('[data-ia-dono-next]');
const passo = wrapper =>
  wrapper.find('[data-ia-dono]').attributes('data-ia-dono-step');

describe('CuidarDono (#2212)', () => {
  afterEach(() => {
    montadas.splice(0).forEach(wrapper => wrapper.unmount());
  });

  it('passo 1: sem mensagem não continua; com ela, vai ao passo 2', async () => {
    const wrapper = montar();
    expect(passo(wrapper)).toBe('1');
    expect(proximo(wrapper).element.disabled).toBe(true);

    await wrapper
      .find('[data-ia-dono-message]')
      .setValue('Oi! O link: loja.com');
    expect(proximo(wrapper).element.disabled).toBe(false);
    await proximo(wrapper).trigger('click');

    expect(passo(wrapper)).toBe('2');
  });

  describe('passo 1 com o começo escrito pela IA (mockup aprovado)', () => {
    const pendente = () => {
      let resolver;
      const promessa = new Promise(resolve => {
        resolver = resolve;
      });
      return [promessa, valor => resolver(valor)];
    };

    it('o cuidado novo abre com o começo da IA e o texto "Escrevi um começo"', async () => {
      const draft = vi.fn().mockResolvedValue('Oi! O e-book sai por R$ 29.');
      const wrapper = montar({ draft });
      await flushPromises();

      expect(draft).toHaveBeenCalledTimes(1);
      expect(wrapper.find('[data-ia-dono-message]').element.value).toBe(
        'Oi! O e-book sai por R$ 29.'
      );
      expect(wrapper.find('[data-ia-dono-what-text]').text()).toContain(
        'Escrevi um começo com base no post'
      );
      expect(proximo(wrapper).element.disabled).toBe(false);
    });

    it('enquanto a IA escreve, avisa; sem começo, o campo fica vazio com o texto de sempre', async () => {
      const [promessa, resolver] = pendente();
      const wrapper = montar({ draft: () => promessa });
      await flushPromises();
      expect(wrapper.find('[data-ia-dono-writing]').exists()).toBe(true);

      resolver('');
      await flushPromises();

      expect(wrapper.find('[data-ia-dono-writing]').exists()).toBe(false);
      expect(wrapper.find('[data-ia-dono-message]').element.value).toBe('');
      expect(wrapper.find('[data-ia-dono-what-text]').text()).toContain(
        'Escreva a mensagem que a pessoa recebe'
      );
    });

    it('o que o dono digitou enquanto a IA escrevia não é trocado', async () => {
      const [promessa, resolver] = pendente();
      const wrapper = montar({ draft: () => promessa });
      await wrapper.find('[data-ia-dono-message]').setValue('A minha');

      resolver('Oi! Da IA.');
      await flushPromises();

      expect(wrapper.find('[data-ia-dono-message]').element.value).toBe(
        'A minha'
      );
    });

    it('cuidado já escrito ou mudando: não pede começo à IA', async () => {
      const draft = vi.fn().mockResolvedValue('Oi! Da IA.');
      montar({ draft, data: painel({ message: 'A do dono' }) });
      montar({ draft, changing: true });
      await flushPromises();

      expect(draft).not.toHaveBeenCalled();
    });
  });

  it('passo 1 não explica a frase automática: o dono só escreve a mensagem (pedido do Rodrigo no teste real)', () => {
    const wrapper = montar();
    expect(wrapper.text()).not.toContain('No fim');
    expect(wrapper.text()).not.toContain('mensagem automática');
  });

  it('o limite da mensagem é em bytes, como a Meta conta', async () => {
    const wrapper = montar();
    // 501 letras com acento: 1002 bytes, com menos de 1000 letras.
    await wrapper.find('[data-ia-dono-message]').setValue('é'.repeat(501));

    expect(wrapper.find('[data-ia-dono-too-long]').exists()).toBe(true);
    expect(proximo(wrapper).element.disabled).toBe(true);

    await wrapper.find('[data-ia-dono-message]').setValue('é'.repeat(500));
    expect(wrapper.find('[data-ia-dono-too-long]').exists()).toBe(false);
    expect(proximo(wrapper).element.disabled).toBe(false);
  });

  it('passo 2: o cuidado novo começa em "Quem perguntar o preço", como no mockup; vazio ou mais de 500 letras não continua', async () => {
    const wrapper = montar({ data: painel({ message: 'Oi!' }) });
    await proximo(wrapper).trigger('click');
    const atalhos = wrapper.findAll('[data-ia-dono-suggestion]');
    expect(wrapper.find('[data-ia-dono-who]').element.value).toBe(
      'Quem perguntar o preço'
    );
    expect(atalhos[0].attributes('aria-pressed')).toBe('true');
    expect(proximo(wrapper).element.disabled).toBe(false);

    await wrapper.find('[data-ia-dono-who]').setValue('  ');
    expect(proximo(wrapper).element.disabled).toBe(true);

    await atalhos[1].trigger('click');
    expect(wrapper.find('[data-ia-dono-who]').element.value).toBe(
      'Quem pedir o link'
    );
    expect(proximo(wrapper).element.disabled).toBe(false);

    await wrapper.find('[data-ia-dono-who]').setValue('a'.repeat(501));
    expect(wrapper.find('[data-ia-dono-who-too-long]').exists()).toBe(true);
    expect(proximo(wrapper).element.disabled).toBe(true);
  });

  it('passo 3: pede a prévia com o para quem e mostra quem recebe e quem não', async () => {
    const preview = vi.fn().mockResolvedValue({
      recebe: { author: 'carla', text: 'Qual o preço?', network: 'instagram' },
      nao: { author: 'joao', text: 'Lindo!', network: 'instagram' },
    });
    const wrapper = montar({
      data: painel({ message: 'Oi!', para_quem: 'Quem perguntar o preço' }),
      preview,
    });
    await proximo(wrapper).trigger('click');
    await proximo(wrapper).trigger('click');
    await flushPromises();

    expect(passo(wrapper)).toBe('3');
    expect(preview).toHaveBeenCalledWith('Quem perguntar o preço');
    expect(wrapper.find('[data-ia-dono-example="recebe"]').text()).toContain(
      '@carla'
    );
    // O balão é o privado inteiro: a mensagem do dono, sem nada no fim.
    expect(wrapper.find('[data-ia-dono-bubble]').text()).toBe('Oi!');
    expect(wrapper.find('[data-ia-dono-example="nao"]').text()).toContain(
      'Lindo!'
    );
  });

  it('prévia que falha: avisa e ainda deixa ligar', async () => {
    const wrapper = montar({
      data: painel({ message: 'Oi!', para_quem: 'Quem pedir o link' }),
    });
    await proximo(wrapper).trigger('click');
    await proximo(wrapper).trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-ia-dono-examples-failed]').exists()).toBe(true);
    expect(wrapper.find('[data-ia-dono-example="nao"]').exists()).toBe(false);
    expect(wrapper.find('[data-ia-dono-start]').element.disabled).toBe(false);
  });

  it('prévia sem resposta em 20 s: para de girar e cai no aviso de falha', async () => {
    vi.useFakeTimers();
    try {
      const wrapper = montar({
        data: painel({ message: 'Oi!', para_quem: 'Quem pedir o link' }),
        preview: vi.fn().mockReturnValue(new Promise(() => {})),
      });
      await proximo(wrapper).trigger('click');
      await proximo(wrapper).trigger('click');
      await flushPromises();
      expect(wrapper.find('[data-ia-dono-examples-loading]').exists()).toBe(
        true
      );

      await vi.advanceTimersByTimeAsync(20000);

      expect(wrapper.find('[data-ia-dono-examples-loading]').exists()).toBe(
        false
      );
      expect(wrapper.find('[data-ia-dono-examples-failed]').exists()).toBe(
        true
      );
    } finally {
      vi.useRealTimers();
    }
  });

  it('prévia velha que chega depois não cobre a nova', async () => {
    let velha;
    const preview = vi
      .fn()
      .mockReturnValueOnce(
        new Promise(resolve => {
          velha = resolve;
        })
      )
      .mockResolvedValueOnce({
        recebe: { author: 'nova', text: 'Tem link?', network: 'instagram' },
        nao: null,
      });
    const wrapper = montar({
      data: painel({ message: 'Oi!', para_quem: 'Quem pedir o preço' }),
      preview,
    });
    await proximo(wrapper).trigger('click');
    await proximo(wrapper).trigger('click');
    await wrapper.find('[data-ia-dono-previous]').trigger('click');
    await wrapper.find('[data-ia-dono-who]').setValue('Quem pedir o link');
    await proximo(wrapper).trigger('click');
    await flushPromises();
    velha({
      recebe: { author: 'velha', text: 'Quanto?', network: 'instagram' },
      nao: null,
    });
    await flushPromises();

    expect(preview).toHaveBeenLastCalledWith('Quem pedir o link');
    const recebe = wrapper.find('[data-ia-dono-example="recebe"]').text();
    expect(recebe).toContain('@nova');
    expect(recebe).not.toContain('@velha');
  });

  it('frase padrão acompanha o idioma que chega depois de abrir a tela, enquanto o dono não a troca', async () => {
    const i18n = createI18n({
      legacy: false,
      locale: 'en',
      messages: { en, pt_BR: ptBR },
    });
    const wrapper = montar({
      i18n,
      data: painel({ message: 'Oi!', para_quem: 'Quem pedir', phrases: [] }),
    });
    i18n.global.locale.value = 'pt_BR';
    await proximo(wrapper).trigger('click');
    await proximo(wrapper).trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-ia-dono-phrase]').text()).toBe(
      'Te chamei no privado 😊'
    );
  });

  it('cuidado novo (o servidor manda frases vazias): vem a frase padrão e dá para ligar', async () => {
    const wrapper = montar({
      data: painel({
        message: 'Oi!',
        para_quem: 'Quem pedir o link',
        phrases: [],
      }),
    });
    await proximo(wrapper).trigger('click');
    await proximo(wrapper).trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-ia-dono-phrase]').text()).toBe(
      'Te chamei no privado 😊'
    );
    expect(wrapper.find('[data-ia-dono-phrase-field]').exists()).toBe(false);
    expect(wrapper.find('[data-ia-dono-start]').element.disabled).toBe(false);
    await wrapper.find('[data-ia-dono-start]').trigger('click');
    expect(wrapper.emitted('done')[0][0].phrase).toBe(
      'Te chamei no privado 😊'
    );
  });

  it('ligar emite done com a mensagem, o para quem e a frase mudada', async () => {
    const preview = vi.fn().mockResolvedValue({
      recebe: { sample: true },
      nao: null,
    });
    const wrapper = montar({
      data: painel({ message: '  Oi! O link: loja.com ', para_quem: '' }),
      preview,
    });
    await proximo(wrapper).trigger('click');
    await wrapper.find('[data-ia-dono-who]').setValue(' Quem pedir o link ');
    await proximo(wrapper).trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-ia-dono-phrase]').text()).toBe(
      'Te mandei no privado!'
    );
    await wrapper.find('[data-ia-dono-phrase-edit]').trigger('click');
    await wrapper.find('[data-ia-dono-phrase-field]').setValue('Já te chamei!');
    await wrapper.find('[data-ia-dono-start]').trigger('click');

    expect(wrapper.emitted('done')).toEqual([
      [
        {
          message: 'Oi! O link: loja.com',
          paraQuem: 'Quem pedir o link',
          phrase: 'Já te chamei!',
        },
      ],
    ]);
  });

  it('passo anterior volta sem perder o que foi escrito', async () => {
    const wrapper = montar({ data: painel({ message: 'Oi!' }) });
    await proximo(wrapper).trigger('click');
    await wrapper.find('[data-ia-dono-previous]').trigger('click');

    expect(passo(wrapper)).toBe('1');
    expect(wrapper.find('[data-ia-dono-message]').element.value).toBe('Oi!');
  });

  it('privado não liberado (Facebook): em breve, sem os passos', () => {
    const wrapper = montar({
      data: painel({ network: 'facebook', private_available: false }),
    });

    expect(passo(wrapper)).toBe('soon');
    expect(wrapper.find('[data-ia-dono-bar]').exists()).toBe(false);
    expect(wrapper.text()).toContain('Em breve');
  });
});
