# Dados do protótipo da fase Gatilhos (#2499), só no banco da demo. Rodar com `bin/demo seed 2499-gatilhos <este arquivo>`.
# Funil de seguro com etapas e cards, campos de data no card e no contato (vencimento da apólice, aniversário) e uma
# automação de conversa para a lista. Os dados são fictícios.
account = Account.find(1)

%w[automacao_fundacao automacao_motor automacao_editor automacao_mensagens automacao_gatilhos crm].each do |flag|
  account.enable_features!(flag) if account.respond_to?(:enable_features!)
end
account.save!

funil = Crm::Pipeline.find_or_create_by!(account: account, name: 'Vendas de seguro auto')
etapas = ['Novo pedido', 'Orçamento enviado', 'Negociação', 'Renovação'].each_with_index.map do |nome, posicao|
  Crm::PipelineStage.find_or_create_by!(account: account, pipeline: funil, name: nome) { |etapa| etapa.position = posicao }
end

{ 'card_attribute' => %w[vencimento_apolice Vencimento\ da\ apólice], 'contact_attribute' => %w[aniversario Aniversário] }
  .each do |modelo, (chave, nome)|
  CustomAttributeDefinition.find_or_create_by!(account: account, attribute_model: modelo, attribute_key: chave) do |definicao|
    definicao.attribute_display_name = nome
    definicao.attribute_display_type = 'date'
  end
end

contatos = [['Marina Duarte', '+5511990000001'], ['Paulo Lemos', '+5511990000002'], ['Ana Ribeiro', '+5511990000003']]
contatos.each_with_index do |(nome, telefone), i|
  contato = Contact.find_or_create_by!(account: account, phone_number: telefone) { |c| c.name = nome }
  contato.update!(custom_attributes: contato.custom_attributes.merge('aniversario' => (Date.current + (i * 10)).iso8601))
  Crm::Card.find_or_create_by!(account: account, pipeline: funil, title: "Seguro auto · #{nome}") do |card|
    card.stage = etapas[i % 2 == 0 ? 1 : 0]
    card.contact = contato
    card.value_cents = (1800 + (i * 350)) * 100
    card.entered_stage_at = (i + 2).days.ago
    card.custom_attributes = { 'vencimento_apolice' => (Date.current + 30 + i).iso8601 }
  end
end

puts "funil=#{funil.id} etapas=#{etapas.map(&:id).join(',')} cards=#{Crm::Card.where(pipeline: funil).count}"
