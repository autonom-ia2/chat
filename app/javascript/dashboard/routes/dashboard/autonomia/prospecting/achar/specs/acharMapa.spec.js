// #2692 — o mapa da lista nova (pedido do Rodrigo depois da r5). O mapa é o de
// hoje (ProspectingGoogleMap.vue); aqui se confere o que a tela nova pede dele:
// pino na cor da chance, "Chame primeiro" maior, quem não vai apagado, pino
// clicado destaca a empresa, e sem chave só o aviso de sempre.
import { flushPromises, mount } from '@vue/test-utils';
import ProspectingGoogleMap from '../../components/ProspectingGoogleMap.vue';
import AcharMapaDaLista from '../components/AcharMapaDaLista.vue';

vi.mock('@googlemaps/markerclusterer', () => ({
  MarkerClusterer: class {
    clearMarkers = vi.fn();
  },
}));

let markers = [];

const fakeGoogleMaps = () => {
  markers = [];
  function Marker(options) {
    this.options = options;
    this.setMap = vi.fn();
    this.setIcon = vi.fn();
    this.setZIndex = vi.fn();
    this.listeners = {};
    this.addListener = (event, handler) => {
      this.listeners[event] = handler;
    };
    markers.push(this);
  }
  function GoogleMap() {
    this.addListener = () => ({ remove: vi.fn() });
    this.fitBounds = vi.fn();
    this.setCenter = vi.fn();
    this.setZoom = vi.fn();
    this.getBounds = () => null;
    this.getCenter = () => null;
  }
  function LatLngBounds() {
    this.extend = vi.fn();
  }
  window.google = {
    maps: {
      Map: GoogleMap,
      Marker,
      LatLngBounds,
      SymbolPath: { CIRCLE: 'circle' },
    },
  };
};

const empresa = (id, chance, extra = {}) => ({
  id,
  nome: `Empresa ${id}`,
  chance,
  latitude: -22.9 - id / 1000,
  longitude: -47.06,
  fora: null,
  ...extra,
});

const EMPRESAS = [
  empresa(1, 'boa'),
  empresa(2, 'boa'),
  empresa(3, 'media'),
  empresa(4, 'pouca', { fora: { motivo: 'no_funil' } }),
  empresa(5, 'pouca', { latitude: null }),
];

const montar = (props = {}) =>
  mount(AcharMapaDaLista, {
    props: {
      empresas: EMPRESAS,
      primeiroId: 1,
      naoVai: new Set([3]),
      ...props,
    },
  });

describe('Achar · mapa da lista', () => {
  beforeEach(() => {
    fakeGoogleMaps();
    window.chatwootConfig = { googleMapsBrowserApiKey: 'chave-de-teste' };
  });

  afterEach(() => {
    delete window.google;
    delete window.chatwootConfig;
  });

  it('põe um pino por empresa com lugar, sem agrupar e sem número', async () => {
    const wrapper = montar();
    await flushPromises();

    expect(markers).toHaveLength(4);
    expect(markers.every(marker => marker.options.label === undefined)).toBe(
      true
    );
    expect(markers.every(marker => marker.options.map)).toBeTruthy();
    wrapper.unmount();
  });

  it('cor da chance, "Chame primeiro" maior, quem não vai ou está fora apagado', async () => {
    const wrapper = montar();
    await flushPromises();

    const [primeiro, boa, naoVai, fora] = markers.map(m => m.options.icon);
    expect(primeiro.fillColor).toBe('#12a594');
    expect(primeiro.scale).toBeGreaterThan(boa.scale);
    expect(boa.fillColor).toBe('#0d74ce');
    expect(boa.fillOpacity).toBe(1);
    expect(naoVai.fillColor).toBe('#ffb224');
    expect(naoVai.fillOpacity).toBeLessThan(1);
    expect(fora.fillOpacity).toBeLessThan(1);
    wrapper.unmount();
  });

  it('clicar no pino pede o destaque da empresa', async () => {
    const wrapper = montar();
    await flushPromises();

    markers[1].listeners.click();
    expect(wrapper.emitted('selecionar')).toEqual([[2]]);
    wrapper.unmount();
  });

  it('empresa destacada troca só o desenho do pino, sem refazer o mapa', async () => {
    const wrapper = montar();
    await flushPromises();
    const antes = markers.length;

    await wrapper.setProps({ destacada: 2 });
    await flushPromises();

    expect(markers).toHaveLength(antes);
    const icone = markers[1].setIcon.mock.calls.at(-1)[0];
    expect(icone.strokeWeight).toBe(3);
    expect(markers[1].setZIndex).toHaveBeenLastCalledWith(3);
    wrapper.unmount();
  });

  it('sem a chave do Google mostra o aviso de sempre e nenhum pino', async () => {
    window.chatwootConfig = {};
    const wrapper = montar();
    await flushPromises();

    expect(markers).toHaveLength(0);
    expect(wrapper.text()).toContain('PROSPECTING.SEARCH.MAP_API_KEY_MISSING');
    wrapper.unmount();
  });
});

describe('ProspectingGoogleMap · sem pinStyle continua como hoje', () => {
  beforeEach(fakeGoogleMaps);
  afterEach(() => {
    delete window.google;
  });

  it('o pino de hoje mantém o número da fila', async () => {
    const wrapper = mount(ProspectingGoogleMap, {
      props: {
        apiKey: 'chave',
        leads: [
          { id: 1, latitude: -22.9, longitude: -47, priority_position: 4 },
        ],
      },
    });
    await flushPromises();

    expect(markers[0].options.label).toBe('4');
    expect(markers[0].options.icon).toBeUndefined();
    wrapper.unmount();
  });
});
