import { mapHrefOf, pointOf } from '../mapLink.js';

const LINK = 'https://maps.google.com/?q=';

// Os mesmos pares e links estão em spec/services/rich_messages/types/location_spec.rb: bolha e texto saem iguais.
describe('mapHrefOf', () => {
  it.each([
    [5e-324, 5e-101, `${LINK}0.${'0'.repeat(323)}5,0.${'0'.repeat(100)}5`],
    [1e-7, -1e-7, `${LINK}0.0000001,-0.0000001`],
    [1.2345e-7, -23.5489, `${LINK}0.00000012345,-23.5489`],
    [-0, -90, `${LINK}0.0,-90.0`],
    [90, -180, `${LINK}90.0,-180.0`],
    [-90, 180, `${LINK}-90.0,180.0`],
  ])(
    'escreve %s, %s em notação decimal, sem notação científica',
    (latitude, longitude, href) => {
      expect(mapHrefOf(latitude, longitude)).toBe(href);
    }
  );

  it.each([
    ['latitude em texto', '-23.5', 1],
    ['latitude acima de 90', 90.0001, 1],
    ['longitude abaixo de -180', 1, -180.0001],
    ['coordenada ausente', 1, undefined],
    ['coordenada infinita', Infinity, 1],
    ['coordenada que não é número', Number.NaN, 1],
  ])('não cria link com %s', (_titulo, latitude, longitude) => {
    expect(mapHrefOf(latitude, longitude)).toBe('');
  });
});

describe('pointOf', () => {
  it('devolve "lat,long" validado, ou vazio', () => {
    expect(pointOf(-23.5613, -46.6565)).toBe('-23.5613,-46.6565');
    expect(pointOf('-23.5', 1)).toBe('');
  });
});
