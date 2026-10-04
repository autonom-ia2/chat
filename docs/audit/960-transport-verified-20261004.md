# #960 — transporte comprovado nas duas instalações

## Execução de 04/10/2026, 20:43–20:44 UTC

O operador iniciou o launcher no M2, usando os perfis AWS já existentes no M4 pela conexão SSH autorizada. O executor concluiu Hub2You e Autonom.ia, sem novo login ou cópia de credenciais para o Mac cliente.

| Prova | Hub2You | Autonom.ia |
| --- | --- | --- |
| SSM terminou com sucesso / código zero | Sim | Sim |
| Transporte auxiliar instalado na instância atendendo tráfego | Sim | Sim |
| Redis: TLS/certificado e autenticação | Aprovado | Aprovado |
| Redis: marcador de integridade esperado | Aprovado | Aprovado |
| Webshare: HTTPS e saída residencial esperada | Aprovado | Aprovado |
| Comparação dos containers e arquivos da aplicação | Sem mudança | Sem mudança |
| Escritas Redis ou chamadas Meta pelo teste | Nenhuma | Nenhuma |

O coordenador consultou novamente as execuções na AWS às 20:48 UTC, conferindo os identificadores, os recibos, a conta e a permanência das duas instâncias no ponteiro CURRENT. Ambas correspondem ao relatório local. A consulta não iniciou outra instalação nem recuperou valores dos parâmetros secretos.

Fontes locais: `tmp/reuse-auth-20261004/relatorios-transporte/resultado.json` e `tmp/final-release-20261004/transport-aws-confirmation.json`. O estado local terminou com `pending: null`. A instalação dos servidores antigos não foi repetida ou apagada.

## Limites e próximo gate

Este registro encerra a pendência de transporte atual: AWS → túnel SSH → Redis dedicado/Webshare. Não equivale a deploy da aplicação, sessão Meta autenticada, renovação automática, exclusão concorrente real entre stacks ou mensagens de Instagram. O teste de persistência anterior do Redis dedicado permanece documentado separadamente.

A versão da aplicação ainda precisa incorporar as correções locais e as mudanças recentes da main, receber revisão independente e CI no SHA final. Merge e deploy continuam dependentes de aprovação explícita. A instalação em instâncias futuras deve ocorrer pelo workflow da release, não por repetição manual deste bootstrap.

Não reprovisionar o Redis, resetar epoch, limpar outcomes, substituir REDIS_URL global ou compartilhar credenciais administrativas para concluir a ativação.
