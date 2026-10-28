import ptBR from 'dashboard/i18n/locale/pt_BR/funcoesDaEquipe.json';
import en from 'dashboard/i18n/locale/en/funcoesDaEquipe.json';
import { PRESETS } from '../../customRoles/permissionMatrix';
import { capacidadesSemFuncao, diffEntre } from '../semFuncao';
import contrato from '../semFuncaoCapacidades.json';

// #2308, especificação 5.E, 7.9 e 14: o diff "Vão passar a poder / Vão deixar de" sai do contrato gerado das
// policies, nunca de uma lista por função; os relatórios das vendas seguem a flag crm_numeros_lentes da conta.
const LENTES = 'crm_numeros_lentes';
const desligada = () => false;
const ligada = flag => flag === LENTES;

describe('semFuncao', () => {
  it('com crm_numeros_lentes desligada, quem fica sem função passa a ver os relatórios das vendas', () => {
    expect(diffEntre(PRESETS.SDR(), desligada)).toEqual({
      ganha: [
        'conversas_dos_colegas',
        'respostas_prontas',
        'apagar_mensagens',
        'arquivar_vendas',
        'relatorios_das_vendas',
      ],
      perde: ['procurar_clientes_novos'],
    });
  });

  it('com crm_numeros_lentes ligada, não ganha os relatórios, e quem tinha perde', () => {
    expect(diffEntre(PRESETS.SDR(), ligada)).toEqual({
      ganha: [
        'conversas_dos_colegas',
        'respostas_prontas',
        'apagar_mensagens',
        'arquivar_vendas',
      ],
      perde: ['procurar_clientes_novos'],
    });
    expect(diffEntre(PRESETS.SUPERVISOR(), ligada).perde).toEqual([
      'relatorios_das_vendas',
    ]);
    expect(diffEntre(PRESETS.SUPERVISOR(), desligada).perde).toEqual([]);
  });

  it('quem só olha os contatos ganha mudar os contatos; quem leva planilha perde', () => {
    const { ganha } = diffEntre(PRESETS.AGENT(), desligada);
    expect(ganha).toContain('contatos');
    expect(diffEntre(PRESETS.MARKETING(), desligada).perde).toContain(
      'planilha_de_clientes'
    );
  });

  it('a chave implicada conta: crm_manage_cards traz crm_view', () => {
    const { ganha } = diffEntre(
      ['crm_manage_cards', 'crm_move_cards'],
      desligada
    );
    expect(ganha).not.toContain('vendas_das_colunas');
  });

  it('as capacidades seguem o contrato, na ordem dele, com a flag resolvida', () => {
    const ids = contrato.capacidades.map(item => item.id);
    expect(capacidadesSemFuncao(desligada).map(item => item.id)).toEqual(ids);
    const relatorios = id =>
      capacidadesSemFuncao(id).find(
        item => item.id === 'relatorios_das_vendas'
      );
    expect(relatorios(desligada).pode).toBe(true);
    expect(relatorios(ligada).pode).toBe(false);
  });

  it('cada capacidade do contrato tem texto em en e pt_BR', () => {
    contrato.capacidades.forEach(({ id }) => {
      [ptBR, en].forEach(catalogo => {
        expect(catalogo.FUNCOES_EQUIPE.SEM_FUNCAO[id].LISTA).toBeTruthy();
        expect(catalogo.FUNCOES_EQUIPE.SEM_FUNCAO[id].CURTO).toBeTruthy();
      });
    });
  });
});
