# B1: parada na checagem das consultas — 07/10/2026

## Estado

Não houve execução de SQL, acesso a produção ou alteração de produto. Desenho B1 e suas consultas estão em rascunho. Após correções da primeira conferência (preservar espelho sem conversa e prefixo literal), a checagem independente encontrou B1-SQL-01/02. Trabalho dependente das consultas parado até corrigir a causa e concluir uma revisão final; erro na final exige retorno ao Rodrigo.

## Achados e causa

| Achado | Causa raiz | Correção da causa |
|---|---|---|
| B1-SQL-01: conta da inbox ausente do join | A relação foi conferida pelo vínculo e bot denormalizados, sem fechar o caminho até a entidade inbox. A comparação de conta entre todas as entidades não foi registrada na revisão inicial. | Conferir e registrar agente → vínculo → inbox → bot nativo → vínculo do bot → conversa no baseline fixo. JOIN da inbox exige a conta do vínculo. |
| B1-SQL-02: prefixos amplos excluem chaves ainda desconhecidas | A revisão inicial corrigiu o wildcard de LIKE e confundiu essa correção sintática com o contrato de lista fechada da consulta. O requisito textual de reportar chaves novas não foi confrontado com cada exclusão. | Levantar os escritores atuais no código, registrar os nomes exatos permitidos e remover exclusão genérica por prefixo. Uma chave nova passa a aparecer na Q12a até ser conferida e declarada. |

## Conferência antes da revisão final

- [x] Consultas preservam a contagem de espelhos sem conversa presa.
- [x] Conta conferida em cada join; referências no SHA `6242e31695fd1c6b8b088f2fcb819c027fc5083c`.
- [x] Exclusões de configuração são nomes exatos, ligados aos escritores; nenhuma exclusão genérica.
- [x] READ ONLY, timeouts de 5s/1s, ROLLBACK e saída somente IDs/chaves/contagens.
- [x] Revisão final independente concluída sem erro.

Nenhum resultado documental prova que o schema ou runtime de produção corresponde ao baseline. Eventual falha de schema ou timeout na leitura autorizada será falha registrada, sem retry ou correção de dados automática.

## Resultado da revisão final

Revisor independente `r9_produto` concluiu: consultas §5.1 e §5.2 prontas para pedir OK específico de leitura, sem novos erros. Conferência limitada ao SQL documentado contra o SHA fixo. Demais mecanismos B1 continuam em rascunho, sem aprovação de implementação. Nenhum banco foi executado.
