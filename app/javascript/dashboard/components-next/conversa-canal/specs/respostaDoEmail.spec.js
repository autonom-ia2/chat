import { defineComponent, h, nextTick } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { useDitado } from '../email/useDitado';
import TopoDaResposta from '../email/TopoDaResposta.vue';
import CampoDeEnderecos from '../email/CampoDeEnderecos.vue';
import { MODOS_DE_RESPOSTA } from '../email/useConversaDeEmail';

// #1786 — revisão crítica: o ditado solta o microfone, o menu de tipo não apaga a
// resposta montada e o endereço errado não fica só na cor.
const api = vi.hoisted(() => ({ ditar: vi.fn() }));
vi.mock('dashboard/api/conversaEmail', () => ({ default: api }));
vi.mock('dashboard/api/contacts', () => ({ default: { search: vi.fn() } }));

const trilhas = [];
class GravadorFalso {
  constructor(stream) {
    this.stream = stream;
    this.state = 'inactive';
  }

  start() {
    this.state = 'recording';
  }

  stop() {
    this.state = 'inactive';
    setTimeout(() => this.onstop?.());
  }
}

const montarDitado = () => {
  let ditado;
  const wrapper = mount(
    defineComponent({
      setup() {
        ditado = useDitado();
        return () => h('div');
      },
    })
  );
  return { ditado, wrapper };
};

describe('ditado (useDitado)', () => {
  beforeEach(() => {
    trilhas.length = 0;
    globalThis.MediaRecorder = GravadorFalso;
    Object.defineProperty(globalThis.navigator, 'mediaDevices', {
      configurable: true,
      value: {
        getUserMedia: vi.fn(async () => {
          const trilha = { stop: vi.fn() };
          trilhas.push(trilha);
          return { getTracks: () => [trilha] };
        }),
      },
    });
  });

  it('cancelar solta o microfone e volta a parado; depois dá para ditar de novo', async () => {
    const { ditado } = montarDitado();
    await ditado.iniciar();
    expect(ditado.estado.value).toBe('ouvindo');

    ditado.cancelar();
    await new Promise(resolve => {
      setTimeout(resolve);
    });

    expect(trilhas[0].stop).toHaveBeenCalled();
    expect(ditado.estado.value).toBe('parado');
    expect(await ditado.parar()).toBe('');
    await ditado.iniciar();
    expect(ditado.estado.value).toBe('ouvindo');
  });

  it('dois toques seguidos abrem um microfone só', async () => {
    const { ditado } = montarDitado();
    await Promise.all([ditado.iniciar(), ditado.iniciar()]);

    expect(navigator.mediaDevices.getUserMedia).toHaveBeenCalledTimes(1);
  });

  it('cancelar durante a transcrição descarta o texto que chegar depois', async () => {
    let entregar;
    api.ditar.mockReturnValue(
      new Promise(resolve => {
        entregar = resolve;
      })
    );
    const { ditado } = montarDitado();
    await ditado.iniciar();
    const texto = ditado.parar();
    await new Promise(resolve => {
      setTimeout(resolve);
    });
    expect(ditado.estado.value).toBe('transcrevendo');

    ditado.cancelar();
    entregar({ data: { texto: 'Oi, Marina' } });

    expect(await texto).toBe('');
  });
});

describe('menu do tipo de resposta (TopoDaResposta)', () => {
  const montarTopo = () =>
    mount(TopoDaResposta, {
      props: { modo: MODOS_DE_RESPOSTA.TODOS },
      global: { mocks: { $t: chave => chave } },
    });

  it('Esc e o tipo já escolhido só fecham o menu', async () => {
    const topo = montarTopo();
    await topo.find('[data-tipo-de-resposta]').trigger('click');
    await topo.find('[role=menu]').trigger('keydown', { key: 'Escape' });
    expect(topo.find('[role=menu]').exists()).toBe(false);

    await topo.find('[data-tipo-de-resposta]').trigger('click');
    await topo
      .find(`[data-tipo="${MODOS_DE_RESPOSTA.TODOS}"]`)
      .trigger('click');

    expect(topo.emitted('trocarModo')).toBeUndefined();
  });

  it('outro tipo troca', async () => {
    const topo = montarTopo();
    await topo.find('[data-tipo-de-resposta]').trigger('click');
    await topo
      .find(`[data-tipo="${MODOS_DE_RESPOSTA.ENCAMINHAR}"]`)
      .trigger('click');

    expect(topo.emitted('trocarModo')).toEqual([
      [MODOS_DE_RESPOSTA.ENCAMINHAR],
    ]);
  });
});

describe('campo de endereços (CampoDeEnderecos)', () => {
  it('endereço errado: ícone, frase ligada ao campo e aria-invalid', async () => {
    const campo = mount(CampoDeEnderecos, {
      props: { rotulo: 'Para', modelValue: 'marina@gmail' },
    });
    await nextTick();

    const entrada = campo.find('input');
    const erro = campo.find('[data-erro-de-endereco]');
    expect(erro.exists()).toBe(true);
    expect(entrada.attributes('aria-invalid')).toBe('true');
    expect(entrada.attributes('aria-describedby')).toBe(erro.attributes('id'));
  });

  it('lista de sugestões fechada não fica na página (o Esc da resposta funciona)', async () => {
    const campo = mount(CampoDeEnderecos, {
      props: { rotulo: 'Para', modelValue: 'marina@exemplo.com.br' },
    });
    await flushPromises();

    expect(campo.find('[role=listbox]').exists()).toBe(false);
    expect(campo.find('[data-erro-de-endereco]').exists()).toBe(false);
  });
});
