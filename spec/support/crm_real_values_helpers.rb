# Follow-up de IA com dados reais (#1336): cenário do CrmHybridHelpers com um modelo de cobrança cujo perfil liga
# {{1}} ao primeiro nome, {{2}} ao valor e {{3}} ao prazo do card; {{4}} fica com a IA. A flag nasce ligada aqui.
module CrmRealValuesHelpers
  FLAG = 'followup_template_real_values'.freeze
  COBRANCA = {
    'name' => 'cobranca_valor', 'status' => 'APPROVED', 'language' => 'pt_BR', 'category' => 'UTILITY',
    'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, o valor de {{2}} vence em {{3}}. {{4}}' }]
  }.freeze
  LIVRE = {
    'name' => 'retomada_livre', 'status' => 'APPROVED', 'language' => 'pt_BR', 'category' => 'UTILITY',
    'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, {{2}}' }]
  }.freeze
  FILLED_BODY = 'Oi Lead, o valor de R$ 1.250,00 vence em 20/10/2026. {{4}}'.freeze
  AI_PARAMS = { '1' => 'Cliente', '2' => 'R$ 99,90', '3' => 'amanhã', '4' => 'Posso ajudar?' }.freeze
  REAL_PARAMS = { '1' => 'Lead', '2' => 'R$ 1.250,00', '3' => '20/10/2026', '4' => 'Posso ajudar?' }.freeze

  def build_real_values_scenario(templates:, hybrid:)
    scenario = build_crm_hybrid_scenario(templates: templates, hybrid: hybrid)
    scenario[:card].update!(value_cents: 125_000, expected_close_at: Time.utc(2026, 10, 20, 15))
    WhatsappTemplateProfile.create!(
      account: scenario[:account], inbox: scenario[:inbox], waba_id: scenario[:inbox].channel.waba_id,
      name: COBRANCA['name'], language: COBRANCA['language'],
      fields: { '1' => 'cliente.primeiro_nome', '2' => 'negocio.valor', '3' => 'negocio.prazo' }
    )
    scenario[:account].enable_features!(FLAG)
    scenario
  end

  def pick(index, name)
    { 'index' => index, 'kind' => 'native', 'name' => name, 'id' => nil, 'language' => 'pt_BR' }
  end

  # A IA escolhe a cobrança e, como hoje, escreve valores para todas as posições (inclusive as já preenchidas).
  def pick_cobranca_inventing_values
    crm_hybrid_ai_answer('chosen_template' => pick(0, COBRANCA['name']), 'message_body' => '',
                         'template_variables' => AI_PARAMS.map { |position, value| { 'position' => position, 'value' => value } })
  end
end
