# Auditoria de importação de destinatários — 14/09/2026

Issue: https://github.com/autonom-ia2/chat/issues/428

## Conclusão

A tentativa correspondente ao horário da captura falhou porque o processamento excedeu o limite HTTP de 15 segundos. O servidor recebeu o arquivo, passou pela leitura e pelo mapeamento de cabeçalhos e chegou à importação dos destinatários. Não foi uma rejeição inicial do formato XLSX.

## Evidência de produção

- Janela consultada: 14/09/2026, 20:20–21:00 UTC (17:20–18:00 em São Paulo).
- Requisição correlacionada: `8ea8897d-5a72-4a6c-99fa-9a60ca7aacc7`.
- Início às 17:42:28; falha às 17:42:43, imediatamente antes da captura das 17:42:45.
- `source=rack-timeout timeout=15000ms service=15000ms state=timed_out`.
- `Rack::Timeout::RequestTimeoutException (Request ran for longer than 15000ms)`.
- HTTP 500 em 15173 ms; 2929 consultas ao banco; 5284,1 ms de ActiveRecord e 1664,3 ms de GC. Número de consultas não representa número de contatos.
- Stack: `RecipientImporter#existing?`, linha 84; `process_row`, linha 59; `import_rows`, linha 46.
- Imagem ativa observada: tag `5742de5fcda319c97c21b0fdf7d79b2dd793090d`.
- O serviço RecipientImporter foi lido diretamente do contêiner ativo e coincide com o fluxo descrito abaixo.

## Mecanismo

O endpoint executa a importação inteira dentro da requisição HTTP. Para cada destinatário, consulta a existência do e-mail e cria o registro individualmente. Todas as linhas estão em uma transação. Esse custo acumulado ultrapassou o limite de 15 segundos nesta tentativa. A exceção deve desfazer a transação; o saldo efetivo de destinatários não foi consultado no banco nesta auditoria.

A campanha é salva separadamente antes da importação. O frontend captura a falha e mostra uma mensagem genérica de rascunho salvo, sem apresentar o motivo retornado pelo servidor.

Referências: `app/services/email_campaigns/recipient_importer.rb`, `app/controllers/api/v1/accounts/email_campaigns/recipients_controller.rb`, `app/javascript/dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/EmailCampaignDialog.vue`.

## Limites

Não foram inspecionadas as células do arquivo original nem feito novo upload. Não se atribui o erro a arquivo corrompido, cabeçalho inválido, domínio remetente ou SMTP: a tentativa correlacionada avançou até a persistência e foi interrompida por timeout. Outros HTTP 422 foram observados na janela, sem diagnóstico de seu motivo e sem atribuí-los a esta tentativa. Não houve consulta a registros de clientes, alteração em produção ou disparo de e-mail.

## Correção proposta, ainda não implementada

Mover a importação para um job em segundo plano, com status consultável pela interface, controle contra repetição e resultado explícito. Reduzir consultas por linha mediante leitura e gravação em lotes, preservando validações, supressões e contadores. Melhorar a mensagem de erro. Aumentar isoladamente o timeout não resolve a dependência do tamanho da lista.

A validação deve cobrir arquivo representativo, contagens, duplicados, supressões, falha e nova tentativa, sem envio de campanhas. Correção e deploy dependem de trabalho separado; merge e deploy exigem aprovação. Este PR contém somente documentação e não requer deploy; rollback documental por revert, caso necessário.

## Trilha e revisão

Leituras executadas: `git status --short`, busca e leitura dos arquivos citados, DNS do domínio, consulta SSM da instância corrente, `ec2 describe-instances`, `journalctl` filtrado por janela e request ID, `docker ps` e `docker exec ... cat` do código ativo. SSM foi usado somente para comandos de leitura. O host legado foi inventariado e descartado como fonte do diagnóstico após verificação do domínio na AWS.

Revisão: horários convertidos de UTC para UTC-3; request ID consistente entre timeout, status e stack; nenhum conteúdo de planilha, credencial ou dado pessoal incluído. Sem testes de aplicação porque não houve alteração de código. Checkout original preservado.
