import { mount } from '@vue/test-utils';
import DropdownMenu from '../DropdownMenu.vue';

// #1823: a etiqueta mostra o nome livre e também é achada pelo título técnico.
const ITENS = [
  { label: 'Aguardando retorno', searchText: 'aguardando_retorno', value: 1 },
  { label: 'Cliente VIP', searchText: 'vip', value: 2 },
  { label: 'Sem texto de busca', value: 3 },
];

const buscar = async termo => {
  const wrapper = mount(DropdownMenu, {
    props: { menuItems: ITENS, showSearch: true },
  });
  await wrapper.find('input[type="search"]').setValue(termo);
  return wrapper.findAll('button').map(botao => botao.text());
};

describe('DropdownMenu search', () => {
  it('finds an item by its label', async () => {
    expect(await buscar('cliente')).toEqual(['Cliente VIP']);
  });

  it('finds an item by its searchText', async () => {
    expect(await buscar('aguardando_')).toEqual(['Aguardando retorno']);
  });

  it('keeps label-only items working as before', async () => {
    expect(await buscar('sem texto')).toEqual(['Sem texto de busca']);
  });
});
