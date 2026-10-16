# Ponto único fora da janela de 24 h (#1587, C+D do épico #1585)

Dono: chat Modelos WhatsApp. Quem pluga: Followup IA (pré-voo e envio) e, depois, Agendamento (#1524).
Código: `app/services/whatsapp/templates/envio_fora_da_janela.rb` e a pasta `envio_fora_da_janela/`.

## Contrato (comentário de 15/10/2026 no #1587)

- `planejar(inbox:, tipo:, com_valor: false, ja_recusado: false, contato: nil, criar: true)` devolve um plano em JSON
  simples, com `caminho` `modelo`, `criando` ou `equipe`. Janela aberta e Híbrido são decisão do Followup (`MessagingWindow`).
- `enviar(inbox:, plano:, valores:, contato: nil)` NÃO envia: relê o modelo na Meta (`DispatchCheck`) e devolve o
  metadata do `MessageSender` (`template_name`, `template_language`, `template_category`, `template_params_category`,
  `template_processed_params`, `message_body`) mais o registro `envio_fora_da_janela`.
- `encaixar_tipo(account:, texto:)`: follow-up livre (decisão do Rodrigo, "IA encaixa num tipo"); `previa(plano:, valores:)`.
- Cada motivo de `equipe` tem texto em `crm.service_reminders.aviso.*` (en e pt_BR), conferido por spec (`MOTIVOS`).

## Ordem do plano

1. O modelo do tipo aprovado (cobrança: o pronto fixo de `Finalidades`; os outros: `c2y_<tipo>_<caixa>`).
2. Um aprovado da caixa que o Jev julga compatível, entre os que as regras deixam usar (pulado com `ja_recusado`).
3. O modelo do tipo em análise: `criando`.
4. Criar o do tipo (só com a 1ª marca; tipo MARKETING também com a 2ª), IA pelo propósito + `Garantir`: `criando`.
5. `equipe`, com o motivo.

## Decisões tomadas nesta entrega

- Cobrança segue nos prontos fixos (#1535, já aprovados nas caixas); a IA escreve só andamento, retorno, retomar contato
  e "deu certo?". Campos que a IA pode usar: `cliente.primeiro_nome`, `minha_empresa.nome`, `negocio.titulo`
  (obrigatório). A etapa do funil ficou de fora: o nome da etapa é interno da equipe.
- O modelo escrito pela IA é só corpo (sem botões, cabeçalho ou rodapé): o envio do Followup manda só `body`.
- Categoria pelo propósito: retomar contato = MARKETING; os outros = UTILITY. `retorno` como UTILITY é leitura nossa
  (o cliente pediu o retorno e a mensagem não oferece nada); se a Meta aprovar como MARKETING, a regra de uso pede a 2ª marca.
- Limites: 250 modelos na lista da caixa (teto do portfólio não verificado) e 100 criações por hora por WABA (contador
  no Redis por WABA e hora, SET NX EX + INCR, contado ANTES da IA). Falha da IA guardada 30 min por (caixa, tipo).
- Trava de criação por (caixa, tipo): 5 min, o dobro do pior caso medido (redator 50 s + `MetaClient#create` ~90 s).
- No envio, a regra de uso roda de novo (2ª marca desligada depois do pré-voo vai para a equipe) e a conferência precisa
  ter vindo da Meta: lista guardada não basta (`conferencia_sem_meta`). MARKETING sem contato: `sem_contato`.
- Candidatos ao "compatível": só pt_BR; modelo do sistema de outro tipo deste ponto (`c2y_*`) não entra; modelo da conta
  entra em qualquer categoria. Pausado/recusado do tipo bloqueia só aquele modelo.

## Redação por propósito

O prompt compartilhado `whatsapp_modelo.md` (tela de Modelos) não muda nesta entrega (decisão nova = PR próprio). A
regra de categoria do tipo vai no `pedido` da chamada ao redator, só neste caminho (`Redator::REGRA_DA_CATEGORIA`).

Juiz do eval (#1333): a rubrica da calibração não está no git (scratchpad da sessão). Itens para a próxima rodada:
- "andamento": serviço só se cita o pedido, diz em que pé está e o próximo passo; oferta, urgência ou "aproveite" elimina.
- "retomar contato": opção marcada como serviço elimina (a Meta trata como marketing mesmo quando o cliente pediu).

## Registro por envio

Vai no metadata (`envio_fora_da_janela`: tipo, caminho, escolha, modelo, idioma, categoria, origem, `consentimento_id`)
e no log (sem texto do cliente). Na tabela própria `whatsapp_out_of_window_sends` (PR #1587b, depende do #1631), uma
linha append-only por mensagem: o Followup chama `EnvioForaDaJanela.registrar_envio(message:, registro:)` numa linha
depois do `:sent` do `MessageSender`, com o hash acima mais `crm_follow_up_id` e `motivo` (opcionais).
- Idempotente por `message_id` (índice único; a corrida devolve a linha que ganhou).
- Nunca levanta: em erro, log com a classe e os ids e devolve nil. Grava num savepoint, para não invalidar a transação
  de quem chama.
- Guardada para sempre (Rodrigo, 15/10/2026: "Sim, trava no banco"; "Precisa guardar porque o cliente pode entrar na
  justiça tempos depois"): sem chave estrangeira, conta, caixa, mensagem, follow-up ou autorização apagados deixam a
  linha intacta, com o id de origem. Na criação, o model confere que cada referência existe e é da conta.
- A linha gravada não muda nem sai: o app recusa (`readonly?`) e o Postgres também (gatilho BEFORE UPDATE OR DELETE por
  linha e BEFORE TRUNCATE). O mesmo vale para `whatsapp_template_consents` (migration 20261104100000, que também tira as
  FKs de conta e usuário e grava `user_name`).
- Gatilho nos bancos de teste: o dumper do `hairtrigger` (já no Gemfile) escreve função e gatilhos no `db/schema.rb`
  como bloco `execute`, e o `db:schema:load` (local e CI) os recria. A suíte limpa por transação, sem TRUNCATE.
- A trava é contra comando comum (UPDATE/DELETE/TRUNCATE do app ou de psql). O dono da tabela ou um superusuário ainda
  conseguem `ALTER TABLE ... DISABLE TRIGGER`, `SET session_replication_role = replica`, `DROP TRIGGER` ou `DROP TABLE`.
  Correção legítima (aceite gravado errado, pedido de LGPD) = migration revisada que desliga o gatilho, corrige e religa.
- Volta (`down`) das duas migrations: recusa com `IrreversibleMigration` se a tabela tiver linha; vazia, tira gatilhos e
  função (a de envios apaga a tabela; a de autorização tira `user_name`) e nunca recria FK com cascade.
- `user_name` na tela: a cópia gravada primeiro; o usuário atual só para linha antiga sem cópia (gravada pelo código
  antigo durante o deploy, risco aceito pelo Rodrigo em 15/10/2026).
- Falha ao gravar o registro de envio: log e alerta no `ChatwootExceptionTracker`, só com ids e classe; sem nova tentativa.

## Decisões do Rodrigo (15/10/2026)

- "retorno" fica UTILITY ("Ok assim").
- O registro por envio terá TABELA própria (append-only), em PR separado, não neste.
- `encaixar_tipo` (chamada paga que pode vir do painel, pedido do Followup IA): cache de 24 h por conta e SHA-256 do
  texto sem os espaços das pontas, guardando também o "nenhum".
