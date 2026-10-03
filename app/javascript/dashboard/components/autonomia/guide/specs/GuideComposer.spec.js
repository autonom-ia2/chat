import { mount, flushPromises } from '@vue/test-utils';
import GuideComposer from '../GuideComposer.vue';

// O gravador de verdade desenha a onda num canvas (WaveSurfer) e pede o
// microfone; aqui ele só emite o que o de verdade emitiria.
const stopRecording = vi.fn();
const GravadorFalso = {
  name: 'AudioRecorder',
  props: ['audioRecordFormat', 'waveHeight'],
  emits: ['recorderProgressChanged', 'finishRecord', 'recordError'],
  methods: { stopRecording },
  template: '<div data-gravador />',
};

const montar = (props, opcoes = {}) =>
  mount(GuideComposer, {
    props: { onSend: vi.fn(() => true), ...props },
    ...opcoes,
    global: {
      stubs: { AudioRecorder: GravadorFalso },
      mocks: {
        $t: (key, valores) =>
          valores ? `${key}:${JSON.stringify(valores)}` : key,
      },
    },
  });

const botao = (wrapper, chave) => wrapper.find(`button[aria-label="${chave}"]`);
const microfone = wrapper => botao(wrapper, 'AUTONOMIA_GUIDE.VOICE.START');
const enviar = wrapper => botao(wrapper, 'AUTONOMIA_GUIDE.A11Y.SEND');
const gravador = wrapper => wrapper.findComponent(GravadorFalso);

const comMicrofone = () => {
  Object.defineProperty(navigator, 'mediaDevices', {
    configurable: true,
    value: { getUserMedia: vi.fn() },
  });
  window.MediaRecorder = class {};
};

afterEach(() => {
  delete window.MediaRecorder;
  stopRecording.mockClear();
});

describe('GuideComposer — arquivos', () => {
  it('manda anexar cada arquivo escolhido e limpa a escolha', async () => {
    const wrapper = montar();
    const input = wrapper.find('input[type="file"]');
    const arquivo = new File(['nome,corretora'], 'leads.csv', {
      type: 'text/csv',
    });
    Object.defineProperty(input.element, 'files', { value: [arquivo] });

    await input.trigger('change');

    expect(wrapper.emitted('anexar')[0]).toEqual([arquivo]);
  });

  it('o clipe também aceita fotos', () => {
    const accept = montar().find('input[type="file"]').attributes('accept');

    ['image/png', 'image/jpeg', 'image/webp', 'image/gif', '.pdf'].forEach(
      tipo => expect(accept).toContain(tipo)
    );
  });

  it('mostra os anexos esperando envio e deixa remover cada um', async () => {
    const wrapper = montar({
      arquivos: [
        { id: 1, nome: 'leads.csv', estado: 'pronto', tipo: 'documento' },
        { id: 2, nome: 'apolice.pdf', estado: 'subindo', tipo: 'documento' },
      ],
    });

    expect(wrapper.text()).toContain('leads.csv');
    expect(wrapper.text()).toContain('apolice.pdf');

    await wrapper
      .find('button[aria-label^="AUTONOMIA_GUIDE.FILE.REMOVE"]')
      .trigger('click');

    expect(wrapper.emitted('remover')[0]).toEqual([1]);
  });

  it('foto anexada aparece com miniatura', () => {
    const wrapper = montar({
      arquivos: [
        {
          id: 1,
          nome: 'print.png',
          estado: 'pronto',
          tipo: 'imagem',
          previa: 'blob:print',
        },
      ],
    });

    expect(wrapper.find('img').attributes('src')).toBe('blob:print');
  });

  it('o clipe tem nome acessível e fica parado enquanto o Guia responde', () => {
    const wrapper = montar({ isBusy: true });

    expect(
      botao(wrapper, 'AUTONOMIA_GUIDE.FILE.ATTACH').attributes('disabled')
    ).toBeDefined();
  });

  it('colar uma foto no campo anexa a foto', async () => {
    const wrapper = montar();
    const foto = new File(['png'], 'image.png', { type: 'image/png' });

    await wrapper
      .find('textarea')
      .trigger('paste', { clipboardData: { files: [foto] } });

    expect(wrapper.emitted('anexar')[0]).toEqual([foto]);
  });

  it('colar texto continua sendo só texto', async () => {
    const wrapper = montar();

    await wrapper
      .find('textarea')
      .trigger('paste', { clipboardData: { files: [] } });

    expect(wrapper.emitted('anexar')).toBeUndefined();
  });

  it('arrastar e soltar arquivos na caixa anexa cada um', async () => {
    const wrapper = montar();
    const foto = new File(['jpg'], 'carro.jpg', { type: 'image/jpeg' });

    await wrapper.trigger('drop', { dataTransfer: { files: [foto] } });

    expect(wrapper.emitted('anexar')[0]).toEqual([foto]);
  });

  it('com anexo pronto e sem texto, envia mesmo assim', async () => {
    const onSend = vi.fn(() => true);
    const wrapper = montar({
      onSend,
      arquivos: [{ id: 1, nome: 'a.png', estado: 'pronto', tipo: 'imagem' }],
    });

    await enviar(wrapper).trigger('submit');

    expect(onSend).toHaveBeenCalledWith('');
  });

  it('não envia enquanto um anexo ainda está subindo, e avisa', async () => {
    const onSend = vi.fn(() => true);
    const wrapper = montar({
      onSend,
      arquivos: [{ id: 1, nome: 'a.pdf', estado: 'subindo' }],
    });
    const textarea = wrapper.find('textarea');
    await textarea.setValue('lê isso');

    await textarea.trigger('keydown', { key: 'Enter' });

    expect(onSend).not.toHaveBeenCalled();
    expect(enviar(wrapper).attributes('disabled')).toBeDefined();
    expect(wrapper.text()).toContain('AUTONOMIA_GUIDE.FILE.WAIT');
  });
});

describe('GuideComposer — microfone ou enviar, como no WhatsApp', () => {
  beforeEach(comMicrofone);

  it('campo vazio mostra o microfone; com texto, vira enviar', async () => {
    const wrapper = montar({ onEnviarVoz: vi.fn() });

    expect(microfone(wrapper).exists()).toBe(true);
    expect(enviar(wrapper).exists()).toBe(false);

    await wrapper.find('textarea').setValue('oi');

    expect(microfone(wrapper).exists()).toBe(false);
    expect(enviar(wrapper).exists()).toBe(true);
  });

  it('com anexo esperando envio, o botão é enviar', () => {
    const wrapper = montar({
      onEnviarVoz: vi.fn(),
      arquivos: [{ id: 1, nome: 'a.pdf', estado: 'pronto' }],
    });

    expect(microfone(wrapper).exists()).toBe(false);
    expect(enviar(wrapper).exists()).toBe(true);
  });

  it('anexo que falhou não conta: o microfone volta', () => {
    const wrapper = montar({
      onEnviarVoz: vi.fn(),
      arquivos: [{ id: 1, nome: 'a.exe', estado: 'erro' }],
    });

    expect(microfone(wrapper).exists()).toBe(true);
  });

  it('não mostra o microfone onde o navegador não grava', () => {
    delete window.MediaRecorder;
    const wrapper = montar({ onEnviarVoz: vi.fn() });

    expect(microfone(wrapper).exists()).toBe(false);
    expect(enviar(wrapper).exists()).toBe(true);
  });

  it('o microfone fica parado enquanto o Guia responde', () => {
    const wrapper = montar({ onEnviarVoz: vi.fn(), isBusy: true });

    expect(microfone(wrapper).attributes('disabled')).toBeDefined();
  });
});

describe('GuideComposer — gravando', () => {
  beforeEach(comMicrofone);

  const comecarGravacao = async (props = {}) => {
    const onEnviarVoz = vi.fn();
    const wrapper = montar(
      { onEnviarVoz, ...props },
      { attachTo: document.body }
    );
    await microfone(wrapper).trigger('click');
    return { wrapper, onEnviarVoz };
  };

  it('a barra de gravação toma o lugar do campo', async () => {
    const { wrapper } = await comecarGravacao();

    expect(wrapper.find('[data-gravacao]').exists()).toBe(true);
    expect(wrapper.find('textarea').exists()).toBe(false);
    expect(gravador(wrapper).exists()).toBe(true);
    expect(gravador(wrapper).props('waveHeight')).toBe(36);
    wrapper.unmount();
  });

  it('um segundo toque não abre outro gravador', async () => {
    const { wrapper } = await comecarGravacao();

    expect(microfone(wrapper).exists()).toBe(false);
    expect(wrapper.findAllComponents(GravadorFalso)).toHaveLength(1);
    wrapper.unmount();
  });

  it('enviar só libera quando o microfone começou a gravar', async () => {
    const { wrapper } = await comecarGravacao();
    const enviarVoz = () => botao(wrapper, 'AUTONOMIA_GUIDE.VOICE.SEND');

    expect(enviarVoz().attributes('disabled')).toBeDefined();

    gravador(wrapper).vm.$emit('recorderProgressChanged', '00:05');
    await flushPromises();

    expect(enviarVoz().attributes('disabled')).toBeUndefined();
    expect(wrapper.text()).toContain('0:05');
    expect(wrapper.find('[role="status"]').text()).toBe(
      'AUTONOMIA_GUIDE.VOICE.RECORDING'
    );
    wrapper.unmount();
  });

  it('enviar para a gravação e manda o áudio com a duração', async () => {
    const { wrapper, onEnviarVoz } = await comecarGravacao();
    gravador(wrapper).vm.$emit('recorderProgressChanged', '00:07');
    await flushPromises();

    await botao(wrapper, 'AUTONOMIA_GUIDE.VOICE.SEND').trigger('click');
    expect(stopRecording).toHaveBeenCalledOnce();

    const audio = new File(['ogg'], 'voz.ogg', { type: 'audio/ogg' });
    gravador(wrapper).vm.$emit('finishRecord', { file: audio });
    await flushPromises();

    expect(onEnviarVoz).toHaveBeenCalledWith({ audio, duracao: 7 });
    expect(wrapper.find('textarea').exists()).toBe(true);
    expect(document.activeElement).toBe(wrapper.find('textarea').element);
    wrapper.unmount();
  });

  it('aos 2 minutos para e envia sozinho', async () => {
    const { wrapper } = await comecarGravacao();
    gravador(wrapper).vm.$emit('recorderProgressChanged', '00:01');
    gravador(wrapper).vm.$emit('recorderProgressChanged', '02:00');
    await flushPromises();

    expect(stopRecording).toHaveBeenCalledOnce();
    wrapper.unmount();
  });

  it('a lixeira apaga: nada é enviado e o campo volta com o foco', async () => {
    const { wrapper, onEnviarVoz } = await comecarGravacao();
    gravador(wrapper).vm.$emit('recorderProgressChanged', '00:03');
    await flushPromises();

    await botao(wrapper, 'AUTONOMIA_GUIDE.VOICE.CANCEL').trigger('click');
    await flushPromises();

    expect(gravador(wrapper).exists()).toBe(false);
    expect(onEnviarVoz).not.toHaveBeenCalled();
    expect(document.activeElement).toBe(wrapper.find('textarea').element);
    expect(wrapper.find('[role="status"]').text()).toBe(
      'AUTONOMIA_GUIDE.VOICE.CANCELLED'
    );
    wrapper.unmount();
  });

  it('Esc apaga a gravação sem fechar o painel do Guia', async () => {
    const outroEsc = vi.fn();
    document.addEventListener('keydown', outroEsc);
    const { wrapper, onEnviarVoz } = await comecarGravacao();

    document.body.dispatchEvent(
      new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })
    );
    await flushPromises();

    expect(gravador(wrapper).exists()).toBe(false);
    expect(onEnviarVoz).not.toHaveBeenCalled();
    expect(outroEsc).not.toHaveBeenCalled();
    document.removeEventListener('keydown', outroEsc);
    wrapper.unmount();
  });

  it('avisa quando o navegador não libera o microfone', async () => {
    const { wrapper } = await comecarGravacao();

    gravador(wrapper).vm.$emit('recordError', { error: new Error('negado') });
    await flushPromises();

    expect(wrapper.emitted('semMicrofone')).toHaveLength(1);
    expect(gravador(wrapper).exists()).toBe(false);
    wrapper.unmount();
  });

  it('se o áudio não fica pronto depois de parar, avisa outra coisa', async () => {
    const { wrapper, onEnviarVoz } = await comecarGravacao();
    gravador(wrapper).vm.$emit('recorderProgressChanged', '00:02');
    await flushPromises();
    await botao(wrapper, 'AUTONOMIA_GUIDE.VOICE.SEND').trigger('click');

    gravador(wrapper).vm.$emit('recordError', { error: new Error('mp3') });
    await flushPromises();

    expect(wrapper.emitted('gravacaoFalhou')).toHaveLength(1);
    expect(wrapper.emitted('semMicrofone')).toBeUndefined();
    expect(onEnviarVoz).not.toHaveBeenCalled();
    wrapper.unmount();
  });
});
