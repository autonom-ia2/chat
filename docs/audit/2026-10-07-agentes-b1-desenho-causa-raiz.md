# B1 — parada após a checagem e causa raiz

Estado: implementação bloqueada. Nenhum código de produto, spec, teste, SQL adicional ou eval pago executado. HEAD do PR documental #1115 permanece `532a5b7beb56902d2a0168013a3e8b657ba31488`, sem novo push.

## Erros concretos da checagem

| ID | Gravidade | Evidência |
|---|---|---|
| B1-TEC-08 | P1 | Desenho B1:324–343 escolhe HTTP_UID antes de HTTP_ACCESS_TOKEN; uid controlável cria bucket novo, contrariando PRD:532–534 |
| B1-TEC-09 | P1 | B1:141–160 deixa silence_tokens e voice_instructions em operation_key_not_ready; D21/BE31 aprovam todas as doze chaves |
| B1-TEC-10 | P1 | B1:156–160 recusa arrays vazios; Registry:71–75, Operate:59–63 e polling têm semântica válida de limpar/resetar |
| B1-TEC-11 | P1 | B1:169–172 não exige validar payload bruto antes de sanitized_config; AgentsController:157–185 já descarta chaves reservadas, e PATCH genérico do SuperAdmin precisa seguir o mesmo contrato público |

Cinco achados originais foram fechados; o contrato de valores BE31 ficou parcial e o throttle continuou incorreto.

## Causa raiz

O desenho fechou o formato do caminho SuperAdmin novo, mas não rastreou completamente os caminhos antigos nem a semântica dos valores que limpam configuração. Isso produziu quatro manifestações: identidade do cliente tratada como identidade autenticada no limite; bloquear uma chave aprovado usado como substituto de fechar seu contrato; formato vazio tratado uniformemente apesar de leitores distintos; e validação especificada depois de um caminho que já filtra o payload.

O método precisa cobrir, por entrada, a origem bruta → validação → gravação → leitor, e por valor o resultado de definir, substituir e limpar. Não basta corrigir a tabela de tipos ou o exemplo que recebeu o achado. Esta é a mesma classe das causas C1/C9/C11 do audit do PRD, aplicada agora ao desenho técnico.

## Correção da causa antes da revisão final

1. Identidade do limite vem do token API ou web previsto no contrato, com hash antes de chave/log; uid não substitui token. Spec mantém token e varia uid, provando bucket estável.
2. As doze chaves D21/BE31 têm contrato concreto, incluindo silence_tokens e voice_instructions; nenhuma chave fica em not_ready. Limites são definidos no desenho, sem consulta de valores de produção.
3. Cada array/texto opcional define explicitamente vazio/reset conforme seu leitor, com prova de limpar configuração já existente.
4. Create e PATCH genérico validam config bruto antes de strong params/sanitized_config; ator SuperAdmin não amplia essa entrada. Prova cada classe de chave proibida com 422/key e configuração relida igual.
5. Conferir todos os pontos correspondentes em B1.md e os sete achados originais, sem alterar o escopo aprovado do PRD.

Após a correção, haverá somente a revisão final desses onze pontos. Persistindo qualquer erro, parar e retornar ao Rodrigo. Não abrir outra rodada nem iniciar implementação.

## Correção concluída e envio à revisão final

O worker alterou somente `design/B1.md`, com 728 linhas. A versão enviada à revisão final tem SHA-256 `766d29ba599ee2b7ff152678eb3b4014ba43a5d1e3704e78d81f5b076e3d3fda`. O passe de consistência removeu a indisponibilidade das duas chaves, fixou a identidade pelo token, explicitou set/replace/clear por leitor e a validação bruta antes de strong params/sanitização em todas as entradas genéricas. `git diff --check` passou.

A revisão final foi solicitada ao mesmo revisor técnico independente, somente leitura, contra os onze pontos e o baseline fixo. Nenhuma implementação está liberada antes do resultado. Persistindo erro, não haverá nova correção ou revisão.

## Revisão final — ERRO residual P1 e parada obrigatória

O revisor não encontrou erro residual em B1-TEC-01 a 10, mas B1-TEC-11 permanece incorreto: `B1.md:173–192` trata `params[:account][:config]` no update genérico de SuperAdmin como entrada de configuração de agente. O baseline prova que `/super_admin/accounts/:id` edita **Account** (`config/routes.rb:1216–1224`, `SuperAdmin::AccountsController:38–57`), e `accounts` não tem coluna `config` (`db/schema.rb:76–93`). O PATCH real de agente recebe `params[:agent][:config]` em `AgentsController:157–193` e está declarado em `routes.rb:364`.

A causa registrada não foi totalmente eliminada: a correção ainda inferiu uma entrada em vez de provar seu alvo real. O desenho precisa distinguir o PATCH real de agente, sujeito ao contrato público independentemente do ator, da rota operacional SuperAdmin nova. Isso é uma pendência para decisão posterior, **não uma correção executada nesta rodada**.

Estado final: **PARADO / B1 não aprovado / código bloqueado / retorno ao Rodrigo**. Não haverá outra correção ou revisão por iniciativa desta sessão. O artefato B1 permanece no hash enviado à final. Não houve implementação, spec nova, teste de produto local, novo push, merge, fila, deploy, instalação ou escrita em produção. As únicas leituras de produção foram Antes B1 e Q12a, autorizadas separadamente e concluídas.

## Retomada autorizada pelo Rodrigo

Após receber o resultado da parada e esclarecer que o PR documental não dispara deploy, Rodrigo respondeu “ok. Pode continuar”. Essa orientação autoriza retomar a correção local e a implementação, respeitados os gates; não autoriza merge, fila, deploy, nova consulta de produção ou limpeza de dados.

O principal corrigiu somente o alvo de B1-TEC-11 no desenho: o PATCH genérico é `/api/v1/accounts/:account_id/autonomia/agents/:id`, com `params[:agent][:config]`, inclusive quando o ator é SuperAdmin autorizado na conta. A edição de Account ficou explicitamente fora do guard de configuração de agente. Será feita uma checagem independente focada nesse achado residual; não reabrir os dez pontos já fechados. Se a checagem detectar outro erro, parar e retornar ao Rodrigo.

### Resultado da checagem focada — nova parada

A entrada e o ator foram confirmados pelo código: `SuperAdmin < User` e associação `AccountUser` tornam válido o caso de SuperAdmin autorizado usando o PATCH real de agente. Porém a tabela de casos BE-19 em `B1.md:427` ainda manda validar antes de `resource_params`, contradizendo a exclusão explícita desse método no traçado corrigido. O principal deixou essa referência antiga no passe de consistência; a correção ficou incompleta.

Conforme o limite comunicado para esta retomada, o trabalho parou novamente, sem corrigir a linha residual nem iniciar código. Subagentes de diagnóstico e mapeamento foram interrompidos. Nenhum push, merge, fila, deploy, instalação, limpeza ou nova leitura de produção. A leitura de recursos nesta retomada mostrou M4 com 16,1 GB livres, ainda abaixo da reserva de 20 GB. Telas reais permanecem pendentes.

## Segunda retomada autorizada — correção pontual e conferência completa

Rodrigo perguntou o próximo passo, recebeu a proposta de corrigir a referência antiga e conferir todas as menções ao mecanismo, e respondeu “ok. Pode continuar.” O principal corrigiu a linha da tabela BE-19 e conferiu todas as ocorrências de `resource_params`, `Administrate`, “PATCH genérico” e `params[:account][:config]` no desenho inteiro. As referências restantes a Account/resource_params apenas excluem explicitamente esse caminho. A versão enviada à checagem focada tem SHA-256 `eb6a02821cc6c44202582961628edc0e0c5e7760f372a54b4ca6a2bd9d192399`; `git diff --check` passou.

Os dez pontos já fechados não foram reabertos. Nenhum código ou teste de produto foi escrito; o mapeamento de specs e diagnóstico de espaço retomaram somente leitura. M4 com 16,0 GB livres, abaixo da reserva. Merge, fila, deploy, instalação/limpeza e novas leituras de produção continuam sem autorização específica.

### Checagem focada concluída — TEC-11 fechado

O revisor confirmou a rota, o payload bruto, o ator SuperAdmin autorizado e a tabela BE-19 corrigida. Nenhum erro residual no achado; nenhuma referência restante manda validar config de agente em resource_params/Administrate/update de Account. Hash conferido igual ao enviado e `git diff --check` aprovado. O desenho B1 pode orientar teste primeiro e implementação local, respeitados os pré-requisitos; isso não aprova código ainda inexistente nem o release.

Diagnóstico de disco sem mutação: os arquivos desta tarefa somam aproximadamente20 KB e não há runtime criado. Caches globais, histórico de sessões e snapshots de outras tarefas não foram apagados. Há capacidade no M2, mas a regra exata do snapshot oficial ainda está sendo conferida separadamente da recusa do setup pesado no scheduler.
