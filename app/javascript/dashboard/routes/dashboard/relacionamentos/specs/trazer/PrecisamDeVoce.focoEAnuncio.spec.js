import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import {
  leituraDeExemplo,
  aplicarConserto,
  aplicarDeixarDeFora,
  aplicarReabrir,
} from '../../demo/trazer';
import PrecisamDeVoce from '../../components/trazer/PrecisamDeVoce.vue';
import { TELEFONE_QUE_VALE, tudoResolvido } from './apoioDaDemo';

// #2894 — "Precisam de você": ao resolver (ou reabrir) uma linha, o foco vai
// para o próximo problema aberto e a mudança é dita numa região viva.
withFullI18n('pt_BR');

const marca = (w, nome) => w.find(`[data-relacionamentos="${nome}"]`);

const leitura = leituraDeExemplo('l1');

// Com a máquina carregada, o primeiro mount do arquivo passa dos 5 s padrão.
vi.setConfig({ testTimeout: 30000 });

// O jsdom não tem scrollIntoView, que o ChoiceSelect chama ao abrir a lista.
beforeEach(() => {
  Element.prototype.scrollIntoView = vi.fn();
});
afterEach(() => {
  document.body.innerHTML = '';
});

describe('foco e anúncio ao resolver uma linha', () => {
  const montar = (l = leitura) =>
    mount(PrecisamDeVoce, {
      attachTo: document.body,
      props: { problemas: l.problemas },
    });
  const resolver = async (w, nova) => {
    await w.setProps({ problemas: nova.problemas });
    await flushPromises();
  };

  it('a região viva existe desde o início, vazia, e a seção não é aria-live', () => {
    const w = montar();
    const aviso = marca(w, 'anuncio-precisam');
    expect(aviso.exists()).toBe(true);
    expect(aviso.attributes('role')).toBe('status');
    expect(aviso.text()).toBe('');
    expect(
      marca(w, 'precisam-de-voce').attributes('aria-live')
    ).toBeUndefined();
  });

  it('resolver a linha 14 leva o foco ao campo da linha 37 e anuncia', async () => {
    const w = montar();
    await resolver(w, aplicarConserto(leitura, 14, TELEFONE_QUE_VALE));
    expect(document.activeElement).toBe(
      w.get('[data-linha="37"] input').element
    );
    expect(marca(w, 'anuncio-precisam').text()).toBe('Linha 14: pronto');
  });

  it('deixar de fora anuncia e leva ao próximo, que pode ser de escolha', async () => {
    const w = montar();
    // A linha 118 (fórmula na empresa) só pode ficar de fora; a aberta seguinte
    // é a repetida, que se resolve escolhendo.
    await resolver(w, aplicarDeixarDeFora(leitura, 118));
    expect(document.activeElement).toBe(
      w.get('[data-linha="143"] button').element
    );
    expect(marca(w, 'anuncio-precisam').text()).toBe(
      'Linha 118: deixada de fora'
    );
  });

  it('resolver a última volta ao primeiro problema ainda aberto', async () => {
    const w = montar();
    await resolver(w, aplicarDeixarDeFora(leitura, 171));
    expect(document.activeElement).toBe(
      w.get('[data-linha="14"] input').element
    );
  });

  it('sem problema aberto, o foco vai ao título da seção', async () => {
    const w = montar();
    await resolver(w, tudoResolvido(leitura));
    expect(document.activeElement).toBe(marca(w, 'precisam-titulo').element);
    expect(marca(w, 'precisam-titulo').text()).toBe('Tudo resolvido');
  });

  it('a linha resolvida não nasce com role="status" própria', async () => {
    const w = montar();
    await resolver(w, aplicarConserto(leitura, 62, 'Ana'));
    expect(w.get('[data-linha="62"]').find('[role="status"]').exists()).toBe(
      false
    );
  });

  it('voltar atrás leva o foco ao primeiro campo da linha reaberta e anuncia', async () => {
    const resolvida = aplicarConserto(leitura, 62, 'Ana');
    const w = montar(resolvida);
    await resolver(w, aplicarReabrir(resolvida, 62));
    expect(document.activeElement).toBe(
      w.get('[data-linha="62"] input').element
    );
    expect(marca(w, 'anuncio-precisam').text()).toBe(
      'Linha 62: voltou para você conferir'
    );
  });

  it('mudança sem linha resolvida não mexe no foco nem no aviso', async () => {
    const w = montar();
    await resolver(w, { problemas: [...leitura.problemas] });
    expect(marca(w, 'anuncio-precisam').text()).toBe('');
    expect(document.activeElement).toBe(document.body);
  });
});
