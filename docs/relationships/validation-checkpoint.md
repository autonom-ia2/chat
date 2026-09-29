# Checkpoint de validação — Issue #757

Estado: candidato em validação, **sem autorização de merge/deploy**.
Base: `8396d7255e097ba79507a22081701eb41ddb6ce5`.

## Evidências executadas pelo supervisor

- PostgreSQL isolado: 358 exemplos, zero falhas, incluindo as alterações de Relacionamentos,
  controllers antigos, importadores, extractor do CRM, identificação/mesclagem e interleavings reais.
  Resultado: `integrated-rspec-v3.json` no diretório local de QA, sem dados de produção.
- Suíte frontend completa anterior às últimas correções: 6.736 testes, zero falhas/pendentes.
  Reexecução completa do candidato final permanece necessária.
- Navegador com backend real: os sete cenários de acceptance passaram na terceira execução.
  O oitavo cenário, login pela interface, encontrou o limite legado de sessões porque os testes
  acumulavam sessões sintéticas. O limite de produto não foi alterado: sessões de QA foram
  limpas somente no banco isolado; execução consolidada deve ser repetida.
- Gate AST: 96 fontes/testes alterados analisados, nenhuma regex nova detectada.
- Foram corrigidos defeitos encontrados pela revisão e pelo navegador, inclusive o uso inicial
  do cliente HTTP não autenticado. Os quatro callers novos agora usam o cliente autenticado
  existente do painel, sem alteração de autenticação ou apiHost.
- A fixture de etiqueta foi alinhada ao contrato antigo `show_on_sidebar`; a fixture do importador
  mantém o tipo numérico de Freshdesk. Nenhuma validação de produto foi afrouxada para testes.

## Publicação e execução Linux

O workflow antigo `Testes do fork` está desabilitado manualmente. A validação desta entrega
não depende dele: o workflow aditivo `relationships.yml` executa regressão e constrói a imagem
final em runner descartável, sem push de imagem, sem AWS, sem secrets e sem deploy.
O smoke da imagem roda com rede desligada, filesystem somente leitura e limites de recursos.
Nenhum resultado Linux é considerado aprovado antes da execução desse workflow.

## Gates ainda abertos neste checkpoint

Reexecução final JS/API/E2E; revisão adversarial final; comparação visual desktop/mobile;
originais e previews autorizados; performance da consulta; imagem Linux e smoke dos conversores.
O rascunho de PR poderá executar CI, mas permanece bloqueado para merge.

Não se promete que uma API legada sem versão detecte a intenção de payloads externos completos
obsoletos: seu contrato continua last-write-wins. O protocolo novo controla concorrência, e os
escritores internos tocados usam atualização/merge sob lock sem substituir valores de outras chaves.

## Correções verificadas após a primeira revisão da PR

- Leitura/remoção de atributos pelo Widget passou a usar o mesmo lock do contato;
  teste com duas conexões PostgreSQL comprovou a sobreposição e preservou o valor recém-confirmado.
- Upload parcial de uma miniatura agora mantém a referência do blob para agendar sua limpeza;
  teste grava no storage de teste, simula falha posterior, executa a limpeza e preserva o original.
- A rodada conjunta dessas correções, contratos do Widget e entrega autorizada de mídia passou:
  **38 exemplos, zero falhas**, incluindo expiração do original e reautorização após desvincular contato.
- Primeiro CI interrompeu no gate AST por dependência transitiva não declarada; `@babel/parser`
  foi declarado diretamente, fixado na versão já usada no lockfile. A execução local não bastava.
- A primeira construção da imagem no GitHub Actions esgotou o disco do runner (`ENOSPC`),
  antes do smoke. A preparação agora libera SDKs não usados exclusivamente no runner hospedado
  descartável; não altera máquina do desenvolvedor, aplicação ou servidor compartilhado.
  O gate de runtime permanece pendente até concluir a nova execução.

## Retomada — gates de CI e navegador

- Rodada local `resume-browser-suite.log`: **14/14 fluxos de navegador com backend real**;
  login pela interface foi separado do teste de criação para dar a cada fluxo o mesmo limite
  original de 30 segundos. Nenhum timeout ou asserção de persistência foi afrouxado.
  As verificações aguardam as respostas autenticadas de contato/configuração antes da UI.
- Conversores nativos locais: **16/16** após bootstrap explícito do bundle no subprocesso
  de imagens. O smoke da imagem Alpine falhava no PNG; a correção e o diagnóstico limitado
  do runner ainda precisam ser comprovados pelo próximo CI.
- Gate estrito já existente de e-mail foi executado sobre todos os JS/Vue/MJS alterados:
  **zero bloqueios**, somente avisos permitidos de chaves dinâmicas. Não foi modificada sua regra.
- Gate AST exclui dependências não versionadas instaladas pelo runner na origem da listagem,
  mas continua examinando todo arquivo de fonte alterado/versionado. Não admite regex nova.
- A janela contextual mantém nome e descrição sem exibir a chave técnica; geração automática
  e preservação de `job_title` continuam testadas no payload.
- PR de revisão: **#760**, ainda rascunho. As execuções anteriores com falhas não representam
  release aprovado. Nenhum merge/deploy foi executado. Project retornou404 nesta retomada.
