# Kit de demo: `AUTONOMIA_AGENTS_ENABLED` no ambiente do painel (#2991)

Data: 14/11/2026. Issue: #2991. Kit: `bin/demo`, `script/demo/no_m2.sh`.

## O problema

O `demo_env` do kit monta o ambiente do painel com `env -i`: só entra o que está escrito ali. Estavam
`CRM_KANBAN_ENABLED`, `AUTONOMIA_PACOTES_ENABLED` e `CRM_CALENDAR_MEETINGS_ENABLED`; faltava
`AUTONOMIA_AGENTS_ENABLED`. Sem ele:

- `app/controllers/dashboard_controller.rb` entrega `AUTONOMIA_AGENTS_ENABLED: "false"` ao painel;
- o guarda de `app/javascript/dashboard/routes/dashboard/autonomia/autonomia.routes.js` manda a rota para o início;
- `Autonomia::Agents::Config.enabled?` responde falso para toda conta, mesmo a marcada.

Nas demos dos PRs #2968 e #2979 a frente editou o kit à mão, religou a demo e desfez a edição no fim.

## Decisão

- `demo_env` passa `AUTONOMIA_AGENTS_ENABLED=true`, junto dos outros interruptores.
- O valor é o padrão da produção: `variable "autonomia_agents_enabled"` tem `default = true` em
  `infra/aws-chatwoot/variables.tf` e em `infra/aws-chatwoot-hub2you/variables.tf`. O valor efetivo de cada
  instalação fica fora do repositório e não foi conferido.
- `AUTONOMIA_AGENTS_GLOBAL` fica de fora. O padrão dele na produção também é `true`, mas ele só liga conta com
  credencial de IA (`Crm::Ai::CredentialResolver`), e o banco novo da demo não tem nenhuma. Ligá-lo não mudaria
  nada e sugeriria o contrário.
- O kit não marca a conta: o `up` (`script/demo/preparar_conta.rb`) não chama `enable_for!`. A marca
  (`autonomia_agents_enabled` nos atributos internos) é do arquivo de seed da demo que precisa da tela, rodado
  com `bin/demo seed`. Demo que não é de agentes segue sem a tela.

## Efeito colateral avaliado

- O Sidekiq não roda na demo. Com a conta marcada, os ouvintes dos agentes passam a enfileirar job no Redis da
  própria demo; nenhum executa. Não foi achada chamada externa feita direto no processo web.
- Os endereços da API de agentes deixam de responder 404 pelo interruptor da instalação; seguem fechados para
  conta sem a marca. Os de copiloto pedem `CRM_COPILOT_ENABLED`, que a demo não liga.
- Banco novo não tem chave de IA: a de sistema vem de `InstallationConfig` e a da conta, da integração de IA do
  Kanban; as duas nascem vazias. Nada chama o modelo.
- O kit desvia o e-mail e a Cloud API do WhatsApp para porta morta. As outras integrações ficam sem endereço. O
  endereço do modelo de IA não é desviado: se alguém gravar uma chave de verdade na demo (seed, Super Admin ou
  integração do Kanban), a chamada sai para fora e é cobrada. A proteção é o aviso no runbook, não uma trava.

## Validação

| O quê | Resultado |
|---|---|
| `bash -n script/demo/no_m2.sh` | sem erro |
| `shellcheck -x script/demo/no_m2.sh` | sem aviso novo |
| Leitura do diff inteiro | 1 linha de ambiente, comentário, runbook |
| Revisão independente (agente revisor, só leitura) | sem achado crítico ou alto; 2 médios e 3 baixos de texto, aplicados |

Achados da revisão, todos de redação: o texto dizia que "o seed põe a marca" sem dizer que o `up` não põe; dizia
que a demo "não tem chave de IA" sem dizer que isso vale só para banco novo; "só desvia e-mail e WhatsApp" virou a
lista exata; "vale `true` nas duas produções" virou "padrão `true`".

## Não verificado

- Nenhuma demo foi subida com esta mudança: a regra é não subir demo sem o OK da Orquestração Deploy, e o M4
  estava com 2,5 GB livres de memória. A prova fica para a próxima demo de tela de agentes, sem edição manual do
  kit.
- Os testes do repositório rodam só na CI do PR.

## Fora deste PR

- Demo que já está de pé: o kit novo chega à pasta dela em qualquer comando que o reenvia (`up`, `sync`, `flag`,
  `seed`, `prints`, `down`, `psql`), mas o Rails que já está rodando continua com o ambiente antigo. A chave só
  passa a valer quando o painel religar (`down` e `up`, com o OK da Orquestração Deploy).
