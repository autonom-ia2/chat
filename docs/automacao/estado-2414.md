# Automação livre (épico #2414): estado e passagem

Atualizado em 18/11/2026. Esta é a página que outra sessão deve ler antes de mexer na Automação livre. O desenho do
épico está no corpo da #2414 e no ADR. Os detalhes de cada parte estão nos documentos desta pasta.

## 1. Em uma frase

O épico está entregue em código. As fases F0 a F9 estão na main, os 20 exemplos dos termos de aceite rodam de ponta a
ponta na CI, e os 6 passos novos estão no ar e ligados em todas as contas. O que **não** aconteceu:

- conferir os passos novos no uso real;
- montar os 20 exemplos em produção;
- fazer a rodada única com IA real.

O épico #2414 segue aberto. Fechá-lo é decisão do Rodrigo.

## 2. O que está no ar

| Parte | PR | Commit na main |
|---|---|---|
| Lote 1 da força-tarefa (26 Issues) | #2930 | `e600f5691f` |
| Lote 2: gatilhos, etapa de entrada, ensaio dos gatilhos novos | #2941 | `addc665d48` |
| "Automações deste card" e "desta etapa" no CRM (F6.3/F6.5) | #2958 | `74c6b8f508` |
| Selo "Já é cliente desde…" no card (#2710) | #2961 | `f9e06349e7` |
| Pedir aprovação, Marcar reunião, Pesquisa de satisfação (#2931, #2935, #2936) | #2959 | `9e6424b488` |
| Para cada, Usar outra automação, Buscar em outro sistema (#2932, #2933, #2934) | #2960 | `90aa12888b` |
| "Parar para este card" fecha também as filhas da lista e do bloco (bug #2978) | #2983 | `e26271b3de` |

Todos tiveram "ok SHA" do Rodrigo. As worktrees e as branches deles já foram limpas.

## 3. Flags em produção

- As 12 flags que os 20 exemplos usam estão ligadas em todas as contas (Hub2You e Autonom.ia).
- `automacao_no_crm` está na posição 48 (1 << 47) e ligada em todas.
- `automacao_passos_novos` está na posição 47 (1 << 46). O Rodrigo mandou ligar em todas em 13/11, e ela foi ligada sem a
  conferência em tela que estava prevista. A Orquestração guardou o valor anterior de cada conta. Desligar é o rollback:
  - o salvar recusa a receita que tem um dos seis passos;
  - a execução que chega num deles para ali, com o motivo `passos_novos_desligados`;
  - o "para cada" não abre mais filhas.

## 4. O que a produção mostra (13/11)

- O motor novo já roda em uso real numa conta, com automações convertidas das regras antigas, e não há falha
  registrada.
- Nenhum dos 20 exemplos foi montado em produção.
- Os passos de IA só rodaram contra o dublê da CI. A rodada com a IA real é paga e exige OK e orçamento do Rodrigo
  (`F9-fechamento-20-exemplos.md`, seção 3.4).

## 5. O que falta

| O quê | Onde | Quem decide |
|---|---|---|
| Conferir no uso real um caso de cada passo novo e o "Parar para este card", com prints 390/1440 | #2982 | fazer quando houver máquina para demo |
| Limite no "Testar consulta" e texto do aviso "passos novos desligados" (não começado) | #2977 | — |
| Consultas Premium em lote no passo Buscar | decisão de cobrança | Rodrigo |
| Montar os 20 exemplos numa conta de teste em produção e rodar a IA real uma vez | proposta, sem Issue | Rodrigo (OK + orçamento) |
| Avulsas da Automação livre, sem vínculo com o fechamento | #2413, #2556, #2597, #2523 | — |

Os 125 prints do protótipo dos passos novos ficavam fora do git, na worktree `2414-ft-c1-telas`. Em 18/11 essa worktree
e o snapshot `20261112-070227-430eed8b…` já não existiam (outra limpeza os removeu). Os prints novos sairão da
conferência da #2982.

## 6. Onde está o código

- **Parar para este card:** `app/services/autonomia/automacao/no_card.rb`, no `parar!`. Fecha as execuções do card e
  as descendentes, achadas pelas marcas de evento `em:`, `lista:` e `bloco:`. Marca as terminadas com
  `textos._parou_por` e repete a passada até não achar mais nada, com o teto `Bloco::ACIMA_MAXIMO`.
- **Barrar filha nova de mãe parada:** `Execucao.nao_abre_filha?`, em `app/models/autonomia/automacao/execucao.rb`.
  `FilhasDaLista` e `FilhasDoPasso` conferem com `FOR UPDATE`, dentro da transação de cada filha.
- **Passos novos:** `passos_novos.rb`, `passos_que_esperam.rb` e `bloco_no_executor.rb`, todos em
  `app/services/autonomia/automacao/`. O protótipo e as decisões de tela estão em
  `docs/2414-prototipos/passos-novos.md`.
- **Os 20 exemplos:** `spec/fechamento/automacao/exemplo_01` a `exemplo_20`; `pendentes_spec.rb` está vazio. O desenho
  está em `F9-fechamento-20-exemplos.md`.

## 7. Lições para quem pegar daqui

1. **Merge.** O pedido de OK vai à Orquestração Deploy, nunca direto ao Rodrigo. Ele leva:
   - PR e head de 10 caracteres;
   - uma linha leiga;
   - CI do head;
   - revisão independente;
   - parecer da sessão Funções;
   - migration e flag.
2. **Geradores, nesta ordem:**
   - `RAILS_ENV=test bundle exec rails autonomia:guia:formatos`;
   - depois `autonomia:guia:automacao`, que lê os formatos;
   - depois `pnpm guia:build`.

   Os formatos dependem do padrão das colunas no **banco de teste local**. Antes de gerar, aplique cada migration
   pendente com `RAILS_ENV=test rails db:migrate:up VERSION=…` e depois rode `git checkout -- db/schema.rb`. Sem isso,
   o `formatos:check` local diz "em dia" e a CI reprova.
3. **Depois de juntar a main,** rode o rubocop em todos os `.rb` do PR: o job "Email backend" da CI cobre os arquivos
   tocados. Revisor que só lê não pega erro de API do ActiveRecord. Exemplo: `where(relação com OR)` lança
   `ArgumentError` no Rails 7.2.
4. **PR em conflito com a main não roda CI** (o GitHub não dispara os workflows de pull_request). Se a CI não começou,
   confira o conflito antes.
5. **Teste é só na CI.** M2 e M4 não rodam rspec nem vite build.
