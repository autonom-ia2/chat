# Planilhas de aceitação da importação — #764

O arquivo `30-planilhas-sinteticas.zip` contém 30 CSV/XLSX com dados fictícios e o relatório `results.json`. Os cinco primeiros são os arquivos originais do pacote de teste fornecido pelo operador, incluindo o XLSX cuja importação falhou na conta 16. O relatório identifica cada arquivo por SHA-256, registra o resultado esperado e o observado e indica as colunas escolhidas pelo Jev.

Em 30/09/2026, os 30 casos tiveram o resultado esperado: 26 importações concluídas e quatro recusas justificadas. Os casos de recusa são parte do teste: duas colunas igualmente plausíveis, ausência de e-mail, todos os endereços inválidos e arquivo vazio. Nenhum e-mail foi enviado.

## Cobertura

| Casos | Situação |
| --- | --- |
| 01–05 | Arquivos originais: padrão, cabeçalhos incomuns, endereços inválidos, campos fragmentados e duplicidade normalizada |
| 06–14 | Separadores diferentes, BOM, UTF-16, CP1252 e campos entre aspas/com quebra de linha |
| 15–18 | XLSX com título antes da tabela, múltiplas abas, colunas reordenadas e linhas vazias |
| 19–22 | Nome opcional, empresa versus pessoa, consentimento versus endereço e e-mail principal versus secundário |
| 23–26 | Recusas esperadas com motivo específico e nenhum contato adicionado |
| 27–30 | Duplicidade, falha permanente/spam/descadastro, campos adicionais e instrução maliciosa em cabeçalho |

## Repetição pelo produto

1. Use uma instalação de teste isolada, com conta sintética e campanhas em rascunho. Não use a conta 16 de produção para a rodada.
2. Ative a integração TypeSafe usando o mecanismo de configuração existente. Testes com provedor pago exigem autorização explícita e um limite de gasto; permanecem desativados nas suítes automatizadas comuns.
3. Descompacte os arquivos e crie uma campanha de teste por arquivo. Envie a planilha no fluxo normal de inclusão de destinatários e aguarde o resultado final.
4. Compare resultado, duplicados, inválidos, exclusões e colunas com `results.json`. Para o caso 28, cadastre previamente os três bloqueios fictícios indicados na planilha: falha permanente, spam e descadastro.
5. Abra no editor uma campanha com a falha do caso 23. O popup deve explicar o motivo e a correção. Escolha o arquivo 22 dentro do próprio popup; a nova importação deve concluir com dois contatos na mesma campanha.
6. Verifique que o rascunho continua salvo e a campanha continua sem enviar. Teste também fechar e reabrir o popup e usar uma tela estreita.

Nome e sobrenome separados não são concatenados por esta alteração. A coluna de nome identificada é usada como nome; as demais informações permanecem como campos adicionais. Esse limite é explícito no caso 04.

A aprovação dos 30 casos demonstra a cobertura deste conjunto. Não garante que toda planilha possível será importável: arquivos danificados, dados inexistentes ou ambiguidades reais continuam exigindo correção.
