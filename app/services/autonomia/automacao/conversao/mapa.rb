# O mapa da F9 (#2568, épico #2414): o que cada pedaço dos motores antigos vira no motor novo, e o que ainda não tem
# equivalente, com a fase em que entra. Ver docs/automacao/F9-conversao-do-antigo.md.
#
# Só tabela, sem efeito. O Relatorio lê daqui; o conversor (F9, com escrita) vai ler do mesmo lugar, para o relatório e
# a conversão nunca dizerem coisas diferentes.
module Autonomia::Automacao::Conversao::Mapa
  # Evento da regra antiga → gatilho do motor novo. nil = sem gatilho equivalente hoje (a falta diz a fase).
  GATILHO_DA_REGRA = {
    'conversation_created' => 'conversa.criada',
    'conversation_opened' => 'conversa.aberta',
    'conversation_resolved' => 'conversa.resolvida',
    'message_created' => 'mensagem.criada',
    'conversation_updated' => nil
  }.freeze

  # Gatilho da automação de etapa → gatilho de card (F6, #2554).
  GATILHO_DA_ETAPA = { 'on_enter' => 'card.entrou_na_etapa', 'on_exit' => 'card.saiu_da_etapa' }.freeze

  # Chave da condição antiga → caminho de valor do motor novo.
  CAMPO = {
    'inbox_id' => 'conversa.caixa_id', 'status' => 'conversa.status', 'priority' => 'conversa.prioridade',
    'assignee_id' => 'conversa.responsavel_id', 'team_id' => 'conversa.time_id', 'labels' => 'conversa.etiquetas',
    'email' => 'contato.email', 'phone_number' => 'contato.telefone', 'message_type' => 'mensagem.tipo',
    'private_note' => 'mensagem.privada', 'crm_pipeline_id' => 'card.funil_id', 'crm_stage_id' => 'card.etapa_id',
    'crm_card_status' => 'card.status'
  }.freeze

  # Atributo personalizado: o tipo antigo → a base do caminho novo (`<base>.<chave>`).
  BASE_DO_ATRIBUTO = { 'conversation_attribute' => 'conversa.atributos', 'contact_attribute' => 'contato.atributos' }.freeze

  # Operador antigo → novo, para valor único. Em lista (`labels`), igual vira "contém".
  OPERADOR = { 'equal_to' => 'igual', 'not_equal_to' => 'diferente', 'is_present' => 'preenchido',
               'is_not_present' => 'vazio' }.freeze
  OPERADOR_EM_LISTA = { 'equal_to' => 'contem', 'not_equal_to' => 'nao_contem', 'is_present' => 'preenchido',
                        'is_not_present' => 'vazio' }.freeze
  CAMPOS_EM_LISTA = %w[labels].freeze

  # `message_type` antigo → `mensagem.tipo` novo.
  TIPO_DE_MENSAGEM = { 'incoming' => 'recebida', 'outgoing' => 'enviada' }.freeze

  # Passo de ação do catálogo (automacao-passos.json): a ação e o caminho, como o editor monta.
  NA_CONVERSA = { 'conversation_id' => { '$valor' => 'conversa.id' } }.freeze
  NA_CONVERSA_POR_ID = { 'id' => { '$valor' => 'conversa.id' } }.freeze
  ACAO = {
    atribuir: ['POST conversations/:conversation_id/assignments', NA_CONVERSA],
    etiquetas: ['PATCH conversations/:conversation_id/labels/alterar', NA_CONVERSA],
    status: ['POST conversations/:id/toggle_status', NA_CONVERSA_POR_ID],
    prioridade: ['POST conversations/:id/toggle_priority', NA_CONVERSA_POR_ID]
  }.freeze

  STATUS_DA_ACAO = { 'resolve' => 'resolved', 'open' => 'open', 'pending_conversation' => 'pending',
                     'snooze' => 'snoozed' }.freeze

  # O que ainda não tem equivalente: a chave da falta → a fase em que entra. A frase de cada uma fica no doc.
  FALTA = {
    'gatilho_conversa_atualizada' => 'F6 PR2d (proposta F9)',
    'gatilho_de_card' => 'F6 (#2554)',
    'passo_de_card' => 'F6 PR2a\'',
    'passo_retorno' => 'F6 (P3: POST crm/follow_ups)',
    'passo_webhook' => 'F8 (#2499 PR4)',
    'passo_decidir' => 'F7 (#2500)',
    'operador_texto' => 'F9.0',
    'condicao_mudou' => 'F6 PR2d (valores evento.*)',
    'campo_sem_valor' => 'F9.0',
    'atribuir_ultimo_que_respondeu' => 'F9.0',
    'espera_de_episodio' => 'F9.0',
    'texto_com_variavel' => 'F9 (conversor)',
    'nota_privada' => 'F9.0',
    'acao_sem_equivalente' => 'sem fase (decisão do Rodrigo)'
  }.freeze

  # Ações antigas sem passo hoje e sem fase prevista: a conversão não as leva, e o relatório diz isso.
  SEM_EQUIVALENTE = %w[mute send_email_transcript send_attachment disable_crm_ai_followup enable_crm_ai_followup
                       add_sla].freeze
  DE_CARD = %w[crm_create_card crm_move_card_stage crm_mark_card_won crm_mark_card_lost crm_assign_card_owner].freeze
end
