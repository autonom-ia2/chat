import { mount } from '@vue/test-utils';
import GuideUserMessage from '../GuideUserMessage.vue';

// #895 — o balão de quem usa: texto, fotos, arquivos e a mensagem de voz.
const montar = item =>
  mount(GuideUserMessage, {
    props: { item: { anexos: [], voz: null, texto: '', ...item } },
    global: {
      stubs: { GuideVoz: true },
      mocks: { $t: key => key },
    },
  });

const VOZ = { url: 'blob:voz', duracao: 4, texto: '', erro: '' };

describe('GuideUserMessage', () => {
  it('mostra o texto enviado', () => {
    expect(montar({ texto: 'Como crio um funil?' }).text()).toContain(
      'Como crio um funil?'
    );
  });

  it('mostra as fotos como miniatura e os arquivos como cartão', () => {
    const wrapper = montar({
      anexos: [
        { id: 1, nome: 'print.png', tipo: 'imagem', previa: 'blob:print' },
        { id: 2, nome: 'apolice.pdf', tipo: 'documento', previa: null },
      ],
    });

    const foto = wrapper.find('img');
    expect(foto.attributes('src')).toBe('blob:print');
    expect(foto.attributes('alt')).toBe('print.png');
    expect(wrapper.text()).toContain('apolice.pdf');
    expect(wrapper.findAll('img')).toHaveLength(1);
  });

  it('só anexos, sem texto: o balão não inventa frase', () => {
    const wrapper = montar({
      anexos: [{ id: 1, nome: 'a.pdf', tipo: 'documento' }],
    });

    expect(wrapper.text()).not.toContain('DEFAULT_MESSAGE');
  });

  it('mensagem de voz: o áudio toca com a duração já conhecida', () => {
    const wrapper = montar({ voz: { ...VOZ, estado: 'transcrevendo' } });
    const player = wrapper.findComponent({ name: 'GuideVoz' });

    expect(player.props('src')).toBe('blob:voz');
    expect(player.props('duracao')).toBe(4);
    expect(wrapper.text()).toContain('AUTONOMIA_GUIDE.VOICE.TRANSCRIBING');
  });

  it('com a transcrição pronta, mostra o que foi falado debaixo do áudio', () => {
    const wrapper = montar({
      voz: { ...VOZ, estado: 'pronta', texto: 'quantos leads tenho' },
    });

    expect(wrapper.text()).toContain('quantos leads tenho');
    expect(wrapper.text()).not.toContain('TRANSCRIBING');
  });

  it('se a transcrição falha, diz e oferece tentar de novo', async () => {
    const wrapper = montar({
      voz: { ...VOZ, estado: 'erro', erro: 'Áudio muito longo.' },
    });

    expect(wrapper.text()).toContain('Áudio muito longo.');
    const tentar = wrapper
      .findAll('button')
      .find(b => b.text() === 'AUTONOMIA_GUIDE.VOICE.RETRY');
    await tentar.trigger('click');

    expect(wrapper.emitted('tentarDeNovo')).toHaveLength(1);
  });
});
