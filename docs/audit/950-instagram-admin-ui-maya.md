# #950 — UI Super Admin (Maya)

## Escopo e decisões

- Worktree `950-instagram-admin-panel`, branch `feat/950-instagram-admin-panel`, nó local m4.
- Cartão separado “Instagram — automação” em Settings e submenu com path direto. Alteração mínima no helper e na view de menu; `app_configs/show.html.erb` preservada.
- View dedicada `super_admin/instagram_automation/show.html.erb`, responsiva, Tailwind, cinco campos de metadados e formulários server-side. Wrapper de uma linha no diretório plural acompanha o lookup do controller de Orion.
- Helper de apresentação traduz os fatos de `LocalStatus`; sessão armazenada/configuração presente não são apresentadas como prova de saúde remota. Gestor/Meta sem confirmação ficam desconhecidos; horário ausente fica desconhecido.
- Reconectar exige ambos os sinais booleanos exatamente verdadeiros: `operator_required` e `control_available`. Backend atual não os fornece; botão permanece desabilitado.
- Textos en/pt_BR em conjunto; labels, dicas associadas, alert de validação e região de status. Nenhuma edição de serviços/controller, secrets, auth ou produção.
- Specs de UI separados das specs backend já adicionadas por outra frente. Nenhuma alteração/reversão de trabalho alheio.

## Validação

- Ruby 3.4.4 via rbenv; `bundle check`: dependências satisfeitas.
- `maccluster work plan`: m4 elegível, m2 offline. `work run` bloqueado pelo sandbox ao escrever o recibo em `~/.local/state/maccluster/outbox`.
- RSpec pelo wrapper já existente `tmp/950-implementation/run-specs.sh`, somente exemplos `Super Admin Instagram automation UI`: bloqueado antes dos exemplos por `Operation not permitted` na conexão TCP ao PostgreSQL local 127.0.0.1:55450. Não houve teste de requisição aprovado.
- Renderização ActionView independente de Rails/banco (`ruby tmp/950-implementation/maya-render-check.rb`): 10 renderizações aprovadas, en/pt_BR e combinações de controle. Verificadas cinco labels, seis componentes, alert, regra da reconexão, ausência de select/style/script e traduções faltantes.
- RuboCop `--no-server --cache false`, cache sob tmp: três arquivos, zero offenses (helpers e spec UI).
- YAML válido e paridade de chaves en/pt_BR; `git diff --check` aprovado.
- `node scripts/guide-map/check.mjs`: mapa em dia, 180 fluxos/176 telas/zero sem explicação. Não houve alteração do roteador do dashboard nem arquivos gerados.

## Integração a fechar por Orion/Turing

- Controller HTML ainda precisa retornar erros de validação na view com `@errors`/422; hoje retorna JSON. Strings `invalid_configuration`, `saved`, `health_checked` e `operator_channel_unavailable` estão disponíveis nos dois idiomas para feedback.
- O backend atual mostra somente fatos locais. Não houve verificação real de gestor/proxy/coordenação/Meta, reconexão, navegador ou produção.
- Executar `spec/requests/super_admin/instagram_automation_ui_spec.rb` no ambiente de testes autorizado com acesso aos serviços locais.
- Sem commit, push, merge ou deploy nesta frente.
