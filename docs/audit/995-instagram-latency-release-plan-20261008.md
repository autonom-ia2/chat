# Plano de publicação e reversão do candidato de latência

Issue #995 / PR #1155. 2026-10-08. **HOLD: este documento não autoriza merge, deploy, instalação, restart ou alteração de produção.**

## O que muda

- Chat2You: confirmação aceita gera diretamente a URL original OAuth; API/painel transportam a comprovação assinada. Publisher Ruby suporta frames num processo residente.
- AWS: a green instala o wrapper SSH da imagem exata, aceitando exclusivamente o comando fixo do canal e mantendo one-shot compatível.
- VPS: broker mantém o canal, SDK consulta CURRENT fresco por frame, sem retry. Manager pausa 1 s entre consultas, com os mesmos orçamentos e renovação.

Portanto o conjunto exige publicação do Chat2You nas duas stacks, incluindo os wrappers na própria green, e instalação do artefato VPS. Não é apenas configuração entre servidores.

## Pré-requisitos antes de pedir/liberar publicação

1. PR e CI no SHA final; revisão independente com os limites dos benchmarks. Nenhuma promoção da branch local ou auto-merge.
2. Runtime efetivo >=22.12. A inspeção fresca confirmou Node24.21.0 privado nas seis units, montado em `/usr/bin/node`; o Node18 pertence ao host. Revalidar SHA/permissões/drop-ins e executar o instalador com o mesmo bind privado conforme `995-instagram-runtime-readiness-20261008.md`. Não alterar Node/npm do host, serviços n8n ou templates systemd.
3. Artefatos imutáveis com SHA e dependências exatas; installer/smoke em ambiente isolado. A validação precisa ocorrer em ancestrais privados/root-owned, nunca relaxando a proteção para aceitar `/Users/Shared` 1777.
4. Leitura de CURRENT, versão/imagem ativa, saúde, memória/CPU do web e estado das unidades nas duas stacks. Confirmar margem para o publisher Ruby residente (RSS observado no sandbox ~262 MiB por filho; não é limite agregado). Preservar rollback de imagem e artefato.
5. Autorização explícita para o SHA final, os dois deploys AWS, instalação VPS e retorno dos dois overrides temporários de CPU200% à quota canônica50%. O runtime privado existente será preservado. Este HOLD permanece até essa autorização.

## Ordem após autorização

1. Merge pelo fluxo aprovado e imagem do SHA mergeado; não promover diretamente o worktree. Blue-green nas duas stacks, com health e confirmação de CURRENT/imagem, mantendo imagem anterior.
2. Confirmar que as greens instalaram os wrappers da imagem mergeada com one-shot preservado antes de habilitar o canal na VPS. Não executar atualização independente do wrapper nem duplicar workflow_dispatch depois do push main. Validar bootstrap/read limitado sem operação cliente.
3. Instalar release VPS imutável, dependências pinadas e Node que satisfaz o contrato do instalador. Não copiar/exibir cookies, chaves ou perfis. Preservar owners, isolamento entre stacks, limites canônicos e rollback para release anterior.
4. Iniciar apenas pelo procedimento aprovado, confirmando prewarm, cancelamento e encerramento do canal na rotação. Não aumentar CPU ou timeouts para mascarar falhas. A normalização para50% exige guardar/remover somente os dois overrides200% de SHA conhecido, conforme o plano de runtime; preservar os binds Node e registrar reversão. Não foi executada aqui.
5. Piloto observado na conta/perfil já autorizados. Autonom.ia não recebe habilitação nova de browser operations; a fronteira de contas continua a da configuração vigente. Não repetir convite já aceito ou escrever de novo um convite de resultado incerto.
6. Medir HTTP recebido → resultado publicado e clique → painel, com Meta real. Metas históricas divididas por dez estão no relatório de testes. Após aceite, abrir diretamente OAuth normal. Não usar o benchmark sintético como prova dessa etapa externa. Reautorização OAuth real e novo restart continuam exigindo aceitação funcional própria.

## Gates do piloto e rollback

Observar taxa de consultas, latência, erros, CPU/memória web/broker, Redis e renovação. Pausa de 1 s pode se aproximar de 60 leituras/min por manager ativo; o teste de cadência mediu somente o leitor SDK.

Se a cadência causar carga ou falhas, voltar a 15 s por release revisada, preservando o canal reaproveitado e OAuth direto. Se canal/SDK falhar, reverter o artefato VPS completo para o one-shot anterior, encerrando os filhos/túnel próprios antes de retomar. Se API/painel/publisher apresentar regressão, reverter a imagem AWS pela rotina blue-green e o wrapper compatível anterior. Não reaplicar frame, claim ou convite como mecanismo de recuperação.

Registrar SHA/imagem/CURRENT, saúde antes/depois e limpeza. Não registrar tokens, cookies, credenciais, URLs com estado OAuth ou dados de cliente. O aceite e a conexão real não serão declarados a partir de health, CI ou fila apenas.
