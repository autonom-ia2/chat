# #960 — retomada operacional de 04/10/2026

## Estado e limites

Redis dedicado e acesso SSH restrito concluídos no host autorizado `n8n` nesta rodada.
Aplicação não publicada; nenhum merge, entrada na fila ou deploy foi solicitado.
A distribuição automática de chaves/credenciais ao SSM foi bloqueada pela ferramenta antes de iniciar.
Essa operação não foi repetida por outro caminho. O utilitário de parâmetros é destinado à execução pessoal do operador, com confirmação interativa.
Túneis AWS, ligação das stacks e sessão administrativa real permanecem dependentes da preparação operacional; não inferir sucesso dessas etapas.

## Retomada do host, sem reinstalação

Gauss revisou a continuação do provisionador; Argos revisou isolamento e as provas.
Reutilizados container, volume, bridge, certificados, credenciais e marcador existentes.
Não foi reexecutado o provisionador NEW ONLY nem inicializado novamente o epoch.
Verificação real às 15:31 UTC: TLS/certificado/hostname válidos; PING autenticado;
marcador remoto igual ao arquivo original e sem expiração; AOF habilitado e saudável,
`appendfsync=always`, `aof-load-truncated=no` e `maxmemory-policy=noeviction`.
ACL DRYRUN dos usuários das stacks: leitura do epoch permitida, SET/DEL negados,
FLUSHALL/CONFIG negados e escrita no prefixo de convites permitida. Nenhuma escrita real no epoch.

Concluída somente a seção SSH pendente: usuário dedicado, chaves públicas já existentes,
restrições por destino, configuração efetiva conferida e recarga do serviço SSH.
Chaves das stacks permitem Redis loopback e o proxy aprovado; chave M4 permite somente proxy.
Não foi distribuída credencial administrativa Redis. O endpoint Redis continua em `127.0.0.1:6381`.

## Prova real de persistência — 15:38 UTC

Teste previamente revisado por Argos e executado com Python sem otimização:
coordenador inicialmente com apenas o marcador, uma chave de teste com UUID/180 segundos,
SET NX e WAITAOF na mesma conexão e confirmação de fsync local antes do reinício.
O segundo usuário não substituiu a reserva. Reiniciado somente o container novo:
reserva, expiração absoluta e epoch originais preservados. Eliminada apenas a chave própria de teste.

Nomes/versões dos 27 serviços existentes e horários de início dos outros 46 containers
permaneceram iguais. Isso prova preservação nessa janela; não é promessa de impacto zero
para qualquer carga nem teste de perda definitiva do host/disco. A proteção aprovada de 24 horas não foi alterada.
Recibos locais: `tmp/final-orchestration-20261004/dedicated-redis-verification.json`,
`ssh-completion.json`, `dedicated-redis-durability.json` e revisão `durability-review.md`.

## CI e código

Aplicado o aviso do Claude: atualizadas serialmente as branches de #937, #956 e #962,
sem retarget, merge de PR ou entrada na fila. A release foi sincronizada no head `8f076988f2`,
que contém a main `5b9807f585` e o novo CI #961. Nexo revisou a composição.
Somente `state=MERGED` será evidência de merge; retorno de enqueue não é publicação.
Os cinco checks exigidos são RSpec agregado, Vitest, trava, central e fork-i18n.
Contratos específicos Instagram continuam exigidos por esta entrega, mesmo não obrigatórios no ruleset.

Íris restringiu os usuários de configuração Redis a `ig_hub` e `ig_auto`;
usuário administrativo, ausente, codificado e senha com quebras de linha são recusados.
O utilitário humano publica somente quatro parâmetros dedicados por conta, sem overwrite,
com confirmação TTY, identidade AWS fixa e conferência por leitura após cada criação.
O modo padrão apenas verifica metadados. Não transporta a senha administrativa Redis.
Guia: [parâmetros dedicados](../runbooks/instagram-coordination-parameters.md).

## Dependência operacional restante

Metadados AWS confirmaram os oito parâmetros ainda ausentes. A simulação de IAM permitiu
`ssm:GetParameter` nos quatro caminhos de cada stack; não foi aplicada alteração de IAM.
Simulação não substitui descriptografia/conectividade real após criar os parâmetros.
Executar a etapa humana, depois instalar e provar túneis com chaves restritas, preservando
ambientes da aplicação. Só então ligar o gestor e homologar sessão/renovação/Meta.
O CI e o parecer final do complemento serão vinculados ao SHA publicado no comentário da PR.

## Complemento de encerramento

Argos aprovou o código do utilitário para execução pessoal com TTY após corrigir
controles de URL, donos confiáveis e diagnóstico com códigos estáticos. Execução automática
inclusive do modo de metadados foi bloqueada; o operador recebeu um único comando local.
Nenhuma transferência alternativa de credenciais foi executada pelo coordenador/agentes.
Validação final local: 19 testes do utilitário, 16 do runtime de coordenação, 4 do
provisionador simulado e parsing YAML aprovados. O workflow preserva `-v` do teste existente
e adiciona a nova suíte offline; não desativa testes ou regras.

M4, 15:52 UTC: teste público pelo upstream Direct retornou CONNECT/HTTP 200/200,
com saída residencial esperada, sem credencial nem chamada Meta. Íris confirmou no código
que M4 direto e backend via túnel podem manter a mesma identidade canônica do proxy.
Portanto, túnel adicional M4→n8n não é necessário para a ativação inicial. Não copiar a
chave `ig_m4.key` para suprir uma dependência inexistente. Mudança do IP público do M4
pode exigir nova autorização Webshare; não é resolvida pelo fingerprint.
A ligação AWS→n8n e os testes reais entre stacks continuam necessários após os parâmetros.
