# Lia: voz sem processo interno e lista que diz o que leva (18/09/2026)

Refs #420. Item 1 (promessa de atendente) separado na #449.

## O que a produção mostrou

Prova real de 18/09/2026, conta 16, agente 24 "Lia", conversa 5045:

1. **Promessa de atendente sem ninguém acionado.** Isso fica **fora desta entrega**, por decisão do CEO: o destino é o handoff do Chatwoot/CRM, cuja integração com a Lia ainda não existe. Diagnóstico e critério de pronto na #449. Nada de `bot_handoff!`, `should_handoff` ou `handoff_strategy` foi tocado, e não houve escrita em produção.
2. **Custo interno exposto:** "novas tentativas podem gerar custo". A origem é a §10 do `especialista_auto.md`, que dava o custo como motivo para não tentar de novo sem dizer que o motivo é nosso. A §2 mandava ainda "deixar claro que nenhuma cotação foi consumida".
3. **Vocabulário de sistema:** "não consegui confirmar a abertura da cotação". A origem é a descrição do papel `incerto` (`Frases::DESCRICOES`), que falava em cotação "aberta".
4. **Promessa que a lista não cumpre:** a Lia prometeu "as três de menor valor, sem a assinatura mensal", e o anexo de `ver_resultado_da_cotacao` trouxe as 11, com a mensal. O retorno da ferramenta ao modelo não dizia o que o anexo leva.

## Correção

- **2 e 3, manuais:** a §4 do `principal.md` e a §2 do `especialista_auto.md` proíbem falar de custo, de tentativa, de "abertura", de "sistema" e de processo interno. A §10 do especialista mantém a regra de não tentar de novo e marca o motivo como nosso. A frase "nenhuma cotação foi consumida" saiu. O md5 da guarda do especialista foi reassinado. Os blocos do principal assinados por md5 (§5 resultado, §5 especialistas, §7.1) não mudaram.
- **2 e 3, descrições:** `falhou` e `incerto` perderam "concluída" e "aberta". A promessa sobre o atendente ficou igual. As constantes de recuo `FALHOU` e `INCERTO` **não** mudaram: elas são a identidade (SHA) de entregas já publicadas por execuções que atravessam o deploy.
- **4:** o retorno ao modelo ganha uma linha, contada sobre os mesmos códigos que foram anexados: quantas opções a lista leva, se a assinatura mensal está nela, e que ela sai inteira. **Sem parâmetro de quantidade**: com a lista anexada sempre inteira, a Lia diz com as palavras dela que manda a lista completa.

## Testes

Um por item, e cada um cai sem a correção (medido com `git stash` de `app/`: 3 de 3 falharam):
- `builder_voz_sem_processo_interno_spec.rb`: os manuais (2) e as descrições (3).
- `insurance_quote_result_spec.rb`: "diz ao modelo quantas opções o anexo leva e se a assinatura mensal está nele" (4).

## O que não foi verificado

- Nenhuma conversa real foi feita depois da mudança: o efeito sobre o texto do modelo é esperado, não medido.
- A instrução do agente 24 em produção é lida do arquivo do deploy (#380), então vale depois do deploy. Não confirmei em produção.
- A promessa de atendente continua falsa até a #449.
