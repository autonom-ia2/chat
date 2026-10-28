import {
  LEVELS,
  PRESETS,
  moduleByKey,
  setLevel,
} from '../../customRoles/permissionMatrix';
import { criarMemoria } from '../guiada/memoriaDaConversa';

// #2308, decisões 5 e 6: o que a conversa guiada lembra entre telas e entre níveis.
const contatos = moduleByKey('CONTACTS');

// Troca o nível de Contatos como a tela faz: setLevel e depois a memória.
const trocar = (memoria, de, para, permissions) =>
  memoria.trocarNivel(contatos, {
    de,
    para,
    permissions,
    novas: setLevel(contatos, para, permissions),
  });

describe('memória da conversa', () => {
  const comAjuste = [
    ...setLevel(contatos, LEVELS.MANAGE, PRESETS.AGENT()),
    'contact_export',
  ];

  it('passar por "Não vê" com as setas e voltar devolve os ajustes da área', () => {
    const memoria = criarMemoria();
    const semContatos = trocar(memoria, LEVELS.MANAGE, LEVELS.NONE, comAjuste);
    expect(semContatos).not.toContain('contact_export');

    const deVolta = trocar(memoria, LEVELS.NONE, LEVELS.MANAGE, semContatos);
    expect([...deVolta].sort()).toEqual([...comAjuste].sort());
  });

  it('uma visita nova esquece os níveis, mas não o "antes do Cuida de tudo" nem o que entrou junto', () => {
    const memoria = criarMemoria();
    trocar(memoria, LEVELS.MANAGE, LEVELS.NONE, comAjuste);
    memoria.guardarAntesDoTudo(PRESETS.SDR());
    memoria.guardarEntrouCom('crm_metas_manage', ['sales_value_view']);
    memoria.novaVisita();

    const semContatos = setLevel(contatos, LEVELS.NONE, comAjuste);
    expect(trocar(memoria, LEVELS.NONE, LEVELS.MANAGE, semContatos)).toEqual(
      setLevel(contatos, LEVELS.MANAGE, semContatos)
    );
    expect(memoria.antesDoTudo()).toEqual(PRESETS.SDR());
    expect(memoria.entrouCom('crm_metas_manage')).toEqual(['sales_value_view']);
  });

  it('recomeçar esquece tudo', () => {
    const memoria = criarMemoria();
    memoria.guardarAntesDoTudo(PRESETS.SDR());
    memoria.guardarEntrouCom('crm_metas_manage', ['sales_value_view']);
    memoria.recomecar();
    expect(memoria.antesDoTudo()).toBeNull();
    expect(memoria.entrouCom('crm_metas_manage')).toEqual([]);
  });
});
