# Audit — recibo final limitado B2 de estado, sessão e digest

**Data:** 2026-10-07  
**Snapshot25:** `/Users/Shared/maccluster-workspaces/chat2you/20261007-190704-532a5b7b-42bf732f84-0ababeca/src`  
**SHA de conteúdo:** `42bf732f841c507e24baf8e134990355c504983159e447d9ec4834cc0c79e3f0`

## Escopo e resultado

Este recibo registra a revisão final independente limitada a `B2-CODE-STATE-01` a `04`: expiração e
sessão do pedido, identidade no polling, vetor nativo efetivo e normalização efetiva de silêncio,
confiança e voz. O resultado é **PASS limitado, sem residual concreto nesta fatia**.

Não foram reabertas a revisão normal, a integração N1 ou qualquer correção. O parecer não fecha B2,
F0, F1, B3, CI, merge, deploy ou produção.

## Provas registradas

O caminho assíncrono revalida pedido/claim e não ressuscita chave expirada; a conclusão privada exige a
mesma sessão sob lock. O polling usa a sessão do próprio pedido e retorna `stale` quando ela diverge.
O digest usa o vetor efetivo da Registry ou o vetor pré-carregado, sem credenciais no payload. Os
normalizadores reais de silêncio, confiança e voz são usados tanto pelo leitor quanto pelo digest.

## Receipts do snapshot25

- Ruby: `m2-a7fa41c360314e39aede0f229e965d2f`, ticket
  `m4-d39daa02419c448eb097fa074ef7de4d`, 222 exemplos, zero falhas/pendências/externos; JSON
  `/tmp/chat2you-agentes-b2-b3-final25.json`, SHA-256
  `80a61547d2542afa66d36d59837c7138da33d4670645256bef83d462fa8ff10b`.
- JavaScript: `m2-8d8297869c1f48ef82051dc043e2c811`, ticket
  `m4-759ce574b4d9422281098e87efd78c03`, 43/43; JSON
  `/tmp/chat2you-agentes-frontend-check25.json`, SHA-256
  `0fb7f86e8e5e0520d6f7fae49b259fa2aa5274ff0d5e03245ee438ac68d3ed85`.
- Lint geral: `m2-4769cbba84b74f8395a8b24fce2987b9`, ticket
  `m4-5e1f2c45b4b84896b72880f035ec2ad2`, seis ofensas em 106 arquivos; JSON
  `/tmp/chat2you-agentes-lint25.json`, SHA-256
  `b2f024dbaf825044d092c3047065b1f9075001943753004a100e098fa6f6bb35`.

Os seis resíduos de lint e as outras cinco fronteiras fora de STATE/digest permanecem pendentes em
seus owners. Este documento não os reclassifica nem os corrige.

## Limite operacional

Nenhum teste, lint, build, serviço, banco, produção, commit, push, PR, merge, fila ou deploy foi
executado por esta sessão. O STOP geral permanece ativo.
