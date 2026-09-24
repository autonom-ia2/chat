# Issue #651 — Chamadas e Mídia dão 500 sem FRONTEND_URL

## Causa raiz

`config/environments/development.rb` definia `default_url_options = { host: ENV['FRONTEND_URL'] }`
sempre, mesmo sem a variável definida. Em `enterprise/app/models/call.rb#recording_url`,
`rails_blob_url` chamado sem host levanta `ActionController::UrlGenerationError`.

## Decisão (já tomada pelo Rodrigo, aplicada)

Só em `development`: fallback para `http://localhost:3000` quando `FRONTEND_URL` não
está definida. `production.rb` e `staging.rb` não ganharam fallback — continuam exigindo
a variável, sem mudança de comportamento.

## Mudança

`config/environments/development.rb`:
```ruby
Rails.application.routes.default_url_options = { host: ENV.fetch('FRONTEND_URL', 'http://localhost:3000') }
```

`FRONTEND_URL` já estava documentada em `.env.example` (linha 17).

## Validação

Comando (development, sem `FRONTEND_URL` no ambiente):
```
env -u FRONTEND_URL bundle exec rails runner -e development '...'
```
Resultado:
- `ENV["FRONTEND_URL"]` = `nil`
- `Rails.application.routes.default_url_options` = `{host: "http://localhost:3000"}`
- `root_url` → `http://localhost:3000/` (sem exceção)
- URL equivalente a `rails_blob_url` (`active_storage/blobs/redirect`) →
  `http://localhost:3000/rails/active_storage/blobs/redirect/fake_signed_id/x.mp4`
  (sem `ActionController::UrlGenerationError`)

Confirmado que `production.rb:124` e `staging.rb:53` seguem com
`host: ENV['FRONTEND_URL']` sem fallback — produção/staging não afetadas.

`bundle exec rubocop config/environments/development.rb`: 2 offenses, ambas em linhas
pré-existentes (68-73, `git blame` aponta commits de 2025-05-29, antes deste fix),
não relacionadas à mudança. Nenhum offense nas linhas alteradas (34-40).

## Bloqueio

Nenhum.
