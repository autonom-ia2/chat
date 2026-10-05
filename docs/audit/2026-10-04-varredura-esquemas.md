# Varredura dos esquemas JSON em produção (#932, AC-G5)

Data: 04/10/2026. Aprovação: D1 do PRD das 5 frentes. Só leitura: sem `valid?`, sem `save`, sem
callbacks. A saída tem só contagens.

## Como rodou

- Script: `script/guia/varredura_esquemas.rb` da branch `feat/932-guia-manual-completo`.
- Produção ainda não tem os esquemas nos modelos. Por isso foi gerado um invólucro: os arquivos de
  esquema da branch, carregados só dentro do processo do `rails runner`, mais o mapa coluna → esquema.
  Nenhum arquivo do servidor foi alterado.
- O invólucro foi testado antes num banco local, com o código da main. Ele recusou `assign_team ['999']`
  (id em texto), como esperado.
- Caminho:
  - SSM → `docker cp` para dentro do `chatwoot-web` → `bundle exec rails runner`;
  - Hub2You pelo perfil `hub2you`, instância green do deploy 37165576077;
  - Autonomia pelo perfil `financial`, instância green do deploy 37165576085.

## Resultado

| Stack | AutomationRule | Macro | Crm::StageAutomationStep | Recusados |
|---|---|---|---|---|
| Hub2You | 7 (conditions e actions) | 0 | 0 | **0** |
| Autonomia | 0 | 0 | 25 (action_config) | **0** |

Nenhum registro de produção deixa de salvar com os esquemas novos, então não é preciso nenhum ramo
`deprecated`. O AC-G5 está cumprido.
