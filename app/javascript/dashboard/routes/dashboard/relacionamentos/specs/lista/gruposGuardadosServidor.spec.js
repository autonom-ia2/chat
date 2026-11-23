import CustomViewsAPI from 'dashboard/api/customViews';
import { gruposGuardadosFonte } from '../../fonte/gruposGuardados';
import { FILTROS_VAZIOS } from '../../lista/filtros';

// #3168 — fora da demonstração, "Meus grupos" são os custom_filters de contato
// da pessoa da equipe: o `relacionamentos` da query é o que a lista reaplica, e
// o `payload` (as linhas de "Por outra informação") a tela antiga ainda lê.
vi.mock('dashboard/api/customViews', () => ({
  default: {
    getCustomViewsByFilterType: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    deleteCustomViews: vi.fn(),
  },
}));

const condicao = {
  id: 1,
  chave: 'email',
  tipo: 'texto',
  modelo: 'standard',
  como: 'contains',
  valor: ' exemplo.com ',
};
const grupo = {
  nome: 'Clientes de Campinas',
  visao: 'conversa',
  grupo: 'clientes',
  busca: '',
  filtros: { ...FILTROS_VAZIOS, cidade: 'Campinas', condicoes: [condicao] },
};
const doServidor = (id, query) => ({ id, name: grupo.nome, query });

describe('gruposGuardadosFonte fora da demonstração', () => {
  const fonte = gruposGuardadosFonte();

  beforeEach(() => vi.clearAllMocks());

  it('lista só os de contato que esta lista guardou, com id em texto', async () => {
    CustomViewsAPI.getCustomViewsByFilterType.mockResolvedValue({
      data: [
        doServidor(7, { relacionamentos: grupo }),
        doServidor(8, { payload: [] }),
      ],
    });

    const lista = await fonte.listar();

    expect(CustomViewsAPI.getCustomViewsByFilterType).toHaveBeenCalledWith(
      'contact'
    );
    expect(lista).toEqual([{ id: '7', ...grupo }]);
  });

  it('guarda o que a pessoa via e as linhas no formato de contacts/filter', async () => {
    CustomViewsAPI.create.mockImplementation(async corpo => ({
      data: doServidor(9, corpo.custom_filter.query),
    }));

    const novo = await fonte.criar(grupo);
    const corpo = CustomViewsAPI.create.mock.calls[0][0].custom_filter;

    expect(corpo.filter_type).toBe('contact');
    expect(corpo.name).toBe('Clientes de Campinas');
    expect(corpo.query.relacionamentos).toEqual({
      visao: 'conversa',
      grupo: 'clientes',
      busca: '',
      filtros: grupo.filtros,
    });
    expect(corpo.query.payload).toEqual([
      expect.objectContaining({
        attribute_key: 'email',
        filter_operator: 'contains',
        values: ['exemplo.com'],
      }),
    ]);
    expect(novo.id).toBe('9');
  });

  it('mudar manda o grupo inteiro e apagar usa o tipo de contato', async () => {
    CustomViewsAPI.update.mockImplementation(async (id, corpo) => ({
      data: doServidor(Number(id), corpo.custom_filter.query),
    }));

    await fonte.mudar('7', { ...grupo, nome: 'Outro nome' });
    await fonte.apagar('7');

    expect(CustomViewsAPI.update.mock.calls[0][0]).toBe('7');
    expect(CustomViewsAPI.update.mock.calls[0][1].custom_filter.name).toBe(
      'Outro nome'
    );
    expect(CustomViewsAPI.deleteCustomViews).toHaveBeenCalledWith(
      '7',
      'contact'
    );
  });
});
