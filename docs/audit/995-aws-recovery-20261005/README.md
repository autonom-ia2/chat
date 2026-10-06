# Issue #995 — fontes de recuperação e estado após o merge #1039

Checkpoint de 5 de outubro de 2026, após os deploys do commit `3783da330716bf92346e5b017a6a491fdb8f1377`. Este diretório preserva fontes públicas revisadas e evidências selecionadas para a retomada. O acompanhamento vigente permanece na [issue #995](https://github.com/autonom-ia2/chat/issues/995) e no [comentário de coordenação da PR #1039](https://github.com/autonom-ia2/chat/pull/1039#issuecomment-6001227765).

## Resultado confirmado

- A #1039 foi mergeada pela fila normal às **23:18:33 UTC**. O head aprovado era `c46cf166438b64626d45125450ec2ed4826915aa`, com **26 checks aprovados**. Os cinco gates obrigatórios também passaram no [grupo da fila](https://github.com/autonom-ia2/chat/actions/runs/37386874571).
- Os workflows de deploy [Hub2You 37387737879](https://github.com/autonom-ia2/chat/actions/runs/37387737879) e [Autonom.ia 37387738073](https://github.com/autonom-ia2/chat/actions/runs/37387738073) terminaram em **SUCCESS**, na primeira tentativa e no SHA mergeado. A leitura direta da API às 23:34:43 UTC confirmou ambos; os últimos horários de atualização dos runs são 23:33:33 e 23:33:27 UTC, respectivamente.
- Os 22 caminhos aprovados da PR não mudaram entre o head c46 e o commit publicado. O merge também preservou as alterações que já estavam em main.
- A instalação do runtime corrigido na VPS, o HTTPS real, o corte, a publicação Meta e as renovações naturais ainda não foram concluídos. **A issue continua aberta e `INSTAGRAM_TESTER_AUTOMATION_ENABLED=false`.**

O sucesso dos workflows de deploy comprova os resultados das etapas registradas nos próprios runs. Uma nova verificação operacional por SSM depois desses deploys ainda depende do acesso ao Mac.

## Conteúdo preservado

| Caminho | Escopo e estado |
| --- | --- |
| `aws/bundle/` | 45 arquivos públicos A5/A6, incluindo o manifesto original: fontes, fixtures, pareceres e três recibos reais A5. A6 revisada e autorizada, ainda não promovida. |
| `aws/review/` | Parecer final do pacote documental AWS, externo ao bundle congelado. |
| `recovery-source-v2/` e `review/` | Allowlist, plano, copiador e pareceres do snapshot de 54 caminhos: 51 obrigatórios e três opcionais. Preparação concluída; zero cópias no Mac por esta execução. |
| `runtime-3783/` | Inventário público dos 41 arquivos do runtime, candidato display/gateway com SHA atualizado e os dois pareceres. Não contém tar nem manifesto operacional. |
| `release/` | Recibos públicos de CI, merge, comparação das fontes e conclusão dos dois deploys. |
| `FILES.json` | Tamanho, SHA-256 e Git blob SHA-1 dos arquivos preservados nesta consolidação. Não descreve instalação ou restauração. |

Os arquivos históricos mantêm seus bytes e carimbos originais. Um README, HANDOFF, PREPARED ou parecer que descreva uma etapa como pendente registra o instante de sua autoria; consulte este checkpoint e o recibo posterior correspondente. O HANDOFF AWS antigo é anterior à autorização A6, que está explicitada em `aws/bundle/RESUME-CHECKPOINT.md`.

## Bloqueio observado

O conector **Rodrigo Local Terminal/Filesystem** do M4 passou de timeouts para `Session terminated`, `INVALID_ARGUMENT`, JSON-RPC **32600**, confirmado pelo coordenador às **23:01:40 UTC**. As tentativas registradas eram somente leitura. Novas sondagens foram suspensas, e nenhuma promoção A6, chamada de upgrade, Serve, overlay, corte ou partida de produtores foi enviada nessa janela.

A última limpeza real do diagnóstico A5 Hub foi confirmada às **22:34:33.466124 UTC**. É uma observação histórica; o erro do conector não informa a saúde atual da VPS. A autorização para implementar, revisar, testar, publicar e executar o corte coordenado permanece válida. A dependência é restabelecer o controle normal e reconciliar fontes e journals.

## Sequência de retomada

1. Reabrir a conexão normal do M4 e reconciliar, por leitura, os arquivos, hashes, intents, recibos e backups exatos antes de qualquer nova execução. Uma resposta perdida não prova ausência de mutação; não repetir automaticamente uma operação ambígua.
2. Para AWS, seguir `aws/bundle/RESUME-CHECKPOINT.md`: promover uma vez os bytes A6 já revisados, fazer o preflight e um C0 Hub novo; apenas com contexto compatível, frescor e cleanup conclusivo, executar uma A Hub. Encerrar as sessões e interpretar o resultado antes de ampliar a sequência. A A5 continua inconclusiva para recusa de canal estrangeiro; código 1003 ou IDs textuais não transformam esse resultado em aprovação.
3. Produzir o pacote real do SHA mergeado pelo `runtime-upgrade.py` original no Mac. Comparar seu manifesto com o inventário `runtime-3783/merge-3783-source-inventory/source-inventory.json`, cujo digest canônico de `files` é `c5df697fbfdb884f6e728118efb75b32ac1cb3ea164d6c8a8941ec2560dafc8d`. Revisar o tar/manifesto real antes de stage, preflight, install e verify-inactive, em chamadas separadas.
4. Reconciliar o candidato display/gateway do diretório novo, completar verify-pair e executar a ativação coordenada da Hub. Somente após start e verify aprovados, seguir Serve/HTTPS e os negativos já previstos. Reconsultar CURRENT, versão do overlay e leitores Rails antes de aplicar a configuração e recarregar os serviços.
5. Concluir o isolamento AWS exigido, realizar o corte controlado dos gestores Mac, coletar B0 válido após o corte e antes dos produtores, iniciar os produtores e realizar login/2FA Meta com o operador. Demonstrar publicação e as renovações naturais previstas, correlacionando timestamps e supervisão. A independência operacional dos Macs é comprovada pela drenagem e operação exclusiva da VPS; não exige desligamento físico do M4 de manutenção.

A cópia fria V2 e o pacote documental AWS são conjuntos distintos. O copiador V2 não foi executado e seu manifesto real não foi criado por esta frente. O inventário de 41 fontes do runtime também não é um manifesto operacional. Cada conjunto conserva seu escopo e seus pareceres próprios.

## Limites de recuperação

Esta consolidação contém fontes e evidências públicas selecionadas. Chaves, envs, credenciais, tokens, estado privado, índices/seriais PKI e a custódia da CA ficam fora dela. O provisionador Mac `5280a18b…` permanece uma dependência externa explicitada no bundle AWS. Não reconstruir PKI ou estado operacional a partir destes relatos.

Os caminhos de origem e modos necessários à restauração permanecem nos documentos correspondentes. Os blobs de auditoria são armazenados em Git como arquivos documentais regulares; preservar um arquivo aqui não o instala, promove ou executa.

Referência base desta branch de auditoria: commit `3783da330716bf92346e5b017a6a491fdb8f1377`, tree `4959339843ca4428f730415debeee9d95769984d`. A consolidação documental não altera os arquivos de produto de main nem adiciona entrada à fila de merge.

