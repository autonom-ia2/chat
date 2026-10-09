# B3/BE-05 — recibo da checagem limitada do PanelTune

**Data:** 2026-10-07  
**Alvo:** snapshot25 `/Users/Shared/maccluster-workspaces/chat2you/20261007-190704-532a5b7b-42bf732f84-0ababeca/src`  
**SHA:** `42bf732f841c507e24baf8e134990355c504983159e447d9ec4834cc0c79e3f0`  
**Escopo:** primeira checagem limitada da correção do P1 de BE-05 no `PanelTune`.

## Causa anterior

Na revisão normal do snapshot23, o botão de retomada ainda executava `RESET`, abria a gaveta vazia e deixava o primeiro envio cair em `start`. O consumidor real não usava a nova ação `resume`, embora API e store já existissem. A causa e o efeito estão registrados em `docs/audit/2026-10-07-agentes-b3-codigo-causa-raiz.md`.

## Correção conferida

O snapshot25 faz a migração somente quando a flag do redesign está ligada: `PanelTune` aguarda `resume` antes de abrir e envia na thread hidratada. Sem id, retorna antes de upload e criação. Com a flag desligada, preserva o `RESET` e o `start` legados. Manual, 401, 404 e 422 não abrem conversa nem escrevem. O painel e o formulário de público usam `ChoiceSelect` nos quatro campos previstos.

## Evidência

O coordenador informou JS25 GREEN com 43 casos, incluindo 9 do PanelTune, SHA `0fb7f86e8e5e0520d6f7fae49b259fa2aa5274ff0d5e03245ee438ac68d3ed85`. Os 14 casos Ruby do reader/writer permanecem GREEN. Esta sessão não executou testes.

**Estado:** PASS limitado. O P1 está fechado no consumidor real dentro do escopo descrito. Esta checagem não aprova F0/F1 nem o lote B3 completo; F0 continua dependência futura.
