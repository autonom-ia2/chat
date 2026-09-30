# Campanhas: publicação e restauração da biblioteca — issue 800

## Estado

Implementação em branch isolada e PR #801. QA e capturas locais disponíveis. Português e inglês concluídos. As capturas do dashboard completo estão em `docs/campaigns/workspace-800/full-application/`, com APIs reais e dados sintéticos locais. QA de integração foi retomado; o CI remoto do HEAD final deve passar antes da publicação. As capturas anteriores com shell sintético foram substituídas para aceitação visual. Nenhuma etapa abaixo foi executada em produção nesta implementação.

Não há migração de schema, mudança de credenciais, permissão, DNS ou infraestrutura. A revisão acrescenta `send_readiness` à leitura de uma campanha; endpoints existentes de enviar/agendar continuam responsáveis pela decisão final.

## Modelos prontos

Os 14 designs globais são editáveis. Mantêm os nomes originais e as fontes MJML licenciadas, acompanhados de HTML sanitizado e compilado com descadastro protegido. Textos, imagens, marcas e links de exemplo precisam ser adaptados à campanha. Isso não impede usar o design imediatamente no editor.

Em desenvolvimento, depois de alterar uma fonte, compile e revise os ativos antes do commit:

```sh
bundle exec rails email_campaign_templates:compile
```

O HTML compilado fica junto da fonte em `db/seeds/email_templates/`. A imagem final não precisa de Node ou dependências frontend para restaurar registros.

## Publicação após aprovação

1. Confirmar o PR e SHA aprovados, CI atual verde, capturas e tradução em português. Registrar aprovação no audit trail e mover a issue de Review para o estado correspondente à execução.
2. Integrar o PR aprovado ao lote de release vigente conforme `docs/processo-de-release.md`; não fazer merge direto deste código na main. Rodar os checks do lote e aguardar a validação da publicação anterior. Preparar a imagem pelo fluxo existente de deploy blue/green nas stacks Hub2You e Autonom.ia; registrar imagem/SHA anteriores como destino de rollback, sem criar infraestrutura adicional.
3. Antes do seed, inventariar os modelos globais pelos 14 nomes de `catalog.json`. Registrar IDs, presença e um snapshot seguro dos campos que serão atualizados. Não exportar modelos/dados das contas. A leitura e o write em produção exigem aprovação do Rodrigo.
4. Na imagem nova, executar uma vez:

```sh
bundle exec rails email_campaign_templates:seed
```

5. Conferir 14 nomes globais únicos e corpo/HTML com descadastro. Conferir que os modelos próprios da conta 16 continuam acessíveis e intactos. O catálogo global é compartilhado por todas as contas; esse efeito faz parte da restauração.
6. Validar no navegador da conta 16: lista, rascunho incompleto, edição/salvamento, biblioteca de 14 modelos, modelos próprios, revisão de público/remetente e agendamento. Conferir Desktop/Mobile e cancelamento da confirmação. Não executar envio real de clientes como smoke test; um eventual teste real requer destino e aprovação próprios.
7. Registrar CI, imagem/SHA publicados, verificações do ambiente, eventuais limitações e estado final da issue.

## Rollback

Se o frontend falhar, retornar à imagem/SHA anterior usando o fluxo existente de rollback. A adição de prontidão ao payload é compatível com o frontend anterior. Não há schema a reverter.

Se um design restaurado precisar voltar à versão anterior, restaurar os campos do snapshot somente dos registros globais correspondentes. Preservar modelos próprios e não excluir registros novos automaticamente. Qualquer alteração adicional no catálogo de produção depende de aprovação concreta. A biblioteca pode permanecer restaurada durante rollback da UI, pois é independente da organização das telas.
