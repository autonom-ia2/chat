import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import EtapasDoTopo from '../../components/trazer/EtapasDoTopo.vue';
// #2894 — as etapas do topo (Enviar → Conferir → Pronto): o passo 3 diz
// "Trazendo" enquanto a lista é trazida, e a lista cabe em 390 px.
withFullI18n('pt_BR');

vi.setConfig({ testTimeout: 30000 });

const marca = (w, nome) => w.find(`[data-relacionamentos="${nome}"]`);

describe('o passo 3', () => {
  it('o passo 3 é "Trazendo" enquanto traz e "Pronto" quando termina', () => {
    const trazendo = mount(EtapasDoTopo, {
      props: { atual: 'pronto', trazendo: true },
    });
    const atual = trazendo.get('[aria-current="step"]');
    expect(atual.text()).toContain('Trazendo');
    expect(atual.text()).not.toContain('Pronto');
    const pronto = mount(EtapasDoTopo, { props: { atual: 'pronto' } });
    expect(pronto.get('[aria-current="step"]').text()).toContain('Pronto');
    const antes = mount(EtapasDoTopo, {
      props: { atual: 'conferir', trazendo: true },
    });
    expect(antes.get('[data-etapa="pronto"]').text()).toContain('Pronto');
  });
});

describe('etapas do topo em 390 px', () => {
  it('traços e vãos encolhem no celular e a lista nunca passa da largura', () => {
    const w = mount(EtapasDoTopo, {
      props: { atual: 'pronto', trazendo: true },
    });
    const lista = marca(w, 'etapas');
    expect(lista.classes()).toEqual(
      expect.arrayContaining(['max-w-full', 'min-w-0', 'gap-2'])
    );
    const traco = w.get('[data-etapa="enviar"] .h-px');
    expect(traco.classes()).toEqual(
      expect.arrayContaining(['w-3', 'sm:w-6', 'md:w-12'])
    );
  });
});
