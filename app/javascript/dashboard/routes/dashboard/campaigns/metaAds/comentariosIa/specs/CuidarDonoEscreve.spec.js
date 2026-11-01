import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/metaAdsComentariosIa.json';
import CuidarDono from '../CuidarDono.vue';

// #2458 (PR 2 do #2436): com a IA escrevendo as respostas (Painel `writes`), o passo 2 soma temas e pede o assunto em
// que a IA não toca; o passo 3 mostra o que a IA escreveria e aceita o pedido de tom; "Ligar" leva tudo em `escrita`.
const painel = (extra = {}) => ({
  network: 'instagram',
  private_available: true,
  care: 'off',
  message: 'Oi! O seguro sai a partir de R$ 39.',
  para_quem: '',
  phrases: ['Te mandei no privado!'],
  unanswered: 0,
  writes: true,
  temas: [],
  assunto_proibido: '',
  tom: '',
  ...extra,
});

const montadas = [];
const montar = ({ data = painel(), preview } = {}) => {
  const wrapper = mount(CuidarDono, {
    props: { data, preview: preview || vi.fn().mockResolvedValue(null) },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: ptBR },
        }),
      ],
    },
  });
  montadas.push(wrapper);
  return wrapper;
};
const proximo = wrapper => wrapper.find('[data-ia-dono-next]');
const chips = wrapper => wrapper.findAll('[data-ia-dono-suggestion]');
const irAoPasso2 = async wrapper => {
  await proximo(wrapper).trigger('click');
};
const irAoPasso3 = async wrapper => {
  await irAoPasso2(wrapper);
  await proximo(wrapper).trigger('click');
  await flushPromises();
};

describe('CuidarDono com a IA escrevendo (#2458)', () => {
  afterEach(() => {
    montadas.splice(0).forEach(wrapper => wrapper.unmount());
  });

  it('passo 2: o cuidado novo começa com o preço marcado, e os chips somam numa frase só', async () => {
    const wrapper = montar();
    await irAoPasso2(wrapper);

    expect(chips(wrapper)[0].attributes('aria-pressed')).toBe('true');
    expect(wrapper.find('[data-ia-dono-who]').element.value).toBe(
      'Quem perguntar o preço'
    );

    await chips(wrapper)[1].trigger('click');

    expect(chips(wrapper)[1].attributes('aria-pressed')).toBe('true');
    expect(wrapper.find('[data-ia-dono-who]').element.value).toBe(
      'Quem perguntar o preço ou pedir o link'
    );
  });

  it('passo 2: ao reabrir, os chips gravados (pela chave) voltam marcados', async () => {
    const wrapper = montar({
      data: painel({ para_quem: 'Quem pedir o link', temas: ['link'] }),
    });
    await irAoPasso2(wrapper);

    expect(chips(wrapper).map(chip => chip.attributes('aria-pressed'))).toEqual(
      ['false', 'true', 'false']
    );

    await chips(wrapper)[0].trigger('click');

    expect(wrapper.find('[data-ia-dono-who]').element.value).toBe(
      'Quem perguntar o preço ou pedir o link'
    );
  });

  it('passo 2: a frase reescrita pelo dono não é trocada pelos chips', async () => {
    const wrapper = montar();
    await irAoPasso2(wrapper);
    await wrapper.find('[data-ia-dono-who]').setValue('Quem quer viajar');

    await chips(wrapper)[2].trigger('click');

    expect(wrapper.find('[data-ia-dono-who]').element.value).toBe(
      'Quem quer viajar'
    );
  });

  it('passo 2: o assunto proibido longo demais não continua', async () => {
    const wrapper = montar();
    await irAoPasso2(wrapper);

    await wrapper.find('[data-ia-dono-nao-falo]').setValue('a'.repeat(301));

    expect(proximo(wrapper).element.disabled).toBe(true);
  });

  it('passo 3: pede a prévia com o assunto e o tom, e mostra o que a IA escreveria', async () => {
    const preview = vi.fn().mockResolvedValue({
      recebe: {
        id: '1',
        author: 'carla',
        text: 'Quanto custa pra Europa?',
        network: 'instagram',
        written: {
          dm: 'Para a Europa, a partir de R$ 39 por dia.',
          comment: 'Te mandei no direct!',
        },
      },
      nao: null,
      dono: {
        id: '2',
        author: 'joao',
        text: 'E o meu reembolso?',
        network: 'instagram',
      },
    });
    const wrapper = montar({
      data: painel({ assunto_proibido: 'reembolso' }),
      preview,
    });
    await irAoPasso3(wrapper);

    expect(preview).toHaveBeenCalledWith('Quem perguntar o preço', {
      assuntoProibido: 'reembolso',
      tom: '',
    });
    expect(wrapper.find('[data-ia-dono-bubble]').text()).toBe(
      'Para a Europa, a partir de R$ 39 por dia.'
    );
    expect(wrapper.find('[data-ia-dono-written-comment]').text()).toBe(
      'Te mandei no direct!'
    );
    expect(wrapper.find('[data-ia-dono-phrase]').exists()).toBe(false);
    expect(wrapper.find('[data-ia-dono-example="dono"]').text()).toContain(
      'reembolso'
    );
  });

  it('passo 3: o agente não saberia: diz que fica com o dono, sem balão', async () => {
    const preview = vi.fn().mockResolvedValue({
      recebe: {
        id: '1',
        author: 'carla',
        text: 'Cobre paraquedas?',
        network: 'instagram',
        kept_for_owner: true,
      },
      nao: null,
    });
    const wrapper = montar({ preview });
    await irAoPasso3(wrapper);

    expect(wrapper.find('[data-ia-dono-kept]').exists()).toBe(true);
    expect(wrapper.find('[data-ia-dono-bubble]').exists()).toBe(false);
  });

  it('passo 3: o pedido de tom escreve a prévia de novo, e "Ligar" leva tudo', async () => {
    const preview = vi.fn().mockResolvedValue(null);
    const wrapper = montar({ preview });
    await irAoPasso3(wrapper);

    await wrapper.find('[data-ia-dono-tom-campo]').setValue('mais formal');
    await wrapper.find('[data-ia-dono-tom-ajustar]').trigger('click');
    await flushPromises();

    expect(preview).toHaveBeenLastCalledWith('Quem perguntar o preço', {
      assuntoProibido: '',
      tom: 'mais formal',
    });
    await wrapper.find('[data-ia-dono-start]').trigger('click');
    expect(wrapper.emitted('done')[0][0]).toEqual({
      message: 'Oi! O seguro sai a partir de R$ 39.',
      paraQuem: 'Quem perguntar o preço',
      phrase: 'Te mandei no privado!',
      escrita: {
        temas: ['price'],
        assuntoProibido: '',
        tom: 'mais formal',
      },
    });
  });

  it('sem a escrita, "Ligar" não leva `escrita` e a prévia é pedida como antes', async () => {
    const preview = vi.fn().mockResolvedValue(null);
    const wrapper = montar({
      data: painel({ writes: undefined, para_quem: 'Quem perguntar o preço' }),
      preview,
    });
    await irAoPasso3(wrapper);

    expect(preview).toHaveBeenCalledWith('Quem perguntar o preço');
    expect(wrapper.find('[data-ia-dono-tom]').exists()).toBe(false);
    await wrapper.find('[data-ia-dono-start]').trigger('click');
    expect(wrapper.emitted('done')[0][0].escrita).toBeUndefined();
  });
});
