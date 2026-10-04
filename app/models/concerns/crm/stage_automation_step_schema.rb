# A regra interna do `action_config` de um passo de automação de etapa, como esquema JSON (#932).
# Antes um validador escrito à mão só olhava o obrigatório: chave que o executor
# (`Crm::StageAutomations::StepExecutor`) não lê gravava em silêncio.
#
# O `action_config` depende do `action_type` do passo. Com o passo, o esquema é o do tipo dele; sem
# passo (o que o Guia lê), é um dos tipos, cada um com `x-quando` dizendo qual.
module Crm::StageAutomationStepSchema
  extend JsonSchemaBlocos

  module_function

  def action_config(passo = nil)
    tipo = passo&.action_type
    return por_tipo.fetch(tipo) if por_tipo.key?(tipo)

    { 'anyOf' => por_tipo.map { |nome, esquema| esquema.merge('x-quando' => { 'action_type' => nome }) },
      'description' => 'O que o passo faz depende do action_type: cada opção diz para qual tipo vale.' }
  end

  def por_tipo
    {
      'create_follow_up' => objeto(['title'], criar_retorno, 'Cria um retorno (tarefa com data) no card, vencendo depois do atraso do passo.',
                                   [enviar_mensagem]),
      'assign_owner' => objeto([], dono, 'Troca o responsável do card.', [{ 'anyOf' => [com_dono, usar_o_dono] }]),
      'move_stage' => objeto(['target_stage_id'], { 'target_stage_id' => etapa }, 'Move o card para a etapa (no máximo 3 passos encadeados).'),
      Autonomia::Decisores::PASSO => objeto(%w[decisor_id chave_que_segue], decisor,
                                            'Pergunta ao Decisor; os passos seguintes só rodam se ele der a resposta combinada.')
    }
  end

  def objeto(obrigatorias, propriedades, descricao, todos = [])
    { 'type' => 'object', 'required' => obrigatorias, 'additionalProperties' => false, 'properties' => propriedades,
      'description' => descricao, 'allOf' => todos.presence }.compact
  end

  def criar_retorno
    {
      'title' => texto('O título do retorno.'),
      'description' => { 'type' => 'string', 'description' => 'O que fazer.' },
      'follow_up_type' => um_de(Crm::FollowUp.follow_up_types.keys, 'O tipo; sem ele, task.'),
      'automation_mode' => um_de(Crm::FollowUp.automation_modes.keys,
                                 'reminder_only só lembra; snooze_conversation adia a conversa; auto_send_message manda a mensagem sozinho.'),
      'timezone' => { 'type' => %w[string null], 'description' => 'Fuso IANA, ex.: America/Sao_Paulo.' },
      'metadata' => { 'type' => 'object', 'description' => 'Com auto_send_message: message_body ou o modelo de WhatsApp a mandar.' }
    }
  end

  # Retorno que manda a mensagem sozinho sai da plataforma: não tem volta.
  def enviar_mensagem
    { 'if' => { 'properties' => { 'automation_mode' => { 'const' => 'auto_send_message' } }, 'required' => ['automation_mode'] },
      'x-sem-volta' => true, 'description' => 'Manda mensagem ao cliente quando o retorno vence.' }
  end

  def dono
    { 'owner_id' => id_da_conta('User', 'O agente da conta.', tipos: %w[integer string]),
      'use_card_owner' => { 'type' => 'boolean', 'description' => 'true mantém o responsável que o card já tem.' } }
  end

  def com_dono
    { 'required' => ['owner_id'], 'properties' => { 'owner_id' => { 'minLength' => 1 } } }
  end

  def usar_o_dono
    { 'required' => ['use_card_owner'], 'properties' => { 'use_card_owner' => { 'const' => true } } }
  end

  def etapa
    id_da_conta('Crm::PipelineStage', 'A etapa de destino, do CRM da conta.', tipos: %w[integer string]).merge('minLength' => 1)
  end

  def decisor
    { 'decisor_id' => id_da_conta('Autonomia::Decisor', 'O Decisor da conta.', tipos: %w[integer string]),
      'chave_que_segue' => texto('A resposta do Decisor que deixa os passos seguintes rodarem.') }
  end
end
