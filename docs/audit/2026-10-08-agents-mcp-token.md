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
