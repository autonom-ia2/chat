# O `action_params` de cada ação de AutomationRule, lido do método que a executa em
# `ActionService`/`AutomationRules::ActionService` (#932). A descrição diz o que o motor faz de
# verdade, inclusive quando ele não faz nada (id em texto, agente fora da caixa).
#
# A macro executa as mesmas ações (`Macros::ExecutionService < ActionService`) e usa estes ramos.
module AutomationRuleSchema::Acoes
  extend JsonSchemaBlocos

  # O que sai da plataforma: mensagem ao cliente, e-mail, webhook. Não há desfazer.
  SEM_VOLTA = %w[send_message send_email_to_team send_email_transcript send_webhook_event send_attachment].freeze
  # Valor que a condição aceita além do enum: 'all' em status vale todos (FilterHelper#conversation_status_values).
  ESPECIAIS = { 'status' => %w[all] }.freeze

  module_function

  def parametros
    @parametros ||= [conversa, estado, mensagens, crm, decisor].reduce(:merge).freeze
  end

  def conversa
    {
      'add_label' => [lista(etiqueta), 'Põe estas etiquetas na conversa (título exato, como gravado na conta).'],
      'remove_label' => [lista(etiqueta), 'Tira estas etiquetas da conversa.'],
      'assign_team' => [lista({ 'anyOf' => [id_da_conta('Team', 'Time da conta.'), um_de(%w[nil], 'Tira o time.')] }, minimo: 1, descricao: time),
                        'Passa a conversa para o time. O id vai como número: em texto o motor não acha o time e não faz nada.'],
      'assign_agent' => [lista({ 'anyOf' => [id_da_conta('User', 'Agente da conta.'), um_de(%w[nil last_responding_agent], especiais)] },
                               minimo: 1, descricao: 'O agente; o motor usa o primeiro.'),
                         'Atribui a conversa ao agente. Só funciona se ele for da caixa ou administrador; id vai como número.']
    }
  end

  def estado
    {
      'remove_assigned_agent' => [nenhum('Sem parâmetro: mande [].'), 'Tira o agente da conversa.'],
      'remove_assigned_team' => [nenhum('Sem parâmetro: mande [].'), 'Tira o time da conversa.'],
      'mute_conversation' => [nenhum('Sem parâmetro: mande [].'), 'Silencia a conversa.'],
      'snooze_conversation' => [nenhum('Sem parâmetro: mande [].'), 'Adia a conversa.'],
      'resolve_conversation' => [nenhum('Sem parâmetro: mande [].'), 'Resolve a conversa.'],
      'open_conversation' => [nenhum('Sem parâmetro: mande [].'), 'Reabre a conversa.'],
      'pending_conversation' => [nenhum('Sem parâmetro: mande [].'), 'Põe a conversa como pendente.'],
      'change_status' => [um_item(um_de(Conversation.statuses.keys, 'O status.'), 'O status novo.'), 'Troca o status da conversa.'],
      'change_priority' => [um_item(um_de(Conversation.priorities.keys + %w[nil], 'A prioridade; nil tira.'), 'A prioridade nova.'),
                            'Troca a prioridade da conversa.']
    }
  end

  def mensagens
    {
      'send_message' => [um_item(texto('O texto.'), 'A mensagem.'), 'Manda esta mensagem ao cliente na conversa. Sai da plataforma.'],
      'add_private_note' => [um_item(texto('O texto.'), 'A nota.'), 'Escreve uma nota privada na conversa, que o cliente não vê.'],
      'send_email_to_team' => [um_item(email_ao_time, 'Os times e a mensagem.'),
                               'Manda um e-mail aos membros dos times, dentro do limite diário de e-mails da conta. Sai da plataforma.'],
      'send_email_transcript' => [um_item({ 'type' => 'string', 'format' => JsonSchemaFormatos::LISTA_DE_EMAILS,
                                            'description' => 'E-mails separados por vírgula num texto só; o do cliente é {{contact.email}}.' },
                                          'Os destinatários.'),
                                  'Manda a conversa inteira por e-mail, se a conta tiver transcrição por e-mail ligada. Sai da plataforma.'],
      'send_webhook_event' => [um_item({ 'type' => 'string', 'format' => 'uri', 'description' => 'Endereço http(s) completo.' }, 'O endereço.'),
                               'Manda os dados da conversa para este endereço. Sai da plataforma.'],
      'send_attachment' => [lista({ 'type' => %w[integer string], 'description' => 'Arquivo enviado na tela.' }, minimo: 1),
                            'Manda ao cliente o arquivo anexado na tela da automação. O Guia não anexa arquivo. Sai da plataforma.']
    }
  end

  def crm
    {
      'crm_create_card' => [um_item(etapa, 'A etapa.'), 'Cria o card da conversa nesta etapa, se ela ainda não tiver card.'],
      'crm_move_card_stage' => [um_item(etapa, 'A etapa.'), 'Move o card aberto da conversa para esta etapa (card ganho ou perdido fica).'],
      'crm_mark_card_won' => [nenhum('Sem parâmetro: mande [].'), 'Marca o card da conversa como ganho.'],
      'crm_mark_card_lost' => [nenhum('Sem parâmetro: mande [].'), 'Marca o card da conversa como perdido.'],
      'crm_assign_card_owner' => [um_item(id_da_conta('User', 'Agente da conta.'), 'O responsável.'), 'Troca o responsável do card.'],
      'disable_crm_ai_followup' => [nenhum('Sem parâmetro: mande [].'), 'Desliga o retorno automático da IA para o contato, em todos os funis.'],
      'enable_crm_ai_followup' => [nenhum('Sem parâmetro: mande [].'), 'Religa o retorno automático da IA para o contato.']
    }
  end

  # [decisor_id, chave_que_segue]: posição a posição.
  def decisor
    itens = [id_da_conta('Autonomia::Decisor', 'O Decisor da conta.', tipos: %w[integer string]), texto('A resposta dele que deixa seguir.')]
    parametro = { 'type' => 'array', 'items' => itens, 'minItems' => 2, 'maxItems' => 2, 'description' => '[decisor_id, chave_que_segue].' }
    { Autonomia::Decisores::PASSO => [parametro, 'Pergunta ao Decisor; as ações seguintes só rodam se ele der a resposta combinada.'] }
  end

  def etiqueta
    valor_da_conta('Label', 'title', 'Título de etiqueta da conta.')
  end

  def etapa
    id_da_conta('Crm::PipelineStage', 'Etapa de funil do CRM da conta.')
  end

  def time
    'O time; nil tira o time.'
  end

  def especiais
    'nil tira o agente; last_responding_agent é o último agente que respondeu.'
  end

  def email_ao_time
    { 'type' => 'object', 'required' => %w[team_ids message], 'additionalProperties' => false,
      'properties' => { 'team_ids' => lista(id_da_conta('Team', 'Time da conta.'), minimo: 1), 'message' => texto('O texto do e-mail.') } }
  end

  # O valor que uma condição compara, pela coluna que ela lê: enum, id de registro da conta, etiqueta.
  def valor_do_atributo(modelo, coluna, tipo_do_filtro)
    return valor_do_enum(modelo, coluna) if modelo.defined_enums[coluna]
    return etiqueta if tipo_do_filtro == 'labels'
    return { 'type' => %w[boolean string] } if tipo_do_filtro == 'boolean'

    associada = associada(modelo, coluna)
    associada ? id_da_conta(associada.name, "Id de #{associada.model_name.human} da conta.", tipos: %w[integer string]) : livre
  end

  def valor_do_enum(modelo, coluna)
    valores = modelo.defined_enums[coluna].keys
    especiais = ESPECIAIS.fetch(coluna, []) + (modelo.columns_hash[coluna]&.null ? %w[nil] : [])
    um_de(valores + especiais, "Um de: #{valores.join(', ')}.")
  end

  # O modelo que a coluna aponta pelo belongs_to, quando há um só.
  def associada(modelo, coluna)
    associacao = modelo.reflect_on_all_associations(:belongs_to).find { |assoc| assoc.foreign_key.to_s == coluna }
    associacao.klass if associacao && !associacao.polymorphic?
  end

  def livre
    { 'type' => %w[string number boolean] }
  end
end
