import { mount } from '@vue/test-utils';
import {
  LEVELS,
  PRESETS,
  moduleByKey,
  setLevel,
} from '../../customRoles/permissionMatrix';
import { escolherNivelDeVendas } from '../nivelDeVendas';
import AjustesDaFuncao from '../guiada/AjustesDaFuncao.vue';
import { global } from './montar';
import { ADMIN } from './quemMonta';

// #2308, especificação 5.B2, 7.1 e 7.5: as linhas de Ajustes. A linha Cuidado lê o que a função dá de fato
// (metas sem R$ não valem no servidor); o "antes" fala no passado.
const montar = (permissions, inicial = permissions) =>
  mount(AjustesDaFuncao, {
    props: {
      titulo: 'Quer mudar alguma coisa?',
      dica: 'Dica',
      permissions,
      inicial,
      giver: ADMIN,
    },
    global: global(),
  });
const cuidado = wrapper => wrapper.find('[data-linha="cuidado"]').text();

describe('AjustesDaFuncao', () => {
  it('"Cuida de tudo" sem R$: a linha Cuidado não promete as metas', () => {
    const tudo = escolherNivelDeVendas('tudo', PRESETS.AGENT());
    expect(tudo).toContain('crm_metas_manage');
    const texto = cuidado(montar(tudo));
    expect(texto).toContain('Levar as vendas para uma planilha');
    expect(texto).not.toContain('metas');
  });

  it('controle: com os valores em R$, a linha Cuidado diz as metas', () => {
    const tudo = [
      ...escolherNivelDeVendas('tudo', PRESETS.AGENT()),
      'sales_value_view',
    ];
    expect(cuidado(montar(tudo))).toContain('metas');
  });

  it('crm_admin sem as seis gravadas: a linha Cuidado diz o que o servidor dá, como a prévia', () => {
    const legada = [...PRESETS.AGENT(), 'crm_admin'];
    expect(cuidado(montar(legada))).toContain(
      'Levar as vendas para uma planilha'
    );
  });

  it('o "antes" fala no passado nas linhas fixas', () => {
    const atendente = PRESETS.AGENT();
    const contatos = setLevel(
      moduleByKey('CONTACTS'),
      LEVELS.MANAGE,
      atendente
    );
    const semVendas = escolherNivelDeVendas(LEVELS.NONE, contatos);
    const wrapper = montar(semVendas, atendente);
    expect(wrapper.find('[data-linha="contatos"]').text()).toContain(
      '· antes: só olhava'
    );
    expect(wrapper.find('[data-linha="vendas"]').text()).toContain(
      '· antes: criava e movia as vendas'
    );
  });

  it('a recolhida nomeia até duas áreas no estado, em vez da conta', () => {
    const wrapper = montar([
      ...PRESETS.AGENT(),
      'desempenho_view',
      'campaign_view',
    ]);
    const texto = wrapper.find('[data-recolhida]').text();
    expect(texto).toContain('Só olha Desempenho da equipe e Campanhas');
    expect(texto).not.toContain('2 áreas');
  });

  // Os relatórios de atendimento contam como ver (Rodrigo, 28/10): com eles no nível de ver, a recolhida diz
  // "Só olha".
  it('a recolhida com os relatórios de atendimento diz "Só olha"', () => {
    const wrapper = montar([
      ...PRESETS.AGENT(),
      'report_manage',
      'campaign_view',
    ]);
    const texto = wrapper.find('[data-recolhida]').text();
    expect(texto).toContain('Só olha Relatórios e Campanhas');
    expect(texto).not.toContain('Vê Relatórios');
  });
});
