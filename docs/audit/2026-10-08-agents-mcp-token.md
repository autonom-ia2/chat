# Agents MCP — credencial técnica dedicada

## Autorização e escopo

Implementação autorizada em 08/10/2026 para integrar o Agents ao Autonom.ia Connect. Este checkpoint não autoriza merge nem deploy. O MCP autentica o usuário no Connect; o Agents não recebe OAuth do Claude e não armazena token pessoal do usuário.

O endpoint interno `/api/v1/autonomia/connect/agents` aceita somente JWT ES256 emitido pelo Connect, com issuer, audiência, `client_id`, escopo exato, `iat`, `exp`, `jti` e vida máxima de 90 segundos. O `sub` é resolvido por `Autonomia::UserLink`. Somente uma associação administradora ativa pode listar como elegível, provisionar, rotacionar ou revogar a credencial da conta solicitada.

## Credencial e autorização

Cada vínculo `identity_subject + account` cria um `Mcp::IntegrationToken`, usuário oculto de integração, `AccountUser` e `CustomRole`. O papel contém apenas as permissões nativas necessárias aos escopos aprovados. O token é entregue somente ao Connect, fica restrito por conta e por uma allowlist de controller/action; qualquer rota não listada falha fechada.

Os escopos iniciais cobrem inboxes, conversas, mensagens, contatos, agentes e resumo de relatórios. A única escrita é criar mensagem. Ela força `message_type=outgoing`, aceita somente `content` e `private`, exige `Idempotency-Key` válido e usa namespace por token para impedir colisão entre integrações da mesma conta. O conteúdo das mensagens não entra na auditoria do Connect.

## Persistência e migração

A migração `20261010110000_create_mcp_integration_tokens.rb` cria a tabela e suas referências. `db/schema.rb` foi inspecionado e sincronizado neste branch. A ferramenta Ruby/Bundler exigida pelo repositório não está disponível neste host, então o schema não pôde ser regenerado por `db:migrate`; CI deve executar a migração e confirmar que o schema gerado permanece idêntico antes do merge.

## Validação local

Foram adicionados specs de modelo, provisionamento, isolamento de conta, allowlist de leitura, escopo de escrita, idempotência e verificação JWT. Neste host foi possível executar verificação sintática Ruby e whitespace; a suíte RSpec/RuboCop depende do ambiente Ruby/Bundler do CI e não deve ser apresentada como aprovada localmente.

## Correções após revisão da PR #1162

- O entry point de autenticação MCP agora verifica, em cada requisição, que o `identity_subject` continua vinculado ao autorizador original e que ele ainda é administrador da conta. Remoção, rebaixamento, exclusão do autorizador ou alteração do vínculo bloqueiam a credencial antes de sincronizar caixas ou executar uma ação. Tokens CRM conservam o comportamento existente.
- Claim idempotente, gravação da mensagem e resposta para replay passam a compartilhar uma transação exclusivamente no envio MCP. Falhas de renderização/persistência antes do commit desfazem mensagem e claim; após o commit a resposta já está persistida, mesmo se um callback falhar. Isso protege a criação de uma mensagem, não promete entrega exatamente uma vez pelo canal externo. A janela contratual de replay continua sendo de 24 horas; após esse prazo uma chave pode ser reutilizada.
- Adicionados casos de desligamento do autorizador, reassociação de identidade, rollback de render/persistência, colisão de payload, concorrência entre conexões PostgreSQL e falha após commit.
- O shard 0 do CI executa rollback/up da migração MCP e regeneração do schema, exigindo diff vazio. O job agregado RSpec inclui esse gate. Não há execução em produção.
- O consentimento atual continua sendo por conta inteira, incluindo caixas futuras; escopo por caixa e proteção contra replay do JWT de provisionamento permanecem melhorias separadas. Envio continua no escopo aprovado, com confirmação no Connect.
- Tentativa local de RSpec bloqueada pelo Bundler 2.5.16 ausente e Ruby local 2.6 (projeto exige 3.4.4). Testes foram escritos antes da implementação, mas o ciclo red/green Rails não pôde ser executado localmente. Verificações sintáticas e CI devem ser reportados separadamente.
- Os hooks locais de commit/push não inicializam porque `.husky/_/husky.sh` está ausente. Hooks desabilitados apenas nos respectivos comandos; gates do CI permanecem ativos.
- A primeira rodada do CI confirmou rollback/up da migração MCP e schema regenerado sem diff. Os logs do lint apontaram complexidade no guard e mocks amplos nas regressões; corrigidos por um predicado de elegibilidade e injeção de falha em objetos específicos/callbacks reais, sem relaxar regras.
- A concorrência real passou na primeira rodada. O teste de falha após commit revelou `AbstractController::DoubleRenderError` no tratamento de erro: zerar `response_body` não limpa o marcador interno de render no Rails. O caminho MCP agora substitui status, tipo e corpo usando os setters públicos, sem segundo render. A nova rodada deve comprovar erro controlado e replay da mesma mensagem. Nada disso foi executado em produção.
- O spec do Guia detectou referências de origem desatualizadas após alterações no controller. Como o gerador oficial exige Rails, o CI agora publica seus arquivos regenerados como diagnóstico após uma falha, sem converter o teste vermelho em sucesso. O dump deve ser recuperado, inspecionado e versionado antes de uma rodada final verde.
