# B2 — revisão final limitada de estado, sessão e digest

**Data:** 2026-10-07  
**Alvo:** snapshot25 em `/Users/Shared/maccluster-workspaces/chat2you/20261007-190704-532a5b7b-42bf732f84-0ababeca/src`  
**SHA de conteúdo:** `42bf732f841c507e24baf8e134990355c504983159e447d9ec4834cc0c79e3f0`  
**Tipo:** revisão final única, independente e somente leitura.

## Escopo

Esta revisão fecha somente os contratos de estado privado, sessão do pedido, proveniência do polling,
digest efetivo de ferramentas nativas e normalização efetiva de silêncio, confiança e voz
(`B2-CODE-STATE-01` a `04`). A integração N1 de `ListProjection`, `Connection` e `Registry` não foi
reavaliada aqui.

## Resultado

**PASS limitado nesta fatia: não encontrei residual concreto em STATE/digest.**

O resultado dinâmico foi fornecido pelo coordenador do snapshot25; esta sessão não executou a bateria.
O recibo registra 222 exemplos Ruby, zero falhas, zero pendências e zero erros externos, além de 43/43
testes JavaScript. Isso confirma os casos usados como evidência, mas não fecha o lote B2 nem autoriza
F0, F1, merge, deploy ou produção.

## Evidências conferidas

- `InteractiveJob` revalida pedido e claim depois da operação; expiração observada ou falha de
  finalização mantém a sessão como `stale`, sem ressuscitar a chave. `AgentStateStore` exige a sessão
  atual e `completion=pending` sob lock antes de aceitar a conclusão.
- O polling passa a `session_id` do pedido ao `TestResultRecorder`. Divergência entre S1 e S2 retorna
  payload tipado `stale`, sem expor os digests da sessão atual.
- `TestDigest` usa o vetor efetivo da mesma `Tools::Registry` do runtime, ou o vetor pré-carregado da
  projeção, e persiste somente identidades públicas em hashes; URL, token e credenciais ficam fora do
  payload.
- Silêncio, confiança e voz passam pelos leitores reais (`Responder`, `Answerer` e `Config`). A
  representação equivalente mantém o digest; mudança efetiva altera o digest; texto privado não é
  serializado no resultado.

## Limites preservados

Ficam fora deste parecer:

1. orçamento e integração N1 da projeção, disponibilidade em lote, `Connection`, `Registry` e
   `ListProjection`;
2. enum de actuation, disponibilidade do Copilot, `RequestValidation` e contrato público de
   configuração;
3. notas privadas, Analytics, `Message.vue` e `PanelTune`;
4. demais contratos e runtime de B3;
5. desenho, implementação e aceite visual de F0/F1, incluindo telas reais;
6. lint geral, CI, merge, fila, deploy e produção.

## Receipts coordenados

- Ruby: job `m2-a7fa41c360314e39aede0f229e965d2f`, ticket
  `m4-d39daa02419c448eb097fa074ef7de4d`, 222 exemplos, zero falhas/pendências/externos. JSON
  `/tmp/chat2you-agentes-b2-b3-final25.json`, SHA-256
  `80a61547d2542afa66d36d59837c7138da33d4670645256bef83d462fa8ff10b`.
- JavaScript: job `m2-8d8297869c1f48ef82051dc043e2c811`, ticket
  `m4-759ce574b4d9422281098e87efd78c03`, 43/43. JSON
  `/tmp/chat2you-agentes-frontend-check25.json`, SHA-256
  `0fb7f86e8e5e0520d6f7fae49b259fa2aa5274ff0d5e03245ee438ac68d3ed85`.
- Lint geral: job `m2-4769cbba84b74f8395a8b24fce2987b9`, ticket
  `m4-5e1f2c45b4b84896b72880f035ec2ad2`, 106 arquivos e seis ofensas. JSON
  `/tmp/chat2you-agentes-lint25.json`, SHA-256
  `b2f024dbaf825044d092c3047065b1f9075001943753004a100e098fa6f6bb35`. As ofensas permanecem fora
  desta fatia e mantêm o lote geral bloqueado.

## Conclusão

O parecer é PASS somente para STATE/digest. Não há encerramento técnico geral do B2 e o STOP geral
permanece válido; nenhuma correção, nova execução ou promoção foi iniciada nesta etapa.
