# Diagnóstico da importação TypeSafe — #764 — 30/09/2026

## Escopo e resultado

Rodrigo pediu verificar uma importação que acabara de falhar na Hub2You. Foram realizadas leituras da interface, da resposta já solicitada pelo navegador, dos logs do worker e dos metadados da tentativa em sessão de banco somente leitura. Nenhuma repetição de importação, edição de campanha, envio de e-mail, alteração de configuração ou chamada paga ao modelo.

Versão produtiva examinada: e45fbe68945f948525dcc0a2997eae5c3c9dc74f. Tentativa iniciada e concluída em 30/09/2026 13:05:16 UTC, status failed, zero destinatários adicionados. O arquivo de teste enviado foi `05_duplicidade_normalizada.xlsx`; tamanho e checksum do blob correspondem ao arquivo sintético local. Credencial TypeSafe configurada, funcionalidade ativada e modelo configurado jev-1.13.0. A confirmação anterior de conexão não comprova resolução real de planilha pelo modelo.

## Causa confirmada

O código persistido foi `duplicated_name_header`; o worker registrou `EmailCampaigns::RecipientImporter::Error`. As colunas `Cliente` e `Contato` são aliases de nome no HeaderMapper. SchemaResolver#blocking_ambiguity rejeita essa duplicidade antes de resolve_with_ai. Portanto, o caminho desta tentativa não chamou o Jev. O arquivo de duplicidade entre destinatários não chegou à etapa que conta endereços repetidos.

O segundo problema é de apresentação: Presentation::Errors::IMPORT_CODES não permite os códigos de cabeçalho/resolução/TypeSafe introduzidos pelo importador. O código específico foi substituído por import_failed na API, causando a mensagem genérica observada. O helper frontend já reconhece duplicated_name_header, mas não recebe esse valor na resposta sanitizada.

## Reprodução local, sem modelo pago

Parser e SchemaResolver reais foram executados contra os cinco XLSX locais do pacote sintético. Um resolver substituto interrompe qualquer chamada ao modelo; nenhuma avaliação externa aconteceu. Esta verificação cobre leitura e resolução de cabeçalhos, não inserção de destinatários nem qualidade real do Jev.

| Arquivo | Resultado de leitura/resolução atual |
| --- | --- |
| 01_padrao_limpo.xlsx | Determinístico; duas linhas; nome/e-mail mapeados. |
| 02_cabecalhos_nao_padrao.xlsx | Determinístico; duas linhas; e-mail mapeado, nome completo mantido em coluna adicional. Não chama Jev. |
| 03_dados_sujos_e_email_invalido.xlsx | Cabeçalhos resolvidos; duas linhas. O endereço inválido ainda deve ser tratado na etapa de destinatários. |
| 04_campos_fragmentados_e_customizados.xlsx | duplicated_email_header: a regra de alias parcial também reconhece aceita_email. Falha antes do Jev. |
| 05_duplicidade_normalizada.xlsx | duplicated_name_header: Cliente e Contato. Reprodução da falha produtiva. |

## Validações e limites

Comandos/resultados: git fetch origin main; leitura da versão publicada e dos caminhos em app/enterprise; observação Network da campanha com recorte apenas de status/contadores; SSM/docker logs com filtro para a tentativa; probe de metadados com SET default_transaction_read_only = on; bundle exec rails runner do diagnóstico no ambiente local de testes isolado. O runner local utilizou somente os arquivos sintéticos e o resolver substituto, sem gravar destinatários. Não foram criadas specs nem alterado código de aplicação.

Evidências selecionadas ficam em `.codex/764-diagnostics/`, fora do Git; não incluem chave, corpo de planilha, nomes/e-mails de destinatários, cabeçalhos de autenticação ou logs brutos. O navegador de diagnóstico não recarregou nem alterou a aba original do Rodrigo.

## Próximos passos recomendados

Revisar o tratamento das ambiguidades para que Jev possa resolver os casos apropriados, mantendo a validação do endereço de destino e a preservação das colunas adicionais. Não escolher a primeira coluna silenciosamente. Preservar na API os códigos conhecidos e seguros que a interface pode explicar. Cobrir os arquivos 04/05 e os cenários já existentes antes de publicar uma correção; a #764 permanece aberta. A avaliação real com Jev exige execução explícita e orçamento definido, conforme AGENTS.md. Não declarar este diagnóstico como correção aplicada ou aceite real do modelo.
