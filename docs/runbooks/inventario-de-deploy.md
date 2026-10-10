# Inventário de deploy (modelo)

A sessão Orquestração Deploy só assume a fila de um projeto depois que este inventário existir **no repositório do
próprio projeto** (decisão do Rodrigo em 10/10/2026, ao estender a orquestração a todos os projetos). Copie este
arquivo, preencha a coluna do projeto e mande o PR. Campo sem resposta conhecida fica "a confirmar". Não chute.

| Campo | O que responder | chat2you (exemplo) |
|---|---|---|
| Como sobe | o que dispara o deploy e onde ele roda | push na `main` → `deploy-hub2you-blue-green.yml` e `deploy-autonomia-blue-green.yml` (blue-green, dois stacks) |
| O que não dispara | caminhos ignorados pelo deploy | `.github/**`, `docs/**`, `*.md` e outros nas negações do filtro `paths` dos dois workflows |
| Rollback | comando ou job exato e quanto tempo leva | job `rollback` do mesmo workflow (volta ao target group anterior); só a instância imediatamente anterior é mantida |
| Migrations | quando rodam e se há volta | no `deploy.sh` da instância green, antes da troca de tráfego; blue e green usam o mesmo banco, então a migration precisa servir aos dois; só aditivas sem o Rodrigo (`docs/processo-de-release.md`) |
| Acesso à produção | como ler e escrever no banco e nos logs | só `psql` via SSM; nunca `rails runner`/`console` |
| Segredos e env | onde ficam (nome, nunca valor) | parâmetro SSM `/chatwoot/prod/env` de cada stack |
| Compartilha com | o que outro projeto também usa (VPS, banco, rede, imagem base) | a confirmar |
| Fila | painel e rótulos | Issue #1237, rótulos `fila:*` e `hotfix` |
| Testes que travam | o que precisa estar verde antes do merge | `testes.yml` (8 shards RSpec + Vitest), lint, Guia/Central |
| Quem aprova o quê | o que fica com o Rodrigo | tabela "Quem decide o quê" em `docs/processo-de-release.md` |
