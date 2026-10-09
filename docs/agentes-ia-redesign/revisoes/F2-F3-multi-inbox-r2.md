# Revisão R2 — composer do Teste e múltiplas caixas no Ligue

**Data:** 2026-10-08  
**Fonte visual:** rodada 54, snapshot `20261008-105028-532a5b7b-5711deea65-548ec6fb`, SHA de conteúdo `5711deea65fa462600d85866574c9a3c71f1d031d7cd07040d4a92ab36423ee4`.  
**Escopo:** confirmação do achado `F2-F3-MULTI-R1-01` e verificação de regressão nos estados móveis Teste válido e Teste invalidado. Inspecionei as capturas originais, com proveniência em `.codex/preview/check54/capture-provenance.json`.

## Achado R1 encerrado

### F2-F3-MULTI-R1-01 — resolvido

O composer móvel agora acomoda as duas linhas de “Escreva uma mensagem de teste” sem cortar a segunda linha. Isso aparece nas versões clara e escura de `ajuste-composer-teste-chromium-400-{light,dark}.png`. Nas versões desktop `ajuste-composer-teste-chromium-1440-{light,dark}.png`, o campo continua alinhado em uma linha.

O botão de envio permanece visível e com alvo de toque adequado nos quatro perfis. A correção visual está limitada ao tamanho responsivo do campo; não alterou a associação de caixas nem o contrato de publicação.

## Verificação de regressão nos estados móveis

As capturas `criacao-04-teste-valido-chromium-400-{light,dark}.png` continuam legíveis: a resposta, a mensagem de orientação, o composer e o botão “Continuar para Ligar” permanecem acessíveis no fluxo.  

As capturas `criacao-05-teste-invalidado-chromium-400-{light,dark}.png` preservam o estado invalidado, a mensagem de orientação e o aviso de salvamento, sem corte do texto do composer ou sobreposição acionável. O enquadramento dessas duas capturas está posicionado na parte inferior da etapa, portanto o rodapé completo não é usado como prova adicional.

Não encontrei novo problema de produto/UX nesta R2. A associação de múltiplas caixas, os estados do Ligue e a tela Pronto não mudaram desde a R1 e permanecem encerrados pelo parecer anterior.

## Conclusão

O único achado da R1 foi corrigido e não surgiu regressão visual nos estados conferidos. Esta R2 encerra a lente produto/UX para os dois ajustes; não constitui aceite humano, CI, aprovação de release ou validação de produção.
