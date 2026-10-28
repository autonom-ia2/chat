import { mount } from '@vue/test-utils';
import { PRESETS } from '../../customRoles/permissionMatrix';
import EfeitoSemFuncao from '../pessoas/EfeitoSemFuncao.vue';
import { global } from './montar';

// #2308, especificação 5.D e revisão do #2308: se o "Sem função" passar a ver R$, tirar alguém da função só MOSTRA o ganho (linha âmbar), não
// trava. O contrato aqui é um fixture com valores_das_vendas liberado e um id que a tela não conhece.
vi.mock('../semFuncaoCapacidades.json', () => ({
  default: {
    capacidades: [
      {
        id: 'contatos',
        chaves: ['contact_view', 'contact_manage'],
        premissas: [],
        pode: true,
      },
      {
        id: 'valores_das_vendas',
        chaves: ['sales_value_view'],
        premissas: [],
        pode: true,
      },
      {
        id: 'coisa_que_a_tela_nao_conhece',
        chaves: ['label_manage'],
        premissas: [],
        pode: false,
      },
    ],
    extras: [],
  },
}));

const montar = permissions =>
  mount(EfeitoSemFuncao, { props: { permissions }, global: global() });

describe('EfeitoSemFuncao', () => {
  it('o ganho de R$ aparece na frase, mesmo sem ser o primeiro', () => {
    const texto = montar(PRESETS.AGENT()).find('[data-efeito] p').text();
    expect(
      texto.startsWith('Sem função, passa a criar e mudar os contatos.')
    ).toBe(true);
    expect(texto).toContain('Também passa a ver os valores das vendas em R$.');
  });

  it('o id que a tela não conhece vira a frase genérica da área, nunca a chave crua', () => {
    const texto = montar(['label_manage']).find('[data-efeito] p').text();
    expect(texto).toContain('Deixa de fazer uma coisa em Etiquetas.');
    expect(texto).not.toContain('coisa_que_a_tela_nao_conhece');
  });

  // Rodada 3: frase corrida, com artigo e sem dois-pontos; Relatórios pesam mais que a Central de Ajuda.
  it('a área perdida entra na frase com artigo, e os Relatórios vêm antes da Central de Ajuda', () => {
    const texto = montar(['knowledge_base_view', 'report_manage'])
      .find('[data-efeito] p')
      .text();
    expect(texto).toContain('Deixa de ver os Relatórios.');
    expect(texto).not.toContain(':');
  });

  // Rodada 4: a lista "Vai deixar de" fala como a Perda de acesso ("Ver os Relatórios", sem dois-pontos), e a área que
  // o sem função ainda usa diz que só uma parte sai.
  it('na lista, as áreas vão com artigo e sem dois-pontos, e a parte que sai não parece a área inteira', async () => {
    const deixam = async permissions => {
      const wrapper = montar(permissions);
      await wrapper.find('[data-ver-tudo]').trigger('click');
      return wrapper
        .findAll('[data-grupo="DEIXAM"] [data-item]')
        .map(item => item.text());
    };
    expect(await deixam(['knowledge_base_view', 'report_manage'])).toEqual([
      'Ver a Central de Ajuda (artigos para os clientes)',
      'Ver os Relatórios',
    ]);
    expect(await deixam(['label_manage', 'macro_manage'])).toContain(
      'Mudar os Atalhos de mensagens'
    );
    expect(await deixam(['crm_manage_pipelines'])).toEqual([
      'Parte do que fazia em Vendas',
    ]);
  });
});
