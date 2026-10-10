# Trocar a caixa de WhatsApp de conta (#1217)

## Contexto

Uma caixa de WhatsApp oficial precisava sair do portfólio da Meta da Autonom.ia para o portfólio do próprio cliente (conta 3). O botão "Reconectar" do Chatwoot não servia: reenvia o `business_account_id` e o `phone_number_id` guardados e só aparece para caixa `embedded_signup` que já caiu. Cadastrar o número como caixa nova falha (telefone único) e dividiria histórico, robô, funil e agentes.

## Decisões

- **Mesma caixa, credencial nova.** O backend do Chatwoot já troca a conta numa caixa existente (`Whatsapp::ReauthorizationService`): confere o número, grava conta/número/token novos, limpa o `business_management_token` e reassina o webhook. A tela nova só manda os IDs que a Meta devolve.
- **Migração oficial da Meta descartada para este caso.** Ela exige nome exibido aprovado e as duas empresas verificadas. Todo número no portfólio Autonom.ia tem o nome `DECLINED`, e a empresa de destino não é verificada.
- **Empresa sem verificação conecta.** Levantamento só de leitura na Graph API, em 10/10/2026: cinco clientes ativos estão em portfólio `not_verified`, com nome `AVAILABLE_WITHOUT_REVIEW` e limite `TIER_250`. Verificar é recomendação, não requisito.
- **Coexistência ou número direto:** a escolha fica na janela da Meta (`featureType: whatsapp_business_app_onboarding`, configuração v4). O diálogo explica as duas opções antes de abrir o Facebook.
- **Tirar o número da conta antiga fica manual** no Gerenciador do WhatsApp. É irreversível, e o diálogo só explica como fazer.
- **Construção aditiva.** A tela é um componente novo. O backend usa `prepend` (`config/initializers/whatsapp_switch_account.rb`):
  - erro tipado quando o número devolvido não é o da caixa;
  - `ready_to_receive` na resposta, porque a assinatura do webhook falha em silêncio;
  - quando a conta muda, descarta os modelos da conta antiga e agenda a sincronização dos novos.
- **Nome da caixa:** o serviço do Chatwoot renomeia a caixa para o nome verificado da conta nova. Comportamento mantido; em aberto com o Rodrigo.

## Validação local

- RSpec: `spec/services/whatsapp/switch_account`, `spec/controllers/api/v1/accounts/whatsapp/`, `embedded_signup_service_spec`, `reauthorization_service_spec`, `webhook_setup_service_spec` e `models/channel/whatsapp_spec`. 102 exemplos, 0 falhas.
- Vitest: `settings/inbox/` com timeout maior, por carga da máquina. 14 arquivos e 170 testes passaram. Depois disso, o spec da tela nova (`WhatsappSwitchAccount.spec.js`) foi ampliado para 11 testes, que passaram.
- RuboCop nos arquivos novos: sem ocorrências. ESLint: 0 erros, e o `--fix` só mudou formatação.
- `pnpm i18n:fork:check` passou, e `pnpm guia:check` está em dia (sem rota nova).
- Visual: a tela real foi renderizada num harness local com Tailwind e componentes do projeto, nos dois temas e em 500 px.
- Revisão independente: 1 achado grave e 6 riscos. Foram corrigidos:
  - fluxo vivo ao fechar e reabrir o diálogo;
  - botão liberado só depois de o SDK do Facebook carregar;
  - falha de rede separada de recusa da Meta;
  - aviso quando ligar o recebimento falha;
  - modelos da conta nova sincronizados;
  - números de telefone tirados do log.
