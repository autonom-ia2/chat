# #995 — revisão integrada e validação local — 05/10/2026

Escopo autorizado nesta etapa: implementação, revisão, testes, documentação e PR.
Não houve merge, deploy, mudança IAM, instalação VPS, reinício de gestores,
leitura/cópia de cookies nem escrita/limpeza Redis nesta retomada.

## Candidato

Branch `feat/995-instagram-vps-runtime`, baseada inicialmente em `8800a6ac2f`.
Gateway/noVNC, marcador de recuperação, UI SuperAdmin, serviços systemd e
publicador AF_UNIX fazem parte da mesma entrega. M2/M4 não são componentes
necessários na arquitetura de execução proposta. Migração operacional pendente.

## Revisão independente e correções

Nexo implementou/revisou installer, preflight, grupos, IAM e runbook. Íris
integrou gateway/marcador com UID próprio. Atlas implementou broker/client
limitados ao protocolo existente. Gauss repetiu contratos e lints offline.
Argos revisou o conjunto, identificou e verificou as correções seguintes:

- Chrome não compartilha UID com publicador SSH/AWS nem gateway HS256.
- Seis UIDs/oito GIDs dedicados; gateway não pertence ao grupo do publisher.
- Marker e VNC compartilhados somente pelo grupo visual: 0640/0660; pai 0710.
- Homes e nonce privados; credenciais nunca entram no ambiente Chromium.
- Expiração de ticket não permite apagar nonce e reutilizá-lo durante o grant.
  Dois testes reproduziram a falha antes do patch; ambos passaram depois.
- Installer recusa ancestrais inacessíveis antes de escrever; documentação IAM
  usa seletores por tags/Name consistentes com a política, não instância fixa.

## Validação final local

Rodada integrada às 10:12 UTC: **242 Node, 25 exemplos RSpec offline e 58 Python,
todos aprovados**, sem falhas ou skips nessas suites. ESLint, RuboCop focal e
whitespace aprovados. Guia e Central passaram seus checks anteriores à sincronização.
Os contratos Python agora criam o fixture privado dentro do projeto, evitando
confundir `/tmp` compartilhado do executor com um ancestral de produção confiável.
Nenhuma guarda de produção foi afrouxada para passar o teste.

Os requests com Devise/banco e o Chrome/VNC Linux real não foram executados
localmente. O sandbox recusou a conexão ao PostgreSQL de teste; não houve tentativa
alternativa de acesso. O workflow da PR deve confirmar essas etapas antes do aceite.
O smoke Linux usa browser e VNC reais mas identidades de filesystem sintéticas;
não representa prova de DAC/grupos/mounts entre seis UIDs reais.

## Gates operacionais e preservação

Acesso HTTPS privado por Tailscale Serve exige conferência real de certificado,
ACL e preservação de Host/path/Origin/WS. Não usar Funnel nem publicar VNC/CDP.
Identidade AWS de serviço e pares de chaves próprios continuam para provisionamento
aprovado: não copiar perfis AWS ou cookies pessoais dos Macs.
O conector SSH recusou a consulta n8n por divergência em seu known_hosts. A chave
pública apresentada coincide com uma chave previamente registrada no M4, mas não
foi removido/alterado o registro nem repetida a chamada por outro transporte.
Antes da migração, reconciliar confiança SSH e confirmar assistido OFF nas duas
stacks, retirar gestores Mac sem concorrência e validar a VPS sob rollback.
Não declarar sessão Meta, renovação, heartbeat ou mensagens homologados com CI.
Evidências locais/revisões: `tmp/resume-995-20261005/`; Project #3 relido em sete campos.
