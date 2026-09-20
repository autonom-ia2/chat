# Guia da Plataforma — consulta a plataforma inteira e faz com confirmação

Issues #533 (2ª volta) e #536 · PR #546 · branch `feat/536-acoes-com-confirmacao`

## Decisões

1. **O catálogo de leitura é derivado, não escrito.** Os cinco assuntos escritos
   à mão nunca cobririam a plataforma, e um deles ("caixas") sumiu numa
   reorganização — foi o que produziu, em produção, "houve um erro ao gerar a
   resposta" com HTTP 200 no log. O catálogo agora sai das rotas GET da API.
2. **A leitura roda como o usuário**, pela mesma API que a interface usa, com o
   `api_access_token` dele. Herda Pundit, papel, funções personalizadas e
   isolamento de conta. O que ele não vê na tela, o Guia não vê.
3. **A ação tem superfície fechada**: três ações no catálogo, só administrador,
   Pundit por domínio dentro da execução. Fora da lista o pedido é recusado, não
   interpretado.
4. **Nada executa sem confirmação.** `descrever` e `executar` são separados; o
   painel mostra os valores exatos e espera o clique.

## Validação

| O quê | Comando | Resultado |
|---|---|---|
| Specs do Guia | `bundle exec rspec spec/services/autonomia/guide/` | 35 passed |
| Regressão do CI | job "Email backend and bounded regression" | 918 examples, 0 failures |
| RuboCop | todos os `.rb` alterados, inclusive `config/routes.rb` | limpo |
| Lint do CI (e-mail) | `.github/scripts/email-protection-eslint.mjs` nos 3 arquivos de front | 0 blocking |
| Porta de produção | SSM read-only, `docker ps` no EC2 green | container em 3000, `PORT` não definida |

### Mutações testadas (6 aplicadas, 6 capturadas)

Gate de administrador, gate de verbo, catálogo fechado, escopo de conta na busca
por nome, `\b` no fim do regex de verbo, porta fixa em 3000.

**A primeira rodada passou verde nas três primeiras mutações.** Os testes não
testavam nada: caíam no `rescue` por falta de credencial. Ao corrigi-los,
apareceu um defeito real — o regex de verbo fechava com `\b` logo após o
radical, então "Configura o funil", "Vincula a caixa" e "Adiciona a etiqueta"
nunca eram reconhecidos como pedido. O Guia ignorava em silêncio.

## Revisão independente

Agente revisor, 6 categorias (SSRF, vazamento de token, prompt injection,
autorização, transação, front). Sem bloqueadores. Duas observações menores não
bloqueantes: `limpo()` não escapa aspas duplas (o texto só volta ao próprio
usuário, escapado no front) e `garantir_permitida!` fora da transação (mitigado
pelo `autorizar!` dentro de cada ação).

## O que ficou de fora do escopo da #536

A issue lista cinco ações; entreguei três.

- **Convidar usuário** — fora por regra: o CLAUDE.md proíbe delegar usuários e
  permissões por função. Não deve entrar no catálogo do Guia.
- **Ajustar horário de atendimento** — não implementado. Decisão do Rodrigo se
  entra numa próxima fatia.

O critério "o registro mostra que foi feito pelo usuário X através do Guia" está
atendido como linha de log da aplicação (conta, usuário, ação, resultado, id do
registro), não como trilha visível na interface.

## Bloqueios

Nenhum. Merge pendente de aprovação explícita do Rodrigo — merge no `main`
dispara deploy nas duas stacks.
