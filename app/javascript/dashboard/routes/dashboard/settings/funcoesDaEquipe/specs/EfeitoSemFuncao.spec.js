import { defineComponent } from 'vue';
import { mount } from '@vue/test-utils';
import { PRESETS } from '../../customRoles/permissionMatrix';
import EfeitoSemFuncao from '../pessoas/EfeitoSemFuncao.vue';
import { useSemFuncao } from '../useSemFuncao';
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

  // Rodada 3: frase corrida, com artigo e sem dois-pontos; Relatórios pesam mais que as Campanhas (a Central de Ajuda,
  // exemplo de antes, saiu das telas de função no #2352).
  it('a área perdida entra na frase com artigo, e os Relatórios vêm antes das Campanhas', () => {
    const texto = montar(['campaign_view', 'report_manage'])
      .find('[data-efeito] p')
      .text();
    expect(texto).toContain('Deixa de ver os relatórios.');
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
    expect(await deixam(['campaign_view', 'report_manage'])).toEqual([
      'Ver os relatórios',
      'Ver as campanhas',
    ]);
    expect(await deixam(['label_manage', 'macro_manage'])).toContain(
      'Mudar os atalhos de mensagens'
    );
    // Rodada 5: "Vão deixar de" fecha a frase ("fazer algumas coisas em Vendas").
    expect(await deixam(['crm_manage_pipelines'])).toEqual([
      'Fazer algumas coisas em Vendas',
    ]);
  });

  it('a parte que sai da área também fecha a frase curta da linha', () => {
    const texto = montar(['crm_view', 'crm_manage_pipelines'])
      .find('[data-efeito] p')
      .text();
    expect(texto).toContain('Deixa de fazer algumas coisas em Vendas.');
  });
});

// Rodada 5: a frase da linha e a do rodapé da gaveta saem da mesma `forma`, e o efeito traz o diff inteiro (o "Ver tudo"
// não calcula de novo).
describe('useSemFuncao › efeitoDe', () => {
  const comSemFuncao = () => {
    let api;
    const wrapper = mount(
      defineComponent({
        setup() {
          api = useSemFuncao();
          return () => null;
        },
      }),
      { global: global() }
    );
    return { api, wrapper };
  };

  it('diz a forma da frase e traz o diff de uma vez', () => {
    const { api, wrapper } = comSemFuncao();
    const efeito = api.efeitoDe(['label_manage']);
    expect(efeito.forma).toBe('ganhoEPerda');
    expect(efeito.ganha).toEqual(api.diff(['label_manage']).ganha);
    expect(efeito.perde).toEqual(api.diff(['label_manage']).perde);
    expect(api.efeitoDe(['contact_view', 'contact_manage']).forma).toBe(
      'ganho'
    );
    expect(api).not.toHaveProperty('curtoDa');
    wrapper.unmount();
  });
});
