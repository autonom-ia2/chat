import { describe, it, expect } from 'vitest';
import auditLogs from '../locale/pt_BR/auditLogs.json';
import teamsSettings from '../locale/pt_BR/teamsSettings.json';
import settings from '../locale/pt_BR/settings.json';
import inboxMgmt from '../locale/pt_BR/inboxMgmt.json';

// Traduções do Crowdin que diziam outra coisa (#1618). O upstream ainda tem o
// texto errado; o fork corrige o valor pt_BR no próprio catálogo, como já faz
// em outras chaves do Chatwoot. Se uma atualização do upstream trouxer o texto
// antigo de volta, este teste avisa.
describe('pt_BR: textos que não batiam com a tela', () => {
  it('Auditoria: colunas de atividade e horário', () => {
    expect(auditLogs.AUDIT_LOGS.LIST.TABLE_HEADER).toMatchObject({
      ACTIVITY: 'Atividade',
      TIME: 'Horário',
    });
  });

  it('Times: o fim da criação fala do time, não da caixa de entrada', () => {
    expect(teamsSettings.TEAMS_SETTINGS.FINISH.TITLE).toBe(
      'Seu time está pronto!'
    );
  });

  it('Atribuição: "Earliest created" atende a mais antiga primeiro', () => {
    expect(
      settings.ASSIGNMENT_POLICY.AGENT_ASSIGNMENT_POLICY.FORM
        .ASSIGNMENT_PRIORITY.EARLIEST_CREATED.LABEL
    ).toBe('Mais antiga primeiro');
    expect(inboxMgmt.INBOX_MGMT.ASSIGNMENT.PRIORITY.EARLIEST_CREATED).toBe(
      'Mais antiga primeiro'
    );
  });
});
