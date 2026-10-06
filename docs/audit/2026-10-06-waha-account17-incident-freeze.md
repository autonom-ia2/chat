# Incidente Hub2You / conta 17 — suspensão da publicação

Em 2026-10-06, Rodrigo informou indisponibilidade e apontou a integração WAHA da conta 17. O trabalho de publicação e histórico foi suspenso. Os agentes foram interrompidos; alterações locais incompletas foram preservadas. Nenhuma retomada operacional foi autorizada após a suspensão.

## Evidência verificada nesta investigação

- O endpoint público de saúde do Hub2You retornou HTTP 502 e posteriormente HTTP 200. O alvo do balanceador passou de unhealthy para healthy. Isso não comprova aceitação autenticada de todas as telas.
- O contêiner WAHA do Hub2You permanece iniciado desde 2026-10-02 11:32:52 UTC, com RestartCount=0 e OOMKilled=false. A imagem original permanece em produção; a candidata preparada para histórico não foi aplicada.
- A conta 17 possui 25 sessões WORKING, uma FAILED preexistente e uma sessão ausente entre as 27 sessões distintas do inventário. WORKING não comprova entrega de mensagens.
- Os registros do conector confirmam falhas HTTP 502 e 504 em tarefas relacionadas à conta 17 durante a indisponibilidade.
- O contêiner web iniciou novamente em 2026-10-06 20:29:55 UTC, com RestartCount=0 e OOMKilled=false. Há um comando SSM contendo restart do web solicitado às 20:25:31 UTC. A autoria e a causa original da indisponibilidade não foram estabelecidas por esta investigação.
- Leitura limitada das filas: messages.pull e contacts.pull não tinham tarefas ativas, aguardando ou atrasadas. As filas de entrega também estavam sem tarefas ativas ou aguardando na leitura. Não foram executadas operações de fila que alteram tarefas.
- Foram preservadas, em diretório operacional privado, as 100 tarefas message.any com falha retidas referentes à conta 17. Elas foram criadas entre 20:26:24 e 20:32:20 UTC e terminaram com falha entre 20:29:51 e 20:32:24 UTC. A retenção limita o inventário; 100 não comprova o total de mensagens afetadas.
- As 50 tarefas concluídas retidas na fila message.any pertenciam à conta 17, todas concluídas após 20:32 UTC; a mais recente consultada terminou às 20:36:52 UTC. Conclusão de tarefa não é prova independente de uma mensagem nova visível ao usuário.

## Contenção e limites

Nesta investigação foram realizadas somente leituras limitadas de metadados, filas e registros, além da preservação local privada da evidência. Não houve restart, alteração de Apps, QR, novo pareamento, mudança de imagem de produção, importação, envio, reenvio de tarefas ou alteração do banco de aplicação.

Os backups, preparação de imagem e teste isolado feitos anteriormente nesta tarefa já haviam terminado. Isso não estabelece nem exclui causalidade. A causa raiz permanece pendente.

As tarefas com falha não foram reenviadas: o conector atual grava o mapeamento após receber a resposta do Chatwoot, portanto uma resposta perdida pode deixar uma mensagem já criada sem mapeamento. Recuperação exige verificar identidade e existência antes de qualquer reprocessamento, sem retry em massa.

Publicação, histórico e testes pesados permanecem suspensos. Pendem confirmação de estabilidade do atendimento, apuração da causa e plano verificável de recuperação das mensagens afetadas.

## Retomada restrita à investigação das mensagens privadas

Rodrigo pediu como corrigir com segurança as mensagens privadas nas demais contas. Foi feita uma nova conferência somente GET, sequencial, com intervalo de 250 ms entre Apps e timeout de três segundos por consulta, sem inicialização Rails.

- Hub2You: 31 caixas elegíveis, todas com sessão WORKING, App habilitado, conta/caixa correspondentes e config.conversations.outgoing=message.
- Autonom.ia: uma caixa elegível, WORKING, App habilitado, conta/caixa correspondentes e config.conversations.outgoing=message.
- As nove caixas anteriormente excluídas continuam fora deste ajuste. Não houve escrita.
- O registro compilado do App Chatwoot instalado confirma restartOnChange=true. Não reaplicar uma configuração já correta; uma alteração do App pode reiniciar a conexão individual.
- A primeira consulta tentou ler um caminho de configuração incorreto (messages.outgoing) e o resumo local falhou. Nenhuma escrita foi executada. A conferência foi corrigida para conversations.outgoing e concluída nas duas instalações.

A configuração correta não comprova o comportamento de uma mensagem específica. O próximo passo é conferir mensagens novas já existentes, distinguindo-as das mensagens privadas anteriores ao ajuste. Qualquer correção adicional deve ter alvo exato, snapshot pequeno de configuração, releitura contra mudança concorrente, uma caixa por vez e verificação do serviço e da entrega antes de continuar. Histórico e recuperação das falhas do incidente permanecem trabalhos separados.

## Verificação autorizada com acompanhamento de memória

Rodrigo autorizou prosseguir com a conferência/correção restrita das mensagens privadas e informou aumento da memória do banco de 1 GB para 2 GB. Histórico e testes pesados continuaram suspensos.

O RDS do Hub2You foi observado em modifying, ainda db.t4g.micro com db.t4g.small pendente. Nenhuma consulta de mensagens foi iniciada nessa instalação durante a alteração. A API chegou a exceder seis segundos, embora a saúde simples respondesse. Depois, a AWS confirmou db.t4g.small, available, sem classe pendente; a API voltou a HTTP 200. A primeira medição disponível após o aumento mostrou 1.005.293.568 bytes livres, sem swap. A ampliação foi feita pelo usuário, não por esta operação.

A conferência usou Ruby/PG independente, sem Rails, uma conexão por instalação, transação READ ONLY, statement_timeout=1s, lock_timeout=500ms, idle_in_transaction_session_timeout=5s e work_mem=64kB. No Hub2You, cada consulta teve LIMIT 50 e intervalo de 250 ms; EXPLAIN sem ANALYZE recusava Seq Scan em messages. Foram consultados registros posteriores a 19:03:34 UTC (16:03:34 de Brasília), sem conteúdo de cliente no retorno. Marcadores de templates gerados pelo conector foram usados apenas como sinais diagnósticos, nunca para alterar registros automaticamente.

Resultados:

- Hub2You: 31 caixas consultadas, 1.025 registros na amostra, 514 com o marcador gerado “Enviado do WhatsApp”; todos esses 514 estavam públicos. Maior consulta individual: 0,173 segundo.
- Hub2You: 28 registros privados na amostra, sendo 21 com marcador de relatório de erro, três com marcador de chamada e quatro ainda sem classificação confirmada. Não foram convertidos para públicos. Quatro caixas das contas 6, 16, 18 e 47 tinham somente um relatório de erro no intervalo; a configuração pública está confirmada, mas falta observar mensagem normal nova nessas quatro caixas.
- Autonom.ia: 58 registros na amostra, 28 com marcador do WhatsApp, todos públicos. Os dois privados foram conferidos por IDs exatos e tinham marcador de chamada.
- Total: 542 mensagens com marcador do WhatsApp públicas nas amostras; nenhum caso privado desse marcador. Isso não comprova a origem de todos os demais registros privados nem a ausência de casos fora da amostra.
- Cinco Apps antigos presentes nas duas VPS apontavam a outros destinos/contas que não constavam do inventário das duas instalações atuais. A consulta por IDs exatos na instalação atual da Autonom.ia não encontrou as quatro caixas desses Apps. Foram preservados; configuração de outra instalação não foi atribuída às caixas atuais por coincidência de IDs.

Monitoramento de fechamento, última métrica disponível às 17:55 de Brasília:

- Banco Hub2You: 844.398.592 bytes livres (aproximadamente 805 MiB), swap 262.144 bytes, CPU mais recente 6,34%, 30 conexões. O consumo pós-reinício mudou com a retomada do atendimento; não foi atribuído exclusivamente a esta consulta.
- Banco Autonom.ia: classe permaneceu db.t4g.micro, 117.956.608 bytes livres (aproximadamente 112 MiB), swap 70.815.744 bytes, CPU 4,06%, oito conexões. Não houve aumento desta instalação nesta operação.
- Hosts da aplicação: aproximadamente 1,69 GiB livres no Hub2You e 1,77 GiB livres na Autonom.ia. Web/worker ativos; APIs locais HTTP 200. Os dois alvos ALB estavam healthy; API pública do Hub2You HTTP 200 em 0,72 segundo.

Limitações operacionais registradas:

- A primeira consulta de classificação de duas notas da Autonom.ia falhou no parser Ruby por escape Unicode gerado localmente, antes de conectar ao banco. A fonte foi corrigida, validada com Ruby 3.4.4 e executada em outra chamada; a leitura confirmou marcadores de chamadas.
- O retorno da consulta Hub2You excedeu os 24 KB da resposta SSM. Não se repetiu a consulta: um comando somente leitura do arquivo completo da execução já concluída gerou o resumo. Foram lidos o resumo completo e as linhas de resultado, não presumido sucesso pela contagem.
- A preparação local da consulta para classificar os quatro registros restantes foi bloqueada duas vezes pelo PreToolUse, com “hook chain failed closed”, sem motivo adicional. Não foi contornado o controle. Os quatro registros permanecem pendentes.

Não houve nesta retomada PUT, alteração de mensagens antigas, mudança de Apps, restart, QR, envio/reenvio, importação, merge ou deploy. Não há nova correção de produção comprovadamente necessária nas 32 configurações já públicas. Permanecem pendentes a origem dos quatro registros privados, observação de tráfego normal nas quatro caixas quietas e a recuperação das falhas do incidente. Histórico e a PR de histórico continuam suspensos.

## Retomada dos dois pontos autorizada

Rodrigo pediu explicitamente fechar mensagens públicas e histórico nas novas conexões.
A autorização anterior de publicação segura permanece; a retomada não autoriza backfill
nas caixas existentes, novo pareamento das excluídas nem retry das falhas do incidente.

Os quatro privados sem classificação foram conferidos por seus IDs exatos: todos eram
avisos de mensagem excluída no WhatsApp. Não eram mensagens comuns do cliente.
A preparação longa da consulta falhou no controle da ferramenta; foi substituída por
um arquivo Python curto e revisável, submetido normalmente ao mesmo controle. Não se
alterou nem desativou hook ou política. Ruby 3.4.4: Syntax OK; SSM
e398f3c2-388a-45ca-9e3f-6b05270fc18d: Success/0, READ ONLY, sem Rails.

Leitura adicional em seis caixas com pouca atividade, desde a conclusão do ajuste às
18:53:44 UTC, limitada a 50 registros por caixa e com as mesmas proteções: quatro caixas
das contas 6/16/18/47 continuam sem mensagem comum no intervalo; caixa 76 também quieta,
caixa 77 teve um registro público não operacional. Nenhum marcador WhatsApp privado.
SSM 694cab15-0fb9-467b-aa6f-e693e1245d3b: Success/0; consulta máxima 0,007 segundo.
Configuração pública das 32 caixas confirmada; observação de mensagem comum não existe
para todas as caixas quietas. Não foi enviado teste para clientes.

Às 18:15 de Brasília, últimas métricas disponíveis: Hub2You 766.550.016 bytes livres,
swap 262.144 bytes; Autonom.ia 111.214.592 bytes livres, swap 75.481.088 bytes.
APIs públicas das duas instalações retornaram HTTP 200 em menos de um segundo.
Não houve nesta conferência alteração de Apps, banco, sessões, imagem, restart ou importação.

A PR #1077 ainda não está publicada. CI revelou uma falha na geração versionada dos
formatos do Guia, exigindo regeneração pelo comando oficial. A revisão do histórico
também exige proteger marcadores internos de entrada externa e fixar o corte pela
primeira conexão real, com processamento serial por instalação antes de publicar.

## Consultas anteriores

- SSM somente leitura: eddedbf9-2ffb-49a0-884b-e8f01aaf2b2a e b8be44e9-ec76-415f-9720-103245ae408c, ambos Success.
- curl público limitado a seis segundos; describe-target-health; docker inspect; docker logs com janela e quantidade limitadas.
- Redis: LLEN, ZCARD, ZRANGE e HMGET limitados às filas específicas; nenhuma escrita ou retry.
- Evidência bruta contendo identificadores ou conteúdo permanece fora do Git, em diretório privado. Nenhuma credencial ou dado de cliente foi incluído neste registro.
