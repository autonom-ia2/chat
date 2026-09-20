# Guia da Plataforma — lê e faz a plataforma inteira, com confirmação

Issues #533 (2ª volta) e #536 · PR #546 · branch `feat/536-acoes-com-confirmacao`

## Decisões

1. **Os catálogos são derivados, não escritos.** Os cinco assuntos de leitura
   escritos à mão nunca cobririam a plataforma, e um deles ("caixas") sumiu numa
   reorganização — foi o que produziu, em produção, "houve um erro ao gerar a
   resposta" com HTTP 200 no log. Leitura e escrita agora saem das rotas da API.
2. **Tudo roda como o usuário**, pela mesma API que a interface usa, com o
   `api_access_token` dele. Herda Pundit, papel, funções personalizadas e
   isolamento de conta. Nenhuma permissão é reimplementada.
3. **Não há área bloqueada para o administrador.** Decisão do Rodrigo em
   20/09/2026, tomada depois de eu apresentar um corte alternativo e ele
   recusá-lo. Inclui campanha (mensagem para cliente real) e credencial (pode
   derrubar integração em produção).
4. **Nada executa sem confirmação.** `descrever` e `executar` são separados; a
   tela mostra a frase, o pedido literal e um aviso próprio quando a ação apaga.

## Cobertura, conferida contra o roteador

| | Existe | No catálogo | Faltando |
|---|---|---|---|
| Leitura | 270 rotas GET | 270 | 0 |
| Escrita | 468 rotas | 468 | 0 |

As rotas com `:id` estavam fora da leitura e isso tirava 145 das 270 — o Guia
listava as caixas e não conseguia abrir nenhuma. O identificador agora vem do
modelo e entra escapado, como um segmento, nunca como pedaço de rota.

## O que substituiu as listas

Três filtros de palavra saíram: o que decidia se valia consultar a conta, o que
decidia se era pedido de ação e o que decidia se a mensagem era relato de
problema. Os três ficavam na frente de uma IA que entendia o pedido, e os três
falhavam em silêncio.

Todo o regex do Guia saiu junto, por regra do Rodrigo estabelecida hoje: campo
do KB lido por linha, parâmetro de rota procurado pelo caractere, higiene de
texto por operação de string.

O que protege agora: a pessoa lê o pedido literal e confirma; a execução usa o
token dela; o caminho é montado sempre com o id da conta dela; só administrador
executa.

## Validação

| O quê | Comando | Resultado |
|---|---|---|
| Specs do Guia | `bundle exec rspec spec/services/autonomia/guide/` | 46 passed |
| Cobertura | comparação item a item contra `Rails.application.routes` | 0 faltando |
| RuboCop | todos os `.rb` alterados, inclusive `config/routes.rb` | limpo |
| Lint do CI (e-mail) | `.github/scripts/email-protection-eslint.mjs` | 0 blocking |
| Porta de produção | SSM read-only, `docker ps` no EC2 green | container em 3000 |

### Mutações aplicadas e capturadas

Gate de administrador, catálogo fechado, escopo de conta na busca por nome,
parâmetro de rota sem escapar, parâmetro vazio na ação, id vazio na leitura,
total descartado no corte da lista, porta fixa em 3000, e o `\b` no fim do
antigo filtro de verbo.

**A primeira rodada de mutação passou verde em três.** Os testes não testavam
nada: caíam no `rescue` por falta de credencial. Ao corrigi-los apareceram dois
defeitos reais — o filtro de verbo nunca reconhecia a palavra conjugada
("Configura o funil" era ignorado) e a leitura descartava o total ao cortar a
lista em 25, o que faria o Guia responder "você tem 25" a quem tem 300.

## Revisão independente

Dois agentes revisores. O primeiro, sem bloqueadores. O segundo, adversarial
sobre a camada de escrita, apontou três furos no bloqueio por nome
(`contacts/:id/call`, `reset_access_token`, `rotate_hmac_token`) — confirmados
contra as rotas reais e depois tornados irrelevantes pela decisão de não
bloquear área nenhuma.

Apontou também que a confirmação é garantida só pela tela, sem token de estado
no servidor: `executar_acao` aceita uma chamada que não passou por
`preparar_acao`. Avaliado como risco baixo — quem chama já é administrador
autenticado e poderia usar a API direto. Não foi implementado; fica registrado
para decisão do Rodrigo.

## Risco aceito, por escrito

Com campanha e credencial no catálogo, um clique em "Confirmar" pode mandar
mensagem para cliente real ou rotacionar credencial de produção. Não há desfazer
para nenhum dos dois. A tela de confirmação é a proteção, e mostra o pedido
literal justamente por isso.

Um teste fixa o catálogo de escrita e falha quando entra rota nova, nomeando
qual: o catálogo cresce sozinho com o produto, e esse crescimento não pode ser
silencioso.

## Bloqueios

Nenhum. Merge pendente de aprovação explícita do Rodrigo — merge no `main`
dispara deploy nas duas stacks.
