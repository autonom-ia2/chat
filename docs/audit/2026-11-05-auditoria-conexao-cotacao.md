# Auditoria da conexão da Cotação (AGGER) — 05/11/2026

Escopo: o caminho da conexão com o portal da corretora, ponta a ponta. Do lado do chat2you: modelo, sessão, sync,
healthcheck, scan, controller e conector. Do lado do `autonomia-adapters`: login, pdocs, sonda, varredura,
cliente HTTP e handler. Código lido em `origin/main` (chat2you e adapters `cd788c0`). Nenhuma escrita em produção.

Método: dois revisores independentes, um por repositório. Os achados que mudam a prioridade foram conferidos à
mão no código. Os números vêm de produção: CloudWatch, métricas do Lambda e a tabela
`autonomia_insurance_connections`.

## O que os dados de produção mostram

- **Zero chamadas ao adapter de 25/10 a 30/10** (métrica `Invocations` do Lambda). A conexão caiu em
  `auth_required` às 04:30 UTC de 25/10 e ficou parada sete dias, até o Rodrigo reconectar em 01/11. A mesma queda
  se repetiu em 02/11 às 06:00 UTC.
- **A métrica `Errors` do Lambda marca 0 todos os dias**, inclusive em 04/11, que teve 12 falhas de login. O
  adapter devolve o erro dentro da resposta HTTP, então nenhum alarme por essa métrica dispararia.
- **"Sessões lotadas" em 04/11:** 12 eventos `adapter.erro` entre 17:00 e 20:30 UTC, classificados como
  `unavailable`. Foi só o que restou de rastro.
- **Não existe histórico de estado.** A tabela guarda só o último status, o último erro e a última evidência, e
  cada checagem sobrescreve. Os incidentes de 25/10 e 02/11 não podem ser reconstruídos, e o adapter não registra
  login no log.
- Normal: o Lambda recebe 60 a 100 chamadas por dia, sem erro de Lambda nem throttle. O tempo médio fica entre
  1,3 e 2 s, e o máximo em cerca de 15 s (timeout em 60 s).

## Achados, do mais grave ao menos grave

### Críticos: derrubam a conexão sem volta

1. **Um 403 qualquer no login vira "senha recusada", e esse estado é terminal.** (CONFIRMADO)
   - **Onde, no adapter:** `client.ts:140-150`. Todo 401 sem envelope e todo 403 viram `auth_required`, sem ler o
     corpo, no login do agregador e no do pdocs.
   - **Onde, no chat:** `sync.rb:55-59` grava `auth_required` e esquece a sessão. `healthcheck_job.rb` só revisita
     `ready`, `degraded` e `offline`.
   - **Por que é um engano:** pelas medições do próprio código, senha errada é `401` com
     `{"message":"Usuário ou senha inválidos."}`, nunca 403. Um 403 é firewall, manutenção ou "explicit deny" do
     pdocs, e mesmo assim desliga a conexão até alguém clicar em Reconectar.
   - **Encaixa nas duas quedas de madrugada:** 25/10 e 02/11. A causa real daqueles 403 é SUSPEITA, porque não há
     log daquela época.
2. **Um 403 da própria AWS (invocação do Lambda recusada) também vira `auth_required`.** (CONFIRMADO)
   - **Onde:** `http.rb:246` lê o código HTTP da invocação pelo mesmo mapa e ignora a causa `:invoke_recusado`.
   - **Efeito:** problema de infraestrutura (permissão, relógio do SigV4, credencial da instância) cai no buraco do
     achado 1.

### Altos: falham em silêncio na frente do cliente

3. **A cada 30 minutos a Lia perde as ferramentas de cotação enquanto dura a checagem.** (CONFIRMADO)
   - **Onde:** `sync.rb:42` grava `authenticating` antes de chamar o portal. Todas as ferramentas procuram uma
     conexão `ready?`: `insurance_capabilities.rb:80/87`, `insurance_quote.rb:372`, `vehicle_lookup`,
     `cep_lookup`, `insurance_quote_proposal`, `atividade_lookup` e `declaracao.rb:192`.
   - **Duração:** a janela costuma ser de 1 a 2 s, mas chega a 60 s com login ou cold start, 48 vezes por dia.
   - **Efeito:** o turno que cai nessa janela diz ao cliente "A corretora ainda não conectou a conta do AGGER", ou
     a cotação falha com `sem conexão pronta`. O `discovering` do scan tem o mesmo efeito por cerca de 25 s.
4. **"Sessões lotadas" é tratado como "portal fora do ar, ninguém precisa agir".** (CONFIRMADO)
   - **Onde:** `session.ts:170-186`. A resposta não bate com o detector de "sessão ativa", e o adapter repete o login
     uma vez antes de sair `unavailable`.
   - **Efeito:** o corretor não é avisado de que precisa liberar uma vaga. Cada checagem de 30 min e cada cotação
     gastam mais 2 logins enquanto dura o problema, sem nenhum recuo.
   - **Pendente de medição:** se a integração, que mantém a sessão aquecida 24 horas por dia, ocupa uma vaga
     permanente da corretora.
5. **Login recusado com a sessão gravada já vencida é tentado duas vezes.** (CONFIRMADO)
   - **Onde:** `session.rb:75-81` e `:104-108`.
   - **Efeito:** dois logins por chamada. Com "Sessões lotadas", isso multiplica as tentativas contra o portal.
6. **Trocar usuário ou senha não testa a credencial nova.** (CONFIRMADO)
   - **Onde:** `connection_controller.rb:13-17` salva e sincroniza com a sessão antiga ainda viva, e marca `ready`.
     O botão Reconectar também reaproveita a sessão viva, sem autenticar de novo.
   - **Efeito:** a senha nova só é posta à prova no próximo login, até 3 h depois e muitas vezes de madrugada, onde
     cai no achado 1.
7. **A varredura de produtos dispara 78 pedidos simultâneos na rota que já bloqueou a conta no firewall.**
   (CONFIRMADO)
   - **Onde:** `capabilities.ts:128-138`. A conferência é por produto × seguradora, tudo em paralelo. O comentário
     diz "uma chamada por seguradora distinta", mas o código não faz isso.
   - **Precedente:** em 23/09, cerca de 60 pedidos simultâneos nessa rota fizeram o firewall bloquear a conta.
   - **Cadeia possível:** varredura, depois bloqueio, depois 403 no próximo login, depois o achado 1.
8. **`derrubaSessao: true` pode ser enviado sozinho.** (Caminho CONFIRMADO, efeito SUSPEITO)
   - **Onde:** `session.ts:99-102`. Qualquer erro cuja mensagem fale em "sessão… ativa" dispara o envio.
   - **Risco:** o efeito só foi medido com o mesmo usuário numa conta de teste. Se o parâmetro derrubar outro
     usuário da corretora, o adapter desconecta um colega humano sem perguntar.

### Médios

9. **Erro que não é de sessão apaga o prazo da sessão.** (CONFIRMADO)
   - **Onde:** `sync.rb:118` grava o `session_expires_at` vindo de uma resposta de falha, que não traz o prazo.
   - **Efeito:** placa, CEP, atividade e proposta ficam sem sessão até o próximo login, que não precisava acontecer.
10. **A tela mostra o diagnóstico antigo depois de um erro de login.** (CONFIRMADO)
    - **Onde:** `sync.rb:208-211`. O `mark!` não atualiza `last_failure`, `last_evidence` nem `layers`.
    - **Efeito:** a tela não pede ação ao corretor e a conexão fica parada sem ninguém ser chamado. Agrava o achado 1.
11. **Trava de linha presa durante o login, com tempo-limite de banco de 14 s.** (CONFIRMADO)
    - **Onde:** `session.rb:104-108`. O `with_lock` envolve o login, que pode levar até 60 s.
    - **Efeito:** quando o portal está lento, quem espera a trava recebe `QueryCanceled`, e a cotação gasta uma
      tentativa.
12. **O `renew!` pode apagar a sessão que outro processo acabou de abrir.** (CONFIRMADO)
    - **Onde:** `session.rb:54-57`. O `forget_session!` roda fora da trava e sem comparar o que apaga.
    - **Efeito:** um login a mais por chamada concorrente.
13. **A sonda diz "ok" mesmo com o token do multicálculo morto.** (CONFIRMADO)
    - **Onde:** `session.ts:141-147` só testa o agregador, e `capabilities.ts:273-275` engole todo erro.
    - **Efeito:** a falha só aparece na cotação.
14. **Limite de taxa (429) vira "integração desatualizada" e libera a descida da escada.** (CONFIRMADO)
    - **Onde:** `client.ts:151-156`.
    - **Efeito:** mais carga justamente quando o portal pediu menos.
15. **A leitura do corpo da resposta não tem limite de tempo.** (CONFIRMADO)
    - **Onde:** `client.ts:115-119`. O timer é limpo antes do `response.text()`.
16. **Apagar e recriar a conexão perde tudo e não libera nada no portal.** (CONFIRMADO, comissão SUSPEITA)
    - Some a comissão própria (`metadata.commission_percent`): a conexão nova volta calada para 10%. Não está
      conferido se a conta 16 tinha comissão própria.
    - Some a evidência do incidente.
    - A sessão no portal continua de pé, porque nada faz logout.
17. **Conexão presa em `discovering` volta a `ready` sem formulários.** (CONFIRMADO)
    - **Onde:** `healthcheck_job.rb:36/55` re-sincroniza sem varredura.
    - **Efeito:** toda cotação de auto é recusada até alguém atualizar a configuração.

### Baixos

- **Login de até 100 s no adapter contra 60 s de espera no chat.** O chat desiste e a nova tentativa faz mais
  logins.
- **Clique duplo em conectar dá erro 500.** `RecordNotUnique` não é tratado.
- **Página de bloqueio detectada só nos primeiros 200 caracteres.**
- **Credencial AWS buscada no IMDS a cada chamada.**

## O que está certo

- Sessão perdida renova uma vez, nunca três.
- A cotação reusa a sessão gravada e não faz login, cerca de 1 login a cada 3 h em operação normal.
- Redação de segredos: corpo omitido onde o portal devolve credencial, header Authorization nunca logado e
  credenciais cifradas no banco.
- Soluço de login (2xx sem token) com uma tentativa extra.
- Nenhuma rota chama `deslogaSessao`.
- O prazo da sessão é o menor entre os dois tokens.

## Situação (06/11/2026)

- **Bloco A no ar e conferido** (ok SHA do Rodrigo em 06/11):
  - autonom-ia2/autonomia-adapters#118 (`69e21ac`, Issue #117) cobre os achados 1, 14 e 15;
  - autonom-ia2/chat#2596 (`9ff0df90b3`, Issue #2595) cobre os achados 1, 2 e 10, mais o histórico de estado.
- **Ficou de fora de propósito:** uma linha `auth_required` sem classificação continua parada, porque pode ser
  senha errada. Ela só volta com Reconectar.
- **Bloco B em PR** (autonom-ia2/chat#2647), achados 3 e 17:
  - conexão que já serve às ferramentas não passa mais por `authenticating` na checagem;
  - durante a varredura de uma conexão já varrida, as ferramentas seguem com a configuração anterior
    (`Connection#usable?`);
  - `discovering` preso é refeito pelo healthcheck com varredura.
- **Próximo:** Bloco C (achados 4, 5, 7, 9, 11, 12 e 14).

## Ordem proposta de correção

1. **Bloco A, a conexão não morre sozinha** (achados 1, 2, 10 e o healthcheck que não revisita `auth_required`):
   - separar 403 e 401 sem envelope de senha recusada;
   - tratar o 403 da AWS como infraestrutura;
   - o healthcheck volta a tentar `auth_required` com recuo;
   - a tela mostra a falha verdadeira;
   - histórico mínimo de mudança de estado.
2. **Bloco B, a Lia não perde as ferramentas** (achados 3 e 17): o estado de checagem não esconde uma conexão
   que estava pronta.
3. **Bloco C, menos logins e menos rajada** (achados 4, 5, 7, 9, 11, 12 e 14): recuo em "Sessões lotadas" e
   varredura por seguradora distinta.
4. **Medir antes de mexer** (achados 4 e 8): capturar a resposta crua de "Sessões lotadas" e o efeito de
   `derrubaSessao` na conta de produção. Isso exige o OK do Rodrigo, porque toca usuários reais da corretora.
5. **Alarme** que não dependa da métrica `Errors` do Lambda: conexão fora de `ready` por mais de 1 h.
