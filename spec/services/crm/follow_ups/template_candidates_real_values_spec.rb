require 'rails_helper'

# Follow-up de IA com dados reais (#1336): com o card e a flag `followup_template_real_values`, a variável que o perfil
# do modelo liga a uma chave do catálogo sai do card, já escrita no body; a IA só preenche o que sobra.
RSpec.describe Crm::FollowUps::TemplateCandidates do
  include CrmHybridHelpers

  def template(name, body)
    { 'name' => name, 'status' => 'APPROVED', 'language' => 'pt_BR', 'category' => 'UTILITY',
      'components' => [{ 'type' => 'BODY', 'text' => body }] }
  end

  let(:cobranca) { template('cobranca_valor', 'Oi {{1}}, o valor de {{2}} vence em {{3}}. {{4}}') }
  let(:livre) { template('retomada_livre', 'Oi {{1}}, {{2}}') }
  let(:scenario) { build_crm_hybrid_scenario(templates: [cobranca, livre], hybrid: false) }
  let(:card) { scenario[:card] }
  let(:owner) { create(:user, account: scenario[:account], name: 'Juliana Melo').tap { |user| user.update!(display_name: nil) } }

  before do
    card.update!(value_cents: 125_000, expected_close_at: Time.utc(2026, 10, 20, 15), owner: owner)
    link(cobranca, '1' => 'cliente.primeiro_nome', '2' => 'negocio.valor', '3' => 'negocio.prazo')
    scenario[:account].enable_features!('followup_template_real_values')
  end

  def link(meta_template, fields)
    WhatsappTemplateProfile.create!(account: scenario[:account], inbox: scenario[:inbox], waba_id: scenario[:inbox].channel.waba_id,
                                    name: meta_template['name'], language: meta_template['language'], fields: fields)
  end

  def candidates(with_card: card)
    described_class.new(conversation: scenario[:conversation], card: with_card).perform
  end

  def by_name(list, name)
    list.find { |candidate| candidate[:name] == name }
  end

  it 'writes the real card values into the body and leaves only the unlinked positions to the AI' do
    filled = by_name(candidates, 'cobranca_valor')

    expect(filled[:body]).to eq('Oi Lead, o valor de R$ 1.250,00 vence em 20/10/2026. {{4}}')
    expect(filled[:variables]).to eq(['4'])
    expect(filled[:filled]).to eq('1' => 'Lead', '2' => 'R$ 1.250,00', '3' => '20/10/2026')
  end

  it 'leaves a template without linked fields exactly as today' do
    expect(by_name(candidates, 'retomada_livre')).to eq(by_name(candidates(with_card: nil), 'retomada_livre'))
    expect(by_name(candidates, 'retomada_livre')).not_to have_key(:filled)
  end

  it 'drops the template when a linked field has no real value (never "R$ 0,00")' do
    card.update!(value_cents: 0)

    expect(candidates.pluck(:name)).to eq(['retomada_livre'])
  end

  it 'drops the template when the deadline or the owner is missing' do
    link(livre, '2' => 'negocio.responsavel')
    card.update!(expected_close_at: nil, owner: nil)

    expect(candidates).to be_empty
  end

  it 'drops the template when the link points to a field the card cannot fill' do
    link(livre, '2' => 'horario.data_hora')

    expect(candidates.pluck(:name)).to eq(['cobranca_valor'])
  end

  it 'keeps a position linked to a screen label (not a catalog key) with the AI, as today' do
    link(livre, '2' => 'desconto')

    expect(by_name(candidates, 'retomada_livre')).to include(body: 'Oi {{1}}, {{2}}', variables: %w[1 2])
  end

  it 'ignores the profile of another WABA' do
    WhatsappTemplateProfile.find_by!(name: 'cobranca_valor').update!(waba_id: 'outra-waba')

    expect(by_name(candidates, 'cobranca_valor')).to include(body: cobranca['components'].first['text'], variables: %w[1 2 3 4])
  end

  def link_sibling(fields)
    sibling = create(:channel_whatsapp, account: scenario[:account], provider: 'whatsapp_cloud', sync_templates: false,
                                        validate_provider_config: false).inbox
    WhatsappTemplateProfile.create!(account: scenario[:account], inbox: sibling, waba_id: scenario[:inbox].channel.waba_id,
                                    name: 'retomada_livre', language: 'pt_BR', fields: fields)
  end

  it "prefers the inbox's own profile over older and newer ones of sibling inboxes in the same WABA" do
    link_sibling('2' => 'negocio.titulo')
    link(livre, '2' => 'negocio.valor')
    link_sibling('2' => 'negocio.funil')

    expect(by_name(candidates, 'retomada_livre')[:filled]).to eq('2' => 'R$ 1.250,00')
  end

  it 'writes a value that looks like a placeholder or has backslashes literally, in one pass' do
    card.update!(title: 'Plano {{1}} \\0 \\& fim')
    link(livre, '2' => 'negocio.titulo')

    expect(by_name(candidates, 'retomada_livre')).to include(body: 'Oi {{1}}, Plano {{1}} \\0 \\& fim', variables: ['1'])
  end

  it 'changes nothing with the flag off' do
    scenario[:account].disable_features!('followup_template_real_values')

    expect(candidates).to eq(candidates(with_card: nil))
  end
end
