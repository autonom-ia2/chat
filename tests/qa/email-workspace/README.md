# QA visual das campanhas

Este ambiente renderiza os componentes Vue reais da lista, do editor GrapesJS, da biblioteca e da revisão. Usa os módulos Vuex e clientes HTTP do produto, o Tailwind do projeto e o CSS compilado do dashboard. O menu externo e a API são fixtures locais. A conta 800 é fictícia; não é a conta 16 de produção.

## Execução local

Use as versões de Ruby e pnpm do projeto, dependências instaladas e um ambiente Rails local de teste. Não carregue configuração de produção.

```sh
eval "$(rbenv init -)"
RAILS_ENV=test bundle exec vite build --mode test
RAILS_ENV=test bundle exec rails runner tests/qa/email-workspace/export_templates.rb
node tests/qa/email-workspace/server.mjs
```

Abra `http://127.0.0.1:34782/app/accounts/800/campaigns/email_campaigns`. O servidor escuta somente em `127.0.0.1`. As alterações de campanha vivem em memória e desaparecem ao reiniciar. Não há integração com SES ou IA: os endpoints de envio, teste de envio e agendamento retornam 403. A criação de campanhas e o processamento de importações não são simulados.

`?role=readonly` inicia o perfil sintético de leitura; `?theme=dark` inicia o tema escuro. Esses controles não substituem os testes de autorização do backend. Os destinos da biblioteca e do editor usam as mesmas rotas de produto. `/qa/events` mostra apenas métodos e caminhos das chamadas locais.

## Conferência

- Lista: rascunhos completos/incompletos, filtros, busca, ação Disparar, diagnóstico sob demanda e menus secundários.
- Editor: assunto, prévia, painéis de blocos/propriedades, personalização, salvamento e revisão.
- Biblioteca: 14 modelos reais, categoria e busca, modelos da conta, prévia Desktop/Mobile, cancelamento sem aplicar.
- Revisão: requisitos, remetente, exclusões, ação corretiva, confirmação final e cancelamento.
- Dimensões de 390, 768 e 1440 px: rolagem horizontal, cortes de texto, acessibilidade dos controles e galeria responsiva.

As capturas comprovam a interface implementada com dados sintéticos. Não comprovam deploy, comportamento do banco de produção nem entrega real de e-mail. A lógica de prontidão, supressão, catálogo e confirmação também é coberta pelos testes automatizados do PR.

Os textos novos seguem o catálogo canônico inglês. A atualização do catálogo pt_BR depende da autorização para a exceção às instruções de tradução fornecidas nesta tarefa.
