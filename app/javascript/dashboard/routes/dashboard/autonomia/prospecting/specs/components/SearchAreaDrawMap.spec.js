/* eslint-disable max-classes-per-file -- dublês das formas do Google Maps */
// Desenho da área no mapa do formulário (#678, E2 frente B): círculo, retângulo
// e polígono com as formas editáveis do núcleo do Google Maps. Nada da
// biblioteca drawing (DrawingManager), que o Google retirou em maio de 2026.
import { flushPromises, mount } from '@vue/test-utils';
import SearchAreaDrawMap from '../../components/search/SearchAreaDrawMap.vue';

const CENTER = { lat: -25.43, lng: -49.27 };

const latLng = (lat, lng) => ({ lat: () => lat, lng: () => lng });

class Listening {
  constructor() {
    this.listeners = {};
  }

  addListener(event, handler) {
    this.listeners[event] = handler;
    return { remove: () => delete this.listeners[event] };
  }

  fire(event, payload) {
    this.listeners[event]?.(payload);
  }
}

const created = { map: null, circles: [], rectangles: [], polygons: [] };

class FakeMap extends Listening {
  constructor(element, options) {
    super();
    this.options = options;
    created.map = this;
  }

  panTo(center) {
    this.center = center;
  }
}

class FakeCircle extends Listening {
  constructor(options) {
    super();
    this.options = options;
    this.center = options.center;
    this.radius = options.radius;
    this.map = options.map;
    created.circles.push(this);
  }

  getCenter() {
    return latLng(this.center.lat, this.center.lng);
  }

  getRadius() {
    return this.radius;
  }

  setMap(map) {
    this.map = map;
  }
}

class FakeRectangle extends Listening {
  constructor(options) {
    super();
    this.options = options;
    this.bounds = options.bounds;
    this.map = options.map;
    created.rectangles.push(this);
  }

  getBounds() {
    return {
      getNorthEast: () => latLng(this.bounds.north, this.bounds.east),
      getSouthWest: () => latLng(this.bounds.south, this.bounds.west),
    };
  }

  setMap(map) {
    this.map = map;
  }
}

class FakePath extends Listening {
  constructor(points) {
    super();
    this.points = points.map(point => latLng(point.lat, point.lng));
  }

  getLength() {
    return this.points.length;
  }

  getAt(index) {
    return this.points[index];
  }

  push(point) {
    this.points.push(point);
    this.fire('insert_at', this.points.length - 1);
  }

  pop() {
    const point = this.points.pop();
    this.fire('remove_at', this.points.length);
    return point;
  }
}

class FakePolygon extends Listening {
  constructor(options) {
    super();
    this.options = options;
    this.path = new FakePath(options.paths);
    this.map = options.map;
    created.polygons.push(this);
  }

  getPath() {
    return this.path;
  }

  setMap(map) {
    this.map = map;
  }
}

const mountDrawMap = async (props = {}) => {
  const wrapper = mount(SearchAreaDrawMap, {
    props: {
      apiKey: 'chave-navegador',
      center: CENTER,
      shape: 'circle',
      defaultRadius: 2000,
      modelValue: null,
      ...props,
    },
  });
  await flushPromises();
  return wrapper;
};

const clickMap = async (lat, lng) => {
  created.map.fire('click', { latLng: latLng(lat, lng) });
  await flushPromises();
};

const lastEmitted = wrapper => {
  const events = wrapper.emitted('update:modelValue') || [];
  return events[events.length - 1]?.[0];
};

const buttonWithText = (wrapper, text) =>
  wrapper.findAll('button').find(button => button.text().trim() === text);

describe('SearchAreaDrawMap', () => {
  beforeEach(() => {
    created.map = null;
    created.circles = [];
    created.rectangles = [];
    created.polygons = [];
    window.google = {
      maps: {
        Map: FakeMap,
        Circle: FakeCircle,
        Rectangle: FakeRectangle,
        Polygon: FakePolygon,
      },
    };
  });

  afterEach(() => {
    delete window.google;
  });

  it('abre o mapa no local escolhido, com rótulo acessível e sem a biblioteca drawing', async () => {
    const wrapper = await mountDrawMap();

    expect(created.map.options.center).toEqual(CENTER);
    expect(
      wrapper
        .find('[aria-label="PROSPECTING.SEARCH.AREA_DRAW.MAP_LABEL"]')
        .exists()
    ).toBe(true);
    expect(window.google.maps.drawing).toBeUndefined();
    expect(wrapper.text()).toContain(
      'PROSPECTING.SEARCH.AREA_DRAW.HINT_CIRCLE'
    );
    expect(wrapper.text()).toContain('PROSPECTING.SEARCH.AREA_DRAW.PENDING');
  });

  it('círculo: o clique põe o centro com o raio padrão, editável, e editar o raio atualiza a área', async () => {
    const wrapper = await mountDrawMap();

    await clickMap(-25.4, -49.2);

    const [circle] = created.circles;
    expect(circle.options).toMatchObject({ editable: true, draggable: true });
    expect(lastEmitted(wrapper)).toEqual({
      type: 'circle',
      config: { center: { lat: -25.4, lng: -49.2 }, radius: 2000 },
    });

    circle.radius = 3456.7;
    circle.fire('radius_changed');
    await flushPromises();
    expect(lastEmitted(wrapper).config.radius).toBe(3457);

    await clickMap(-25.5, -49.3);
    expect(created.circles).toHaveLength(1);
  });

  it('retângulo: o clique cria um retângulo editável em volta do ponto e ajustar os cantos atualiza a área', async () => {
    const wrapper = await mountDrawMap({ shape: 'rectangle' });

    await clickMap(-25.4, -49.2);

    const [rectangle] = created.rectangles;
    expect(rectangle.options).toMatchObject({
      editable: true,
      draggable: true,
    });
    const { bounds } = lastEmitted(wrapper).config;
    expect(lastEmitted(wrapper).type).toBe('rectangle');
    expect(bounds.north).toBeGreaterThan(-25.4);
    expect(bounds.south).toBeLessThan(-25.4);
    expect(bounds.east).toBeGreaterThan(-49.2);
    expect(bounds.west).toBeLessThan(-49.2);

    rectangle.bounds = { north: -25.1, south: -25.6, east: -49.1, west: -49.4 };
    rectangle.fire('bounds_changed');
    await flushPromises();
    expect(lastEmitted(wrapper)).toEqual({
      type: 'rectangle',
      config: {
        bounds: { north: -25.1, south: -25.6, east: -49.1, west: -49.4 },
      },
    });
  });

  it('polígono: cada clique marca um ponto e a área só vale com três', async () => {
    const wrapper = await mountDrawMap({ shape: 'polygon' });

    await clickMap(-25.5, -49.3);
    await clickMap(-25.5, -49.2);
    expect(created.polygons).toHaveLength(1);
    expect(created.polygons[0].options).toMatchObject({ editable: true });
    expect(lastEmitted(wrapper)).toBeNull();
    expect(wrapper.text()).toContain('PROSPECTING.SEARCH.AREA_DRAW.POINTS');

    await clickMap(-25.4, -49.25);
    expect(lastEmitted(wrapper)).toEqual({
      type: 'polygon',
      config: {
        path: [
          { lat: -25.5, lng: -49.3 },
          { lat: -25.5, lng: -49.2 },
          { lat: -25.4, lng: -49.25 },
        ],
      },
    });

    await buttonWithText(
      wrapper,
      'PROSPECTING.SEARCH.AREA_DRAW.UNDO_POINT'
    ).trigger('click');
    expect(lastEmitted(wrapper)).toBeNull();
    expect(created.polygons[0].getPath().getLength()).toBe(2);
  });

  it('limpar tira a forma do mapa e esvazia a área', async () => {
    const wrapper = await mountDrawMap();
    await clickMap(-25.4, -49.2);

    await buttonWithText(wrapper, 'PROSPECTING.SEARCH.AREA_DRAW.CLEAR').trigger(
      'click'
    );

    expect(created.circles[0].map).toBeNull();
    expect(lastEmitted(wrapper)).toBeNull();
  });

  it('trocar a forma apaga o desenho anterior', async () => {
    const wrapper = await mountDrawMap();
    await clickMap(-25.4, -49.2);

    await wrapper.setProps({ shape: 'polygon' });
    await flushPromises();

    expect(created.circles[0].map).toBeNull();
    expect(lastEmitted(wrapper)).toBeNull();
    expect(wrapper.text()).toContain(
      'PROSPECTING.SEARCH.AREA_DRAW.HINT_POLYGON'
    );
  });

  it('mostra que a área está pronta quando recebe uma área do mesmo tipo', async () => {
    const wrapper = await mountDrawMap({
      modelValue: {
        type: 'circle',
        config: { center: CENTER, radius: 1000 },
      },
    });

    expect(wrapper.text()).toContain('PROSPECTING.SEARCH.AREA_DRAW.READY');
  });

  it('sem chave de navegador avisa em vez de abrir o mapa', async () => {
    const wrapper = await mountDrawMap({ apiKey: '' });

    expect(created.map).toBeNull();
    expect(wrapper.text()).toContain('PROSPECTING.SEARCH.MAP_API_KEY_MISSING');
  });
});
