import {
  CONVERSATION_LEVELS,
  LEVELS,
  PRESETS,
  moduleByKey,
  setLevel,
  toggleExtra,
} from '../../customRoles/permissionMatrix';
import { escolherNivelDeVendas } from '../nivelDeVendas';
import { criarMemoria } from '../guiada/memoriaDaConversa';

// #2308: o que a conversa guiada lembra entre telas e entre níveis (rodada 3: só volta o que a troca tirou).
const contatos = moduleByKey('CONTACTS');
const vendas = moduleByKey('CRM');
const procurar = moduleByKey('PROSPECTING');
const conversas = moduleByKey('CONVERSATIONS');

// Troca o nível como a tela faz: o nível escolhido e depois a memória.
const trocar = (memoria, module, para, permissions) =>
  memoria.trocarNivel(module, {
    permissions,
    nivelar: chaves => setLevel(module, para, chaves),
  });
const trocarVendas = (memoria, para, permissions) =>
  memoria.trocarNivel(vendas, {
    permissions,
    nivelar: chaves => escolherNivelDeVendas(para, chaves),
  });
const ordenado = lista => [...lista].sort();

describe('memória da conversa', () => {
  const comAjuste = [
    ...setLevel(contatos, LEVELS.MANAGE, PRESETS.AGENT()),
    'contact_export',
    'contact_delete',
  ];

  it('passar por "Não vê" com as setas e voltar devolve os ajustes da área', () => {
    const memoria = criarMemoria();
    const semContatos = trocar(memoria, contatos, LEVELS.NONE, comAjuste);
    expect(semContatos).not.toContain('contact_export');

    const deVolta = trocar(memoria, contatos, LEVELS.MANAGE, semContatos);
    expect(ordenado(deVolta)).toEqual(ordenado(comAjuste));
  });

  it('o que é só de quem mexe espera em "Só olha" e volta em "Pode mexer"', () => {
    const memoria = criarMemoria();
    const soOlha = trocar(memoria, contatos, LEVELS.NONE, comAjuste);
    const vendo = trocar(memoria, contatos, LEVELS.VIEW, soOlha);
    expect(vendo).toContain('contact_export');
    expect(vendo).not.toContain('contact_delete');

    const mexendo = trocar(memoria, contatos, LEVELS.MANAGE, vendo);
    expect(ordenado(mexendo)).toEqual(ordenado(comAjuste));
  });

  it('o R$ desligado à mão em "Só olha" continua desligado ao voltar para "Pode mexer"', () => {
    const memoria = criarMemoria();
    const comValores = [
      ...escolherNivelDeVendas(LEVELS.MANAGE, PRESETS.AGENT()),
      'sales_value_view',
    ];
    const soOlha = trocarVendas(memoria, LEVELS.VIEW, comValores);
    expect(soOlha).toContain('sales_value_view');
    const semValores = toggleExtra(vendas, 'sales_value_view', soOlha);

    const deVolta = trocarVendas(memoria, LEVELS.MANAGE, semValores);
    expect(deVolta).not.toContain('sales_value_view');
    expect(deVolta).toContain('crm_manage_cards');
  });

  it('os relatórios ligados em "Só olha" continuam ligados em "Pode mexer"', () => {
    const memoria = criarMemoria();
    const mexendo = escolherNivelDeVendas(LEVELS.MANAGE, PRESETS.AGENT());
    const soOlha = trocarVendas(memoria, LEVELS.VIEW, mexendo);
    const comRelatorios = toggleExtra(vendas, 'crm_view_reports', soOlha);

    const deVolta = trocarVendas(memoria, LEVELS.MANAGE, comRelatorios);
    expect(deVolta).toContain('crm_view_reports');
  });

  it('arquivar some em "Só olha" e volta em "Pode mexer"; mover não fica em "Só olha"', () => {
    const memoria = criarMemoria();
    const mexendo = [
      ...escolherNivelDeVendas(LEVELS.MANAGE, PRESETS.AGENT()),
      'crm_delete_cards',
    ];
    const soOlha = trocarVendas(memoria, LEVELS.VIEW, mexendo);
    expect(soOlha).not.toContain('crm_delete_cards');
    expect(soOlha).not.toContain('crm_move_cards');

    const deVolta = trocarVendas(memoria, LEVELS.MANAGE, soOlha);
    expect(deVolta).toContain('crm_delete_cards');
  });

  it('PROSPECTING: "todas as buscas" desligado em "Só olha" não volta', () => {
    const memoria = criarMemoria();
    const mexendo = [
      ...setLevel(procurar, LEVELS.MANAGE, PRESETS.AGENT()),
      'prospecting_view_all_searches',
    ];
    const soOlha = trocar(memoria, procurar, LEVELS.VIEW, mexendo);
    const semTodas = toggleExtra(
      procurar,
      'prospecting_view_all_searches',
      soOlha
    );
    expect(trocar(memoria, procurar, LEVELS.MANAGE, semTodas)).not.toContain(
      'prospecting_view_all_searches'
    );

    const outra = criarMemoria();
    const semArea = trocar(outra, procurar, LEVELS.NONE, mexendo);
    expect(trocar(outra, procurar, LEVELS.MANAGE, semArea)).toContain(
      'prospecting_view_all_searches'
    );
  });

  it('Conversas: passar por "Só olha" e voltar devolve os alcances e o apagar mensagens', () => {
    const memoria = criarMemoria();
    const atendendo = [
      ...PRESETS.AGENT().filter(chave => !chave.startsWith('conversation_')),
      'conversation_unassigned_manage',
      'conversation_participating_manage',
      'conversation_view',
      'conversation_message_delete',
    ];
    const soOlha = trocar(
      memoria,
      conversas,
      CONVERSATION_LEVELS.VIEW,
      atendendo
    );
    expect(soOlha).not.toContain('conversation_message_delete');

    const deVolta = trocar(
      memoria,
      conversas,
      CONVERSATION_LEVELS.LIMITED,
      soOlha
    );
    expect(ordenado(deVolta)).toEqual(ordenado(atendendo));
  });

  it('Conversas: ir para "Atende todas" e voltar tira o alcance que só "Atende todas" pôs', () => {
    const memoria = criarMemoria();
    const proprias = ['conversation_participating_manage'];
    const todas = trocar(memoria, conversas, CONVERSATION_LEVELS.ALL, proprias);
    expect(todas).toContain('conversation_unassigned_manage');
    expect(
      trocar(memoria, conversas, CONVERSATION_LEVELS.LIMITED, todas)
    ).toEqual(proprias);
  });

  it('não devolve o que já voltou por outro caminho', () => {
    const memoria = criarMemoria();
    const semContatos = trocar(memoria, contatos, LEVELS.NONE, comAjuste);
    const mexendo = trocar(memoria, contatos, LEVELS.MANAGE, semContatos);
    const outraVez = trocar(memoria, contatos, LEVELS.MANAGE, mexendo);
    expect(ordenado(outraVez)).toEqual(ordenado(comAjuste));
  });

  it('uma visita nova esquece os níveis, mas não o "antes do Cuida de tudo"', () => {
    const memoria = criarMemoria();
    const semContatos = trocar(memoria, contatos, LEVELS.NONE, comAjuste);
    memoria.guardarAntesDoTudo(PRESETS.SDR());
    memoria.novaVisita();

    expect(trocar(memoria, contatos, LEVELS.MANAGE, semContatos)).toEqual(
      setLevel(contatos, LEVELS.MANAGE, semContatos)
    );
    expect(memoria.antesDoTudo()).toEqual(PRESETS.SDR());
  });

  it('recomeçar esquece tudo', () => {
    const memoria = criarMemoria();
    memoria.guardarAntesDoTudo(PRESETS.SDR());
    memoria.recomecar();
    expect(memoria.antesDoTudo()).toBeNull();
  });
});
