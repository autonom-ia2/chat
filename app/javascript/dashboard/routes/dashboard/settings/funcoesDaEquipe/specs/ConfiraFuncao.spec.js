import { mount } from '@vue/test-utils';
import { PRESETS } from '../../customRoles/permissionMatrix';
import ConfiraFuncao from '../guiada/ConfiraFuncao.vue';
import { global } from './montar';

// #2308, especificação 5.B4, 5.C e 10.4: a ordem do celular e o rodapé com o menu.
vi.mock('vue-router', () => ({
  useRouter: () => ({
    resolve: () => ({ href: '/app/accounts/1/settings/inboxes/list' }),
  }),
}));

const montar = (props = {}) =>
  mount(ConfiraFuncao, {
    props: {
      modo: 'criar',
      nome: 'Atendente 2',
      descricao: 'Quem atende o WhatsApp no dia a dia.',
      permissions: PRESETS.AGENT(),
      inicial: PRESETS.AGENT(),
      podeEscolherPessoas: true,
      ...props,
    },
    global: global(),
  });

const posicao = (wrapper, seletor) =>
  wrapper.html().indexOf(wrapper.find(seletor).element.outerHTML.slice(0, 40));

describe('ConfiraFuncao', () => {
  it('celular: o nome vem antes da prévia, e a prévia antes do formulário', () => {
    const wrapper = montar();
    expect(wrapper.find('[data-vai-se-chamar]').text()).toContain(
      'Vai se chamar Atendente 2'
    );
    const nome = posicao(wrapper, '[data-vai-se-chamar]');
    const previa = posicao(wrapper, '[data-previa-celular]');
    const formulario = posicao(wrapper, '[data-formulario]');
    expect(nome).toBeLessThan(previa);
    expect(previa).toBeLessThan(formulario);
  });

  it('rodapé fixo com o menu acima de "Salvar função"', () => {
    const wrapper = montar();
    expect(wrapper.find('[data-no-menu]').text()).toBe(
      'No menu: Conversas, Contatos, Vendas e Central de Ajuda'
    );
    expect(wrapper.find('[data-botao-grande]').text()).toBe('Salvar função');
    expect(wrapper.text()).toContain(
      'Depois de salvar, você escolhe quem vai ser Atendente 2.'
    );
  });

  it('a cópia avisa o que ficou de fora, com R$ e metas juntos', () => {
    const wrapper = montar({
      modo: 'duplicar',
      deFora: ['sales_value_view', 'crm_metas_manage'],
    });
    expect(wrapper.find('h1').text()).toBe('Confira a cópia');
    expect(wrapper.find('[data-aviso-copia]').text()).toBe(
      'Ficou de fora o que você não pode dar: ver os valores das vendas em R$ e, junto, as metas do mês.'
    );
  });

  it('o erro de salvar aparece como alerta; alterar salva "alterações"', () => {
    const wrapper = montar({
      modo: 'alterar',
      erro: 'Funções da equipe não estão disponíveis agora. Fale com o administrador.',
    });
    expect(wrapper.find('[data-erro-salvar]').attributes('role')).toBe('alert');
    expect(wrapper.find('[data-botao-grande]').text()).toBe(
      'Salvar alterações'
    );
  });
});
