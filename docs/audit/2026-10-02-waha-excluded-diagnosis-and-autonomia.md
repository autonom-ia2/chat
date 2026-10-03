# WAHA 2026.9.2 — diagnóstico das exclusões e migração separada da Autonom.ia

Data: 2026-10-02. Issue #874. Continuação de #869/#870 e código publicado em #873.
Estado: diagnóstico concluído; Hub2You com destinação explícita das oito exclusões; caixa apta da Autonom.ia aplicada e confirmada; decisão sobre sua caixa FAILED pendente.

## Escopo, autorizações e separação

Rodrigo autorizou diagnosticar e corrigir as oito exclusões do Hub2You e inventariar a Autonom.ia separadamente.
Após conhecer o diagnóstico, escolheu manter seis caixas antigas somente como histórico e usar as novas
já migradas. Escolheu manter as duas restantes desconectadas, preservando histórico. Essa disposição
substitui a expectativa de colocar as 33 caixas locais simultaneamente em WORKING; não foi considerada
uma autorização para recriar Apps, duplicar entregas, excluir caixas ou fazer novo pareamento.
A janela sem outros escritores foi confirmada especificamente para a única caixa apta da Autonom.ia.
Nenhuma configuração foi transportada entre instalações. Contas AWS, instâncias, frontend e endpoint
WAHA próprios conferidos antes dos comandos. Runtime web/worker publicado: 0ee03e9be768fc77d7a3a5652002e4542b651878.
Não houve alteração de código de produto, UI, autenticação, QR, logout, pareamento, schema ou histórico.
Identidades exatas, configurações e backups ficam privados, fora de Git/GitHub.

## Diagnóstico somente leitura do Hub2You

Inventário atual: 33 canais locais. As oito exclusões são:

- Seis referências históricas: App antigo retorna HTTP 404, mas a mesma sessão está WORKING e tem
  um App Chatwoot ativo apontando para uma caixa nova, já migrada. Identidade instalação/conta/destino
  confrontada. Recriar o App antigo colocaria o mesmo número em dois destinos. Não houve essa escrita.
- Uma referência sem sessão: GET da sessão/App HTTP 404 e nenhum arquivo de autenticação do identificador
  no armazenamento da WAHA correspondente. Não foi criada sessão nova.
- Uma sessão FAILED: App correto existe e está habilitado, mas o banco GOWS tem zero dispositivos,
  identidades e sessões autenticadas. Consulta SQLite mode=ro/query_only, somente contagens; nenhum
  valor de autenticação lido. Não atribuir momento ou causa histórica do desaparecimento.

A escolha do Rodrigo preserva as oito caixas e seus históricos sem nova aplicação. As seis sessões
compartilhadas continuam com Apps ativos apontando para as caixas novas já concluídas. As duas outras continuam desconectadas.
Os GETs e transações READ ONLY confirmaram ausência de escrita local/remota no diagnóstico.
O roteamento wa-hub.autonomia.site foi confirmado no serviço da VPS hubsegs; wa-hub2you é outro serviço.
Logs recentes sanitizados não continham evento da sessão FAILED; não foram usados para inventar causa.

## Inventário separado da Autonom.ia

Dois canais locais WAHA, em duas contas distintas: uma caixa WORKING com App correto/habilitado e
quatro mudanças previstas; uma caixa FAILED com App correto e zero dispositivos autenticados no GOWS.
Onze sessões remotas não significam onze caixas locais a migrar. Somente duas têm vínculo local.
Listas de Apps por sessão foram obrigatórias e validadas. O probe inicial sem filtro retornou HTTP 400;
suas marcações vazias de App não fundamentam diagnóstico. O inventário final usou GETs por sessão.
O endpoint wa-autonomia.autonomia.site foi confirmado no serviço da VPS autonomia; vsmulti é outro serviço.
A caixa FAILED não recebeu reinício, limpeza de autenticação ou QR. Sua destinação aguarda decisão explícita.

## Aplicação restrita — concluída na caixa apta

Plano para uma única caixa/conta da Autonom.ia, sem lote global: backup completo novo antes de APPLY,
validade máxima de 15 minutos, comparação integral com o backup, task publicada com ACCOUNT_ID/INBOX_ID,
N1/R1, parada na primeira falha e consulta do mesmo comando em resultado desconhecido.
Ruby 3.4.4: sintaxe dos runners validada; Python: compilação do transporte validada.
Backup inicial: SSM e51ad4bb-1b61-4954-84ac-40c6ff040126, Success/0,
2026-10-02T23:40:20.295Z–23:40:45.295Z. Arquivos root 0700/0600, hash da cópia no host conferido;
WORKING, identidade local/remota e filtro de Status verdadeiros; zero escrita de estado local/remoto.
APPLY real: SSM 41aaf3e8-00a7-4909-ae2c-81291e1cf137, Success/0,
2026-10-02T23:44:16.431Z–23:44:51.431Z. Resultado total=1, would_update=1, updated=1,
unchanged=0, skipped=failed=recovered=recovery_failed=0, halted=false. WORKING, configuração de sessão
preservada, filtro ligado, resolver único/habilitado, referência local e conversa única confirmados,
plano final vazio. Nenhum rollback necessário.
Confirmação separada GET-only/READ ONLY: SSM d7e968f1-8a2f-4040-a191-bd69454ce6bf, Success/0,
2026-10-02T23:45:26.508Z–23:45:51.508Z. unchanged=1, would_update=updated=0, zero falhas/recuperações,
halted=false, estado local inalterado. Revisão independente cavecrew do runner antes de APPLY: No issues.

Dois backups before/after foram transferidos cifrados para armazenamento privado fora da instância:
selagem SSM ec232fb4-a53f-4d05-8789-7c1a6df348a1, Success/0. AES-256-GCM/RSA-OAEP,
autenticação e hashes internos conferidos; os dois hashes também confrontados com os resultados
originais de backup/APPLY e sha256sum do host. Diretórios 0700/arquivos 0600.
Uma referência residual do transporte privado impediu uma preparação local antes do dispatch SSM
de selagem; corrigida, não houve aplicação repetida nem resultado desconhecido reexecutado.

A consulta agregada de tráfego posterior encontrou PG::GroupingError pela ordenação padrão de Message.
Foi corrigida apenas no probe privado, usando reorder(nil) antes de group/count. Comando inicial
somente leitura f00e15af-59f2-40fd-a6cc-5ac852275d6d ficou Failed/1; nenhum APPLY repetido,
nenhuma alteração de código de produto ou produção atribuída a essa consulta. Evidência terminal preservada.
Probe corrigido: SSM fb9e3fd3-913d-4f9e-a92e-03b200823f2a, Success/0,
2026-10-02T23:47:58.993Z–2026-10-02T23:48:24.993Z. WORKING, plano vazio, filtro ligado,
resolver cache/stats HTTP 200, conversa única, banco READ ONLY/cliente GET-only e estado local igual.
Após APPLY: zero mensagens comuns/zero Status observados. Isso não comprova entrega, resposta ou
reabertura reais nessa instalação; aceite manual dos três passos foi solicitado e permanece pendente.

Hub2You revalidado no runtime atual: SSM baa48a01-3459-48ef-9f4c-02dcd3b02b8e, Success/0,
2026-10-02T23:46:40.131Z–2026-10-02T23:47:28.131Z. Todas as 25 ativas unchanged=1, plano vazio,
WORKING, filtro ligado, sessões distintas, zero skips/falhas/recuperações e hash local antes/depois igual.
Nas janelas posteriores às operações originais: oito mensagens comuns/zero Status. Não é novo E2E em 25 caixas.
Saúde pública em 2026-10-02T23:48:58/59Z: HTTP 200, Chatwoot 4.18.0, queue_services=ok/data_services=ok
nas duas instalações. Nenhum merge/deploy de produto adicional ou envio de mensagem pelo operador.

## Limites de conclusão

Não afirmar 33 caixas migradas nem importar histórico para cumprir uma contagem. O resultado do Hub2You
é 25 caixas ativas migradas e oito preservadas conforme decisão explícita. A Autonom.ia exige resultado
próprio; tráfego/configuração não substituem aceite funcional que não tenha sido observado.
Documentação não altera produto nem requer outro deploy. Sem --no-verify; validação e commit separados.
A Issue #874 permanece aberta até a decisão pendente e o aceite funcional; não marcar o objetivo completo.

## Continuação autorizada — backfill e incidente de validação

Rodrigo orientou priorizar o backfill disponível sem deixar contas desconectadas impedirem a execução.
Também autorizou merge/deploy caso necessários e com estado validado. Isso não autoriza apagar histórico,
parear sessões ou afirmar que os testes manuais da Autonom.ia passaram. O backfill publicado é de
configuração de caixas existentes; não é importação de mensagens nem recálculo histórico.

Nova conferência do Hub2You: inventário SSM 7578a2f3-2770-4d18-ab25-919aa7d67351 e validação do rake
SSM 22f0c4bb-a992-4807-a9b7-f7bd6d2a557c, ambos Success/0. Mesmos 33 canais locais e mesmas oito
exclusões; as 25 ativas estão WORKING, com plano vazio, filtro ligado, sessões distintas e estado local
inalterado. Nenhuma nova aplicação necessária nessa instalação. Oito mensagens comuns e zero Status
na janela posterior às aplicações originais; isso não representa novo teste E2E em todas as caixas.

Na Autonom.ia, o operador iniciou equivocadamente duas verificações Rails de leitura em paralelo na
instância t3.small, sem conferir antes a folga de memória. Depois disso, /api deixou de responder,
ALB marcou Target.Timeout e leituras EBS cresceram para aproximadamente 7,9 GB/min entre 21:04 e 21:06
(horário de São Paulo, 2026-10-02). A atribuição exata de memória por processo ainda não foi obtida;
não apresentar a correlação temporal como causa-raiz comprovada.

As duas verificações (73c35ab5-048f-434a-acfc-8a644231964d e 8e92761e-b45d-45f9-b55c-4aedb32f3df9)
e o diagnóstico leve 2c380b2c-b992-4ad0-841b-b843ad7137fb foram cancelados, com estado Cancelled
confirmado na AWS. Nenhum APPLY repetido, escrita de configuração WAHA, logout, QR ou histórico alterado.
Plano de recuperação preparado: reiniciar somente a instância atual da aplicação, mantendo disco,
imagem publicada e configurações; conferir containers, saúde HTTP/filas/banco e ALB após o retorno.
Aprovação explícita para essa operação de infraestrutura foi solicitada e ainda não recebida.
Não iniciar novos processos Rails durante a recuperação; validações posteriores devem ser leves e
sequenciais. Merge/deploy permanece condicionado à saúde e revisão, sem trocar o runtime por suposição.
