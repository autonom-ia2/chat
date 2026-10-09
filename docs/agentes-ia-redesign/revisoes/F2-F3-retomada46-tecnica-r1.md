# Revisão técnica 1 — F2/F3 — retomada 46

**Data:** 2026-10-08  
**Escopo:** mudanças posteriores ao snapshot 43 no recorte F2/F3: normalização visual de
`n-slate-10` para `n-slate-11`, tratamento de erros e canal em `AgentCreationPage.vue`,
catálogos `en`/`pt_BR`, fixture de sessão sintética e sincronização dos testes Playwright.
Não reanalisei os 373 arquivos da linha de base nem alterei código, harness, banco ou
produção.

**Método:** leitura do código atual e dos contratos reais de canais, da máquina de estado
do Builder, da resposta de publicação e dos testes. A execução nativa do snapshot 46 ainda
estava em andamento pelo coordenador; portanto este parecer não declara testes, lint, build
ou CI verdes.

## Achado

### F2-F3-TEC-R1-01 — médio — aviso de erro da etapa Conte não é limpo após nova tentativa bem-sucedida

**Evidência:** `AgentCreationPage.vue:188-200` só atribui `entryError` no `catch` de
`onSend`/`onRetryTell`; nenhuma das duas rotinas o limpa antes de tentar novamente ou depois
de uma tentativa bem-sucedida. Ao mesmo tempo, `buildError` prioriza `entryError`
(`AgentCreationPage.vue:111-116`). O composable limpa apenas seu `error.value` no início de
`send` (`useAgentCreation.js:196-211`).

**Reprodução lógica no fluxo real:** um envio em Conte falha; `onSend` grava a mensagem
localizada em `entryError`. A pessoa clica **Tentar de novo**, ou envia a resposta outra vez;
`send` conclui, mas `entryError` continua preenchido. Como ele tem precedência em `buildError`,
o alerta vermelho permanece mesmo com a pergunta respondida e o estado avançando. O mesmo
estado residual ocorre depois de uma falha de anexo seguida de sucesso, pois `onAttach`
também não limpa `entryError`.

**Efeito:** a interface informa simultaneamente que a conversa falhou e que a etapa pode
continuar. Isso contradiz o resultado do retry e pode levar uma pessoa sem conhecimento
técnico a repetir a ação ou abandonar uma configuração que já foi salva.

**Correção mínima:** tratar o aviso local como estado da tentativa atual: limpar `entryError`
no começo de `onSend`, `onRetryTell` e `onAttach` e deixar o `catch` recolocá-lo apenas quando
a nova operação falhar. Acrescentar uma prova Playwright de falha de envio/anexo seguida de
sucesso que exija `getByRole('alert')` ausente antes de seguir para a próxima etapa.

### F2-F3-TEC-R1-02 — médio — retry de envio pode duplicar a bolha otimista

**Evidência:** o store adiciona a mensagem local antes do POST em
`autonomiaBuildThreads.js:217-227`. Em uma falha de transporte comum, o `catch` só grava
`SET_ERROR('send')` e `SET_STATUS('failed')` (`:241-256`); a remoção da bolha otimista existe
somente para a resposta HTTP 409 (`:246-250`). `retrySend` chama novamente `send` com o mesmo
payload (`useAgentCreation.js:215-216`), e esse novo `send` adiciona uma segunda bolha. O
`MERGE_MESSAGES` substitui apenas a primeira ocorrência local que coincidir
(`autonomiaBuildThreads.js:422-436`), deixando a segunda sem `local` e visível na conversa.

**Reprodução lógica no fluxo real:** em Conte, interromper o primeiro
`POST /autonomia/build_threads/:thread_id/messages` com `route.abort('failed')`, clicar
**Tentar de novo** e liberar o segundo POST. O backend confirma uma única resposta do usuário,
mas a conversa local contém duas bolhas com o mesmo texto até a navegação/reset.

**Efeito:** a pessoa vê uma resposta duplicada e pode entender que enviou a mesma informação
duas vezes. A prova da correção do `entryError` deve também contar a mensagem enviada uma única
vez depois do retry.

**Correção mínima:** remover a bolha otimista rejeitada quando o envio falhar, para que o retry
possa inserir uma única bolha; manter a proteção específica de 409 e cobrir o caminho de falha
de transporte no teste.

## Pontos conferidos sem achados

- O retorno do canal conectado usa `inbox_name`, que é o campo produzido pelo endpoint de
  canais; a resposta de publicação também é projetada pelo mesmo serializer.
- O erro técnico de Axios não chega mais ao template: `buildError` converte erros não nulos
  para a mensagem localizada `AGENTS.CREATION.errors.generic`, e a publicação usa mensagem
  localizada específica.
- O cache de sessão sintética é limitado por `baseURL`, conta e papel, reutiliza cabeçalhos
  de uma sessão legítima e não expõe tokens. Com `workers: 1`, não há concorrência entre os
  usos previstos nos testes; o script suplementar percorre os perfis serialmente.
- As trocas de `n-slate-10` para `n-slate-11` atingem textos informativos do fluxo e mantêm
  usos decorativos de `n-slate-10` em ícones/indicadores. Não encontrei `<select>` nativo no
  fluxo alterado.

## Conclusão

**Revisão 1 técnica: reprovada com dois achados médios.** A mesma lente técnica deve conferir
as correções e os testes na revisão 2. Se a revisão 2 ainda encontrar erro, registrar a causa
raiz antes da correção e repetir esta mesma lente na revisão 3, conforme a regra vigente.
