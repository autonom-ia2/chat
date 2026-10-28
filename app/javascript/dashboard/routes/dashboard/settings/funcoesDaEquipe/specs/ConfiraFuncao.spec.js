import { mount } from '@vue/test-utils';
import { PRESETS } from '../../customRoles/permissionMatrix';
import ConfiraFuncao from '../guiada/ConfiraFuncao.vue';
import { espiarDialogo, global, loja } from './montar';

// #2308, especificação 5.B4, 5.C e 10.4: a ordem do celular e o rodapé com o menu.
const montar = (props = {}, caixas = []) =>
  mount(ConfiraFuncao, {
    attachTo: document.body,
    props: {
      modo: 'criar',
      nome: 'Atendente 2',
      descricao: 'Quem atende o WhatsApp no dia a dia.',
      permissions: PRESETS.AGENT(),
      inicial: PRESETS.AGENT(),
      podeEscolherPessoas: true,
      ...props,
    },
    global: global(loja({ caixas })),
  });

afterEach(() => {
  document.body.innerHTML = '';
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

  it('"Ver os canais" abre a folha com os nomes dos canais da conta, sem sair da tela', async () => {
    const { mostrar, soltar } = espiarDialogo();
    const abrirAba = vi.spyOn(window, 'open');
    const wrapper = montar({}, [
      { id: 1, name: 'WhatsApp Loja' },
      { id: 2, name: 'Instagram' },
    ]);

    await wrapper.find('[data-ver-canais]').trigger('click');
    expect(mostrar).toHaveBeenCalledTimes(1);
    expect(abrirAba).not.toHaveBeenCalled();
    expect(wrapper.findAll('[data-canais] li').map(li => li.text())).toEqual([
      'WhatsApp Loja',
      'Instagram',
    ]);
    soltar();
    abrirAba.mockRestore();
  });

  it('o erro do nome é anunciado e ligado ao campo, inteiro, fora da dica', () => {
    const erroDoNome = 'Você já tem uma função Atendente 2. Dê outro nome.';
    const wrapper = montar({ erroDoNome });
    const erro = wrapper.find('[data-erro-nome]');
    expect(erro.attributes('role')).toBe('alert');
    expect(erro.text()).toBe(erroDoNome);
    const campo = wrapper.find('[data-formulario] input');
    expect(campo.attributes('aria-invalid')).toBe('true');
    expect(campo.attributes('aria-describedby')).toBe(erro.attributes('id'));
  });
});
