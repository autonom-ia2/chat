import { mount } from '@vue/test-utils';
import {
  PRESETS,
  moduleByKey,
  setLevel,
} from '../../customRoles/permissionMatrix';
import ComoVaiFicar from '../guiada/ComoVaiFicar.vue';
import { global } from './montar';

// #2308, especificação 8: a prévia do Atendente, com "novo" só no Pode.
const ATENDENTE = PRESETS.AGENT();

const montar = permissions =>
  mount(ComoVaiFicar, {
    props: { nome: 'Atendente', permissions, inicial: ATENDENTE },
    global: global(),
  });

describe('ComoVaiFicar', () => {
  it('frase, Pode, Não pode e menu do Atendente', () => {
    const wrapper = montar(ATENDENTE);
    // Só a lista Pode/Não pode é anunciada; o resto da prévia não fala a cada toque.
    expect(
      wrapper.find('[data-previa]').attributes('aria-live')
    ).toBeUndefined();
    const aoVivo = wrapper.find('[data-ao-vivo]');
    expect(aoVivo.attributes('aria-live')).toBe('polite');
    expect(aoVivo.find('[data-pode]').exists()).toBe(true);
    expect(aoVivo.find('[data-nao-pode]').exists()).toBe(true);
    expect(aoVivo.find('[data-frase]').exists()).toBe(false);
    expect(wrapper.find('[data-frase]').text()).toBe(
      'Com a função Atendente, a pessoa atende as próprias conversas e pega as novas que estão sem ninguém. Cria e move as vendas em andamento. Só olha os contatos.'
    );
    expect(wrapper.findAll('[data-pode] li').map(li => li.text())).toEqual([
      'Responder as próprias conversas',
      'Pegar as conversas novas que estão sem ninguém',
      'Ajudar quando um colega manda o link da conversa',
      'Criar e mover as vendas em andamento',
    ]);
    expect(wrapper.findAll('[data-nao-pode] li').map(li => li.text())).toEqual([
      'Ler as conversas dos colegas',
      'Mudar os dados dos contatos',
      'Levar a lista de clientes para uma planilha',
    ]);
    expect(wrapper.find('[data-menu]').text()).toBe(
      'O menu vai mostrar: Conversas, Contatos e Vendas.'
    );
  });

  it('Relatórios entra no fim do Pode com "novo"; o Não pode não ganha marca', () => {
    const wrapper = montar(setLevel(moduleByKey('REPORTS'), 'view', ATENDENTE));
    const ultimo = wrapper.findAll('[data-pode] li').at(-1);
    expect(ultimo.text()).toContain('Ver os relatórios de atendimento');
    expect(ultimo.find('[data-novo]').text()).toBe('novo');
    expect(wrapper.find('[data-nao-pode] [data-novo]').exists()).toBe(false);
  });
});
