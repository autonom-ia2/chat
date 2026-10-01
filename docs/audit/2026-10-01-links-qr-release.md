# Release — Links e QR code e português da interface

Autorização: Rodrigo aprovou a implementação e, em 01/10/2026, pediu explicitamente para fechar e publicar em produção.

## Escopo e revisão

Lote `release/2026-10-01-lote3`, a partir de `bd2104837da812a91587189b33b2f23daabc6583`. Inclui #824 (issue #823) e #826 (issue #825), revisados independentemente antes de integrar.

Links e QR code têm página própria após E-mails e antes de Modelos WhatsApp, com tema claro/escuro. O formulário e a consulta antigos foram removidos de Gestão de campanhas. O menu de e-mails foi renomeado para E-mails. O menu de perfil e os textos de configurações/MFA revisados foram corrigidos em português. Os catálogos Captain permanecem iguais ao baseline; nenhum recurso Captain foi ativado.

A autorização de criar/excluir links agora usa a política existente de campanhas, distinguindo visualização e gerenciamento. Não houve alteração de credenciais, configuração de autenticação, infraestrutura ou banco.

## Validação do lote completo

- RSpec: 5.230 exemplos, zero falhas, nove pendências preexistentes em quarentena. Lista fixa do processo de release mais API de links e permissões Enterprise.
- Vitest: 150 arquivos, 1.499 testes passando.
- Build Vite completo passou; avisos existentes de tamanho de chunks e Browserslist.
- Lint de proteção de e-mail: zero achados bloqueantes; 77 avisos de chaves dinâmicas.
- QA de interface de e-mail: 215 verificações passaram, zero falhas, 151 capturas. Contratos do harness: 11 testes passaram.
- Guia: build/check passaram, 170 fluxos, 171 rotas, zero explicações ausentes. Central: 175 artigos, 171 rotas cobertas. Catálogos do fork verificados.
- QA da nova página: criação, erro 422, busca, compartilhamento, QR PNG decodificado para o link rastreável, exclusão, estados vazio/erro, somente leitura, mobile e ambos os temas passaram em ambiente local com dados sintéticos.
- Matriz HTTP local usando os controladores reais: visualização GET 200, criação/exclusão sem gerenciamento 401; gerenciamento POST 201 e DELETE 204.

O CI anterior ainda esperava o formulário removido de Gestão de campanhas. O teste existente foi corrigido para exigir ausência do formulário e ausência de consultas à API de links nessa tela. Diff revisado independentemente, Prettier e QA completos passaram após a correção.

## Publicação e rollback

Um merge commit na main dispara os dois workflows oficiais blue-green, sem dispatch duplicado. Não há migrations. Antes da publicação, ambas as instalações estavam na revisão `bd2104837da812a91587189b33b2f23daabc6583`.

Rollback autorizado no escopo desta publicação: workflow oficial de cada instalação com `action=rollback` e `confirm_production=true`, retornando à instância anterior. Evitar outro lote até a verificação desta publicação.

Após o deploy, conferir sucesso dos workflows, revisão/imagem de web e worker, saúde HTTP e hashes dos arquivos entregues via SSM somente leitura, sem consultas ao banco. Evidência final será registrada no PR de release e nas issues. A checagem operacional não substitui uma sessão autenticada completa de UX em produção.
