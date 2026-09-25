// Pinos agrupados no mapa de resultados (#678, E2 frente E), como o Orth
// (MapResults.tsx): com mais de um pino, o MarkerClusterer junta os pinos;
// com um só, o pino vai direto no mapa. O clusterer é trocado por um mock.
import { flushPromises, mount } from '@vue/test-utils';
import ProspectingGoogleMap from '../components/ProspectingGoogleMap.vue';

const clusterers = vi.hoisted(() => []);

vi.mock('@googlemaps/markerclusterer', () => ({
  MarkerClusterer: class {
    constructor(options) {
      this.options = options;
      this.clearMarkers = vi.fn();
      clusterers.push(this);
    }
  },
}));

let markers = [];

const fakeGoogleMaps = () => {
  markers = [];
  function Marker(options) {
    this.options = options;
    this.setMap = vi.fn();
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
  function Shape() {
    this.setMap = vi.fn();
    this.getBounds = () => null;
  }
  window.google = {
    maps: {
      Map: GoogleMap,
      Marker,
      LatLngBounds,
      Circle: Shape,
      Rectangle: Shape,
    },
  };
};

const lead = (id, extra = {}) => ({
  id,
  name: `Lead ${id}`,
  latitude: -25.4 - id / 1000,
  longitude: -49.2,
  priority_position: id,
  ...extra,
});

const mountMap = leads =>
  mount(ProspectingGoogleMap, {
    props: { apiKey: 'chave', leads },
  });

describe('ProspectingGoogleMap · pinos agrupados', () => {
  beforeEach(() => {
    clusterers.length = 0;
    fakeGoogleMaps();
  });

  afterEach(() => {
    delete window.google;
  });

  it('com vários pinos entrega todos ao clusterer, fora do mapa', async () => {
    const wrapper = mountMap([lead(1), lead(2), lead(3)]);
    await flushPromises();

    expect(clusterers).toHaveLength(1);
    expect(clusterers[0].options.markers).toEqual(markers);
    expect(clusterers[0].options.map).toBeTruthy();
    expect(markers.map(marker => marker.options.map)).toEqual([
      undefined,
      undefined,
      undefined,
    ]);
    wrapper.unmount();
  });

  it('com um pino só não agrupa e põe o pino no mapa', async () => {
    const wrapper = mountMap([lead(1)]);
    await flushPromises();

    expect(clusterers).toHaveLength(0);
    expect(markers).toHaveLength(1);
    expect(markers[0].options.map).toBeTruthy();
    wrapper.unmount();
  });

  it('o número do pino é a posição do lead na fila, como no card', async () => {
    const wrapper = mountMap([
      lead(1, { priority_position: 4 }),
      lead(2, { priority_position: null }),
    ]);
    await flushPromises();

    expect(markers.map(marker => marker.options.label)).toEqual(['4', '2']);
    wrapper.unmount();
  });

  it('clique no pino agrupado abre o lead', async () => {
    const wrapper = mountMap([lead(1), lead(2)]);
    await flushPromises();

    markers[1].listeners.click();
    expect(wrapper.emitted('selectLead')).toEqual([[lead(2)]]);
    wrapper.unmount();
  });

  it('trocar os leads limpa o agrupamento anterior e cria outro', async () => {
    const wrapper = mountMap([lead(1), lead(2)]);
    await flushPromises();
    const [first] = clusterers;

    await wrapper.setProps({ leads: [lead(3), lead(4), lead(5)] });
    await flushPromises();

    expect(first.clearMarkers).toHaveBeenCalled();
    expect(clusterers).toHaveLength(2);
    expect(clusterers[1].options.markers).toHaveLength(3);
    wrapper.unmount();
  });

  it('ao sair da tela limpa o agrupamento', async () => {
    const wrapper = mountMap([lead(1), lead(2)]);
    await flushPromises();

    wrapper.unmount();
    expect(clusterers[0].clearMarkers).toHaveBeenCalled();
  });
});
