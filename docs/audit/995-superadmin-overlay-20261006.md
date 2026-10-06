# #995 — SuperAdmin real e aplicação do overlay, 06/10/2026

Checkpoint após a aplicação das três variáveis do navegador administrativo. A autorização de Rodrigo para continuar permanece válida. Este registro não conclui o corte, o login Meta ou as renovações. DNS e consentimento Tailscale já foram concluídos nos dois Macs; não devem ser refeitos.

## Estado deste checkpoint

- Runtime VPS fixado em `3783da330716bf92346e5b017a6a491fdb8f1377`; link current e `instagram_vps_env_pair_ok` reconfirmados.
- As três variáveis de navegador foram acrescentadas ao SecureString `/chatwoot/prod/instagram-tester-env`: Hub versão7→8 e Autonomia6→7. As duas operações terminaram exit0.
- A configuração gravada no SSM **ainda precisa ser carregada por uma nova release**. O processo Rails em execução não é considerado atualizado apenas porque PutParameter passou.
- O painel real do SuperAdmin das duas instalações foi acessado na sessão autenticada do Chrome do M2. Os GETs retornaram200, cinco metadados presentes, configuração completa, modo gerenciado e gatefalse. Antes de recarregar a aplicação: navegador não configurado, sessão missing e gestor unknown. Nenhum Save ou Reconnect foi solicitado.
- Nenhum corte dos gestores Mac, partida dos produtores VPS, alteração Redis ou nova publicação Meta foi realizada nesta etapa. Não habilitar assistido antes do aceite.

## Coordenação com a fila da equipe

A consulta inicial encontrou #1050 e #1049 na fila. Foram preservadas suas posições e seus deploys; não houve cancelamento, rerun ou dispatch desta frente.

A #1050 avançou main para `f5f81d160c831055b7ce6f46a25c8067c4181559` e a #1049 para `84110ba2c4ca5984cb920f7fe203681192e6b670`. Os dois pares de deploys terminaram SUCCESS antes dos planos finais do overlay:

| Release | Hub2You | Autonom.ia |
| --- | --- | --- |
| f5f81d16 | 37455927896 | 37455927910 |
| 84110ba2 | 37457160566 | 37457160622 |

Às11:55:20UTC, a nova consulta encontrou #1055/#1056 aguardando checks. Seus arquivos foram lidos: nenhuma alteração em workflow de deploy. Estar na fila não é tratado como deploy já ativo nem exige cancelar a equipe. O executor verificou ausência de deploy em execução/pendente nas janelas efetivas de escrita.

A coordenação está nos comentários da #1039, #1049 e #1056. Foi comunicado que o próximo deploy normal poderá carregar o overlay compatível, evitando dispatch redundante. Não afirmar que a equipe confirmou uma pausa: os comentários comunicam a janela e solicitam sinalizar concorrência.

## Plano atualizado sem mudar configuração funcional

Raiz local operacional:

`/Users/rodrigosilva/dev/worktrees/chat2you/995-instagram-vps-runtime/tmp/approved-1023-20261005/`

A nova pasta de evidências é `superadmin-20261006T1117/`.

O plano anterior `runtime/env-provision/env-plan.json` apontava para499809. O helper VPS exige que `plan.source_sha` corresponda ao link current; portanto foi criada uma cópia local `superadmin-20261006T1117/env-plan-runtime-3783.json`, alterando **somente** esse SHA para3783. Origens, URL, proxy e referências existentes foram preservados; o original permanece intacto.

- SHA256 do plano anterior: `7b91a91ff7325bc8dc87a30423eb252720161e779121be72c930656c32a0d3e5`.
- SHA256 do plano novo: `58e7a886107140a0f7ed1019f6a8c7fff4cb8f5f8649f0ba8ff5e5690ad5f17f`.
- Executor original `runtime/env-provision/overlay-candidate/overlay-env-deploy.py`: `32ecd57eccb309ead3c5e9a24cc41ad23f390401576db43a0ae2e99fdc131b81`.

Os validadores AWK dos workflows f5f81d16 e84110ba2 foram comparados com3783 e permaneceram byte-idênticos. O teste focal da allowlist passou4/4 em cada conjunto: novos campos aceitos; campos anteriores preservados; desconhecidos/malformados e duplicados recusados. São validações locais de leitores, não novos deploys ou CI do PR documental.

## Planos e aplicação reais

Os planos finais foram coletados depois dos deploys da equipe, às11:53:11UTC Hub e11:53:19UTC Autonomia. Confirmaram SecureString/Standard e espaço suficiente sem mudar Tier:

| Stack | Versão anterior | Bytes anteriores/projetados | Variáveis anteriores/projetadas |
| --- | --- | --- | --- |
| Hub2You | 7 | 699 / 941 | 13 / 16 |
| Autonom.ia | 6 | 522 / 768 | 12 / 15 |

Foram acrescentados somente:

- `INSTAGRAM_TESTER_RUNTIME_STACK`;
- `INSTAGRAM_TESTER_OPERATOR_BROWSER_URL`;
- `INSTAGRAM_TESTER_OPERATOR_BROWSER_SIGNING_KEY`.

| Operação | PID Mac | ConclusãoUTC | Resultado |
| --- | --- | --- | --- |
| rails-apply Hub | 77241 | 11:56:51.597482 | exit0, versão8 |
| rails-apply Autonomia | 77853 | 11:57:48.723127 | exit0, versão7 |

Cada aplicação conferiu a chave contra o gateway VPS, preservação literal de todas as linhas anteriores, KMS/Tier/metadados e readback da versão escrita. A origem do parâmetro principal permaneceu `https://chat.hub2you.ai`, versão386, e `https://agents.autonomia.site`, versão362. O principal foi apenas lido, nunca escrito.

Os workflows antes/depois de cada escrita permaneceram nos respectivos runs84110ba2 já concluídos, sem novo run durante a janela observada. Isso é verificação de concorrência, **não CAS**: PutParameter não oferece a escrita condicional utilizada aqui. A coordenação externa continua necessária.

A chave transitou somente pelo pipe privado do helper para o executor e pelo transporte autenticado ao SSM. Não foi impressa no chat ou publicada em Git. Os backups locais contêm a configuração anterior e permanecem privados0600; não devem ser abertos em ferramentas que emitam seu conteúdo.

Recibos e intents originais:

`runtime/env-provision/overlay-candidate/{hub2you,autonomia}-rails-apply.{intent,result}.json`

Backups privados:

`runtime/env-provision/overlay-candidate/backups/hub2you-before-v7.json`

`runtime/env-provision/overlay-candidate/backups/autonomia-before-v6.json`

**Não repetir rails-apply.** Se uma futura ação falhar, reconciliar versões, valor esperado e workflow antes de retry/rollback. O rollback preparado exige o resultado confirmado e a versão atualmente esperada; não é um rollback cego em caso de resposta perdida.

## SuperAdmin no navegador real

A tentativa no M4 encontrou duas limitações observadas: execução JavaScript via Apple Events desativada e página Chrome com `ERR_FAILED`. Curl sem sessão para os mesmos endpoints retornou302 para sign_in; não se atribuiu esse erro de Chrome a indisponibilidade do servidor. Nenhuma preferência ou permissão do Chrome foi alterada.

A sessão já autenticada do M2 permitiu navegação e leitura DOM pelos controles existentes. Não houve necessidade de habilitar JavaScript no M4 para essa inspeção. A tentativa de captura de janela no M2 não produziu imagem; não se declara screenshot visual aprovado nesse Mac.

A leitura DOM dos dois painéis mostrou a página `Instagram — automation`, formulário dos identificadores e saúde. No Hub, os cinco inputs estavam presentes/preenchidos; Reconnect estava desabilitado. Os resultados JSON foram obtidos por GET same-origin dentro da sessão do navegador, sem extrair cookies/CSRF ou enviar valores secretos:

| Stack | Horário de coletaUTC | Resposta |
| --- | --- | --- |
| Hub2You | 11:52:43.255245 | HTTP200, config_complete=true, managed_session=true, global_gate=false, operator_browser_configured=false, session=missing, manager_connectivity=unknown |
| Autonom.ia | 11:58:32.132165 | Mesmos estados, HTTP200, cinco chaves de metadados presentes |

Recibos: `superadmin-20261006T1117/{hub,autonomia}-superadmin-before-overlay.json`. Os nomes indicam a configuração efetiva ainda anterior à recarga, não que a segunda coleta tenha ocorrido antes do PutParameter. O primeiro início de coleta Autonomia parou na validação de aba ativa e não gerou recibo; o alvo foi depois localizado pela URL exata, sem reenvio de uma ação de escrita.

Esses GETs comprovam leitura da UI/backend autenticados e configuração local. Não comprovam que os cinco valores vieram de registros persistidos em vez de fallback ENV; o bootstrap exigido antes da partida continua sendo a prova correspondente. Não houve Save, Check health POST ou Reconnect.

## Revisões realizadas

Três revisores Codex `gpt-6.1-sol`, esforço high, modo read-only e MCPs desativados por invocação produziram pareceres textuais. Os processos terminaram exit0, os conteúdos foram lidos e os recibos reportam zero tool_events. Não são execuções de teste realizadas pelos revisores.

- `overlay-review.json`: preservação de prefixo, alvo restrito e transporte privado confirmados no código fornecido; concorrência e resposta perdida exigem reconciliação.
- `superadmin-sequence-review.json`: ordem mínima sem ciclo: configuração carregada → corte real → B0 real → produtores → Reconnect legítimo. O sucesso Meta não é pré-requisito para iniciar o gestor que permite intervenção.
- `aws-scope-final.json`: chamador completo confirma que o mesmo objeto `own` é passado à tentativa cruzada e ao controle do plugin. O material sustenta recusa comportamental limitada nas duas tentativas históricas, sem atribuição IAM nem isolamento universal. Os diagnósticos originais não foram promovidos; CURRENT e prova própria frescos continuam necessários antes do corte.

O último parecer recebeu somente dois recibos; sua referência final a seis não corresponde à entrada e não é adotada. As verificações tipadas/camadas internas do plugin não foram declaradas provadas. Não transformar uma síntese textual em flags de aceite de produção.

## Próxima sequência

Confirmar que a próxima release normal carregou as três ENV e mantém gatefalse nas duas stacks. Verificar CURRENT, web/worker e o painel novamente. Depois obter prova própria fresca e executar corte por stack, preservando sessão/Redis/outcomes; coletar B0 verdadeiro após o corte e antes de iniciar publisher/manager. Só então usar Reconnect quando o gestor estiver em operator_required e o controle disponível, seguir login/2FA Meta e validar publicação e renovações naturais.

A #995 permanece aberta e a #1042 é documental/draft, sem enfileiramento por esta etapa. Não marcar runtime ou migração como concluídos pela aplicação do overlay.
