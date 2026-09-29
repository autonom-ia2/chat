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
