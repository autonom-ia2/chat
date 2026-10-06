# Pacote público de recuperação — diagnóstico AWS A5/A6

Este pacote preserva os fontes revisados A5/A6, os recibos reais mais recentes,
os testes locais e a sequência de retomada já autorizada. A6 ainda não foi
promovida. O bloqueio atual é o conector Mac, com novas sondagens suspensas pelo
root após `Session terminated`.

Comece por `RESUME-CHECKPOINT.md` e `RECOVERY.md`. `ACCESS-INCIDENT.json` registra
as três tentativas somente leitura, os resultados e os limites da observação.
`AWS-HANDOFF-last-read-Mac.md` é histórico e foi preservado sem alterações.

| Caminho | Conteúdo |
| --- | --- |
| `a5/` | Seis módulos da última versão promovida e documentação histórica |
| `a6/` | Candidata exata, promotor, diffs, oito fixtures e logs cloud/Mac separados |
| `reviews/` | Parecer A5 preservado, parecer focal da projeção A6 e parecer do promotor |
| `live-a5/` | Promoção A5, C0 Hub e A Hub originais completos |
| `source-evidence/` | Índice das fontes primárias e inventário público histórico da VPS |
| `MANIFEST.json` | Lista explícita de todos os arquivos e SHA-256 de cada um |

A seleção é explícita: não foram incluídos diretórios recursivamente, chaves,
envs, credenciais, tokens, payloads brutos, caches ou binários. O pacote não
faz instalação, restauração, rotação, promoção ou chamadas externas ao ser
aberto. Ele não contém a fonte Mac do provisionador 528 nem o estado PKI e
não constitui um backup completo da infraestrutura.

Os README/PREPARED dos candidatos descrevem o estado na hora em que foram
escritos. Permanecem intactos para correlação por hash; a decisão e a pausa
atuais estão no checkpoint de retomada. A semântica da A5 continua inconclusiva
para recusa estrangeira; o código 1003 e os IDs textuais não viram PASS.
