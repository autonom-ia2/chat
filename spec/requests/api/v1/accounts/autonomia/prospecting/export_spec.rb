require 'rails_helper'
require 'roo'

# Exportar os leads de uma busca ou de uma lista em CSV e em Excel (#682, frente A), com as colunas do Orth (ACAO-39 e
# PAINEL-40): empresa do cadastro, decisor, sócios, WhatsApp verificado, nota e faixa que a tela mostra.
RSpec.describe 'Autonomia prospecting export', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:base_path) { "/api/v1/accounts/#{account.id}/autonomia/prospecting" }
  let(:header) do
    [
      'ID do Google', 'Nome', 'Nota', 'Prioridade', 'Faixa', 'Nota no Google', 'Avaliações', 'Categoria', 'Endereço', 'Bairro',
      'Site', 'Telefone', 'WhatsApp', 'WhatsApp verificado', 'E-mail', 'Instagram', 'Facebook', 'LinkedIn', 'CNPJ',
      'Razão social', 'Nome fantasia', 'Situação', 'UF', 'Decisor', 'Cargo do decisor', 'Confiança do decisor',
      'LinkedIn do decisor', 'Instagram do decisor', 'Sócios', 'Pesquisado em', 'Maps', 'Latitude', 'Longitude', 'Status', 'Fonte'
    ]
  end
  let(:profile) do
    Autonomia::Prospecting::CompanyProfile.create!(
      cnpj: '12345678000190', legal_name: 'CLINICA SORRISO LTDA', trade_name: 'Clinica Sorriso', registration_status: 'ATIVA',
      registration_state: 'PR', verified_at: Time.zone.parse('2026-09-20 10:00'),
      owners: [{ 'name' => 'ANA SOUZA', 'qualification' => 'SOCIO ADMINISTRADOR' }, { 'name' => 'BRUNO LIMA', 'qualification' => 'SOCIO' }]
    )
  end
  let!(:researched) do
    Autonomia::Prospecting::Lead.create!(
      account: account, provider: 'google_places', provider_place_id: 'places/sorriso', name: 'Clinica Sorriso',
      phone: '(41) 99999-0001', website: 'https://sorriso.example.com', address: 'Rua XV, 10', city: 'Curitiba', state: 'PR',
      neighborhood: 'Centro', category: 'Dentista', rating: 4.7, reviews_count: 88, latitude: -25.4284, longitude: -49.2733,
      google_maps_uri: 'https://maps.google.com/?cid=1', enriched_email: 'contato@sorriso.example.com',
      enriched_instagram: 'https://instagram.com/sorriso', enriched_cnpj: '99.999.999/0001-99',
      score: 71.5, priority_score: 40, priority_position: 2,
      company_research_status: 'confirmed', decision_research_status: 'confirmed', company_profile: profile,
      research_completed_at: Time.zone.parse('2026-09-25 12:30'),
      decision_name: 'ANA SOUZA', decision_role: 'SOCIO ADMINISTRADOR', decision_confidence: 0.92,
      decision_linkedin: 'https://linkedin.com/in/ana',
      metadata: {
        'whatsapp_verification' => { 'status' => 'verified', 'phone' => '+5541999990001' },
        'research' => { 'owners' => profile.owners, 'decision_source' => 'qsa' }
      }
    )
  end
  let!(:site_only) do
    Autonomia::Prospecting::Lead.create!(
      account: account, provider: 'google_places', provider_place_id: 'places/site', name: '=HYPERLINK("http://mal")',
      phone: '+55 41 3333-0002', enriched_cnpj: '11.222.333/0001-81', score: 30, priority_score: 90, priority_position: 1,
      metadata: { 'whatsapp_verification' => { 'status' => 'not_whatsapp' } }
    )
  end
  let(:search) do
    Autonomia::Prospecting::Search.create!(
      account: account, user: admin, query: 'dentista', location: 'Curitiba', provider: 'google_places', status: 'completed',
      metadata: { 'lead_ids' => [researched.id, site_only.id] }
    )
  end
  let(:other_account) { create(:account) }
  let(:other_lead) do
    Autonomia::Prospecting::Lead.create!(account: other_account, provider: 'mock', provider_place_id: 'places/outra', name: 'Lead de outra conta')
  end

  before do
    Autonomia::Prospecting::Config.enable_for!(account)
    Autonomia::Prospecting::Config.enable_for!(other_account)
  end

  def csv_rows
    expect(response.body.bytes.first(3)).to eq([0xEF, 0xBB, 0xBF])
    CSV.parse(response.body.force_encoding('UTF-8').delete_prefix([0xFEFF].pack('U')), col_sep: ';')
  end

  def xlsx_rows
    Tempfile.create(['export', '.xlsx'], binmode: true) do |file|
      file.write(response.body)
      file.flush
      sheet = Roo::Excelx.new(file.path).sheet(0)
      (1..sheet.last_row).map { |index| sheet.row(index) }
    end
  end

  def column(rows, name, lead_name)
    rows.find { |row| row[header.index('Nome')] == lead_name }[header.index(name)]
  end

  describe 'GET searches/:id/export' do
    it 'CSV com BOM, ponto e vírgula e as colunas do Orth, na ordem da prioridade' do
      get "#{base_path}/searches/#{search.id}/export", params: { format: 'csv' }, headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/csv')
      expect(response.headers['Content-Disposition']).to include('attachment', '.csv')
      rows = csv_rows
      expect(rows.first).to eq(header)
      expect(rows.drop(1).map { |row| row[header.index('Prioridade')] }).to eq(%w[90 40])
      expect(rows.size).to eq(3)
    end

    it 'CNPJ do cadastro vence o do site; empresa, decisor, sócios e WhatsApp verificado saem como a tela mostra' do
      get "#{base_path}/searches/#{search.id}/export", params: { format: 'csv' }, headers: auth_headers(admin)

      row = csv_rows.find { |line| line[1] == 'Clinica Sorriso' }
      expect(header.zip(row).to_h).to include(
        'ID do Google' => 'places/sorriso', 'Nota' => '71,5', 'Prioridade' => '40', 'Faixa' => 'Lead morno',
        'Nota no Google' => '4,7', 'Avaliações' => '88', 'Categoria' => 'Dentista', 'Endereço' => 'Rua XV, 10 - Curitiba PR',
        'Bairro' => 'Centro', 'Site' => 'https://sorriso.example.com', 'Telefone' => '(41) 99999-0001',
        'WhatsApp' => 'https://wa.me/5541999990001', 'WhatsApp verificado' => 'Sim', 'E-mail' => 'contato@sorriso.example.com',
        'Instagram' => 'https://instagram.com/sorriso', 'CNPJ' => '12.345.678/0001-90', 'Razão social' => 'CLINICA SORRISO LTDA',
        'Nome fantasia' => 'Clinica Sorriso', 'Situação' => 'ATIVA', 'UF' => 'PR', 'Decisor' => 'ANA SOUZA',
        'Cargo do decisor' => 'SOCIO ADMINISTRADOR', 'Confiança do decisor' => '92%', 'LinkedIn do decisor' => 'https://linkedin.com/in/ana',
        'Sócios' => 'ANA SOUZA (SOCIO ADMINISTRADOR) | BRUNO LIMA (SOCIO)', 'Pesquisado em' => '25/09/2026 09:30',
        'Maps' => 'https://maps.google.com/?cid=1', 'Latitude' => '-25,4284', 'Longitude' => '-49,2733', 'Status' => 'Novo',
        'Fonte' => 'Google places'
      )
    end

    it 'sem cadastro, usa o CNPJ do site; WhatsApp que não é WhatsApp sai como Não; fórmula neutralizada' do
      get "#{base_path}/searches/#{search.id}/export", params: { format: 'csv' }, headers: auth_headers(admin)

      rows = csv_rows
      row = header.zip(rows[1]).to_h
      expect(row).to include('Nome' => "'=HYPERLINK(\"http://mal\")", 'CNPJ' => '11.222.333/0001-81', 'WhatsApp verificado' => 'Não',
                             'WhatsApp' => nil, 'Telefone' => "'+55 41 3333-0002", 'Razão social' => nil, 'Decisor' => nil,
                             'Sócios' => nil, 'Faixa' => 'Lead muito quente')
    end

    it 'Excel abre e traz as mesmas células do CSV, com o texto limpo (sem o apóstrofo que o CSV precisa)' do
      get "#{base_path}/searches/#{search.id}/export", params: { format: 'csv' }, headers: auth_headers(admin)
      csv = csv_rows
      get "#{base_path}/searches/#{search.id}/export", params: { format: 'xlsx' }, headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
      expect(response.headers['Content-Disposition']).to include('attachment', '.xlsx')
      # Número vai como número no Excel; no CSV, com vírgula decimal. O resto é a mesma célula: o Excel guarda o texto como
      # veio (neutralizado pelo estilo quotePrefix) e o CSV põe o apóstrofo na frente do que começa como fórmula.
      xlsx = xlsx_rows
      as_csv = xlsx.map do |row|
        row.map { |value| value.is_a?(Float) ? value.to_s.tr('.', ',') : Autonomia::Prospecting::Export::Cell.safe(value)&.to_s }
      end
      expect(as_csv).to eq(csv)
      expect(column(xlsx, 'Nota', 'Clinica Sorriso')).to eq(71.5)
      expect(column(xlsx, 'Telefone', '=HYPERLINK("http://mal")')).to eq('+55 41 3333-0002')
    end

    it 'com lead_ids, exporta só esses leads, na ordem pedida (a seleção ou o filtro da tela)' do
      third = Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: 'places/3', name: 'Terceiro')
      search.update!(metadata: { 'lead_ids' => [researched.id, site_only.id, third.id] })

      get "#{base_path}/searches/#{search.id}/export", params: { format: 'csv', lead_ids: [third.id, researched.id] },
                                                       headers: auth_headers(admin)

      expect(csv_rows.drop(1).pluck(1)).to eq(['Terceiro', 'Clinica Sorriso'])
    end

    it 'lead de outra conta, ou fora da busca, nunca entra, mesmo pedido por id' do
      loose = Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: 'places/solto', name: 'Fora da busca')

      get "#{base_path}/searches/#{search.id}/export", params: { format: 'csv', lead_ids: [other_lead.id, loose.id, site_only.id] },
                                                       headers: auth_headers(admin)

      expect(csv_rows.drop(1).pluck(1)).to eq(["'=HYPERLINK(\"http://mal\")"])
    end

    it 'busca de outra conta responde 404' do
      other_search = Autonomia::Prospecting::Search.create!(
        account: other_account, user: create(:user, account: other_account), query: 'x', location: 'y', provider: 'mock',
        status: 'completed', metadata: { 'lead_ids' => [other_lead.id] }
      )

      get "#{base_path}/searches/#{other_search.id}/export", params: { format: 'csv' }, headers: auth_headers(admin)

      expect(response).to have_http_status(:not_found)
    end

    it 'formato fora de csv e xlsx responde 422' do
      get "#{base_path}/searches/#{search.id}/export", params: { format: 'pdf' }, headers: auth_headers(admin)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.prospecting.export.errors.invalid_format'))
    end

    it 'lead_ids que não é lista de números responde 422' do
      get "#{base_path}/searches/#{search.id}/export", params: { format: 'csv', lead_ids: ['1a'] }, headers: auth_headers(admin)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.prospecting.export.errors.invalid_lead_ids'))
    end
  end

  describe 'nota e faixa: a que a tela mostra, legada ou do Orth conforme a conta' do
    def scoring(values)
      { 'score' => values[:score], 'score_breakdown' => {}, 'priority_score' => values[:priority], 'priority_position' => 1 }
    end

    def export_priority_and_band
      get "#{base_path}/searches/#{search.id}/export", params: { format: 'csv' }, headers: auth_headers(admin)
      row = header.zip(csv_rows.find { |line| line[1] == 'Clinica Sorriso' }).to_h
      row.values_at('Nota', 'Prioridade', 'Faixa')
    end

    def screen_priority
      get "#{base_path}/searches/#{search.id}", headers: auth_headers(admin)
      response.parsed_body.dig('payload', 'leads').find { |lead| lead['name'] == 'Clinica Sorriso' }['priority_score'].to_f.round.to_s
    end

    it 'conta no motor legado: a nota da busca, nunca a do Orth guardada em sombra' do
      search.update!(metadata: search.metadata.merge(
        'lead_scoring' => { researched.id.to_s => scoring(score: 64, priority: 80).merge('orth' => { 'score' => 10, 'priority_score' => 12 }) }
      ))

      expect(export_priority_and_band).to eq(['64', '80', 'Lead muito quente'])
      expect(screen_priority).to eq('80')
    end

    it 'conta virada para o Orth: a nota do Orth, nunca a legada guardada para comparar' do
      search.update!(metadata: search.metadata.merge(
        'lead_scoring' => { researched.id.to_s => scoring(score: 22, priority: 55).merge('legacy' => { 'score' => 90, 'priority_score' => 95 }) }
      ))

      expect(export_priority_and_band).to eq(['22', '55', 'Oportunidade alta'])
      expect(screen_priority).to eq('55')
    end

    it 'busca feita de verdade na conta virada: prioridade e faixa do arquivo iguais às da tela, e são as do Orth' do
      Autonomia::Prospecting::Setting.for_account(account).update!(provider: 'mock', cache_ttl_seconds: 0, score_engine: 'orth')
      post "#{base_path}/searches", params: { search: { query: 'dentista', location: 'Curitiba, PR', requested_limit: 5 } },
                                    headers: auth_headers(admin), as: :json
      created = Autonomia::Prospecting::Search.find(response.parsed_body.dig('payload', 'search', 'id'))
      screen = response.parsed_body.dig('payload', 'leads').to_h { |lead| [lead['provider_place_id'], lead['priority_score'].to_f.round] }

      get "#{base_path}/searches/#{created.id}/export", params: { format: 'csv' }, headers: auth_headers(admin)

      exported = csv_rows.drop(1).to_h { |row| [row[0], row[3].to_i] }
      expect(exported).to eq(screen)
      created.metadata['lead_scoring'].each_value do |entry|
        expect(entry['priority_score']).to eq(entry.dig('orth', 'priority_score'))
      end
      csv_rows.drop(1).each do |row|
        expect(row[4]).to eq(Autonomia::Prospecting::Scoring::Band.label(Autonomia::Prospecting::Scoring::Band.code(row[3].to_i)))
      end
    end
  end

  describe 'GET lists/:id/export' do
    let(:list) { Autonomia::Prospecting::List.create!(account: account, user: admin, name: 'Dentistas') }

    before do
      [researched, site_only].each do |lead|
        Autonomia::Prospecting::ListLead.create!(account: account, list: list, lead: lead)
      end
    end

    it 'exporta os leads da lista em CSV e em Excel' do
      get "#{base_path}/lists/#{list.id}/export", params: { format: 'csv' }, headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      rows = csv_rows
      expect(rows.first).to eq(header)
      expect(rows.drop(1).pluck(1)).to contain_exactly('Clinica Sorriso', "'=HYPERLINK(\"http://mal\")")
      expect(column(rows, 'Faixa', 'Clinica Sorriso')).to eq('Lead morno')

      get "#{base_path}/lists/#{list.id}/export", params: { format: 'xlsx' }, headers: auth_headers(admin)

      expect(xlsx_rows.drop(1).map { |row| row[1] }).to contain_exactly('Clinica Sorriso', '=HYPERLINK("http://mal")')
    end

    it 'lista de outra conta responde 404' do
      other_list = Autonomia::Prospecting::List.create!(account: other_account, user: create(:user, account: other_account), name: 'Outra')

      get "#{base_path}/lists/#{other_list.id}/export", params: { format: 'csv' }, headers: auth_headers(admin)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'permissão' do
    def agent_with(permissions)
      agent = create(:user, account: account, role: :agent)
      role = create(:custom_role, account: account, permissions: permissions)
      agent.account_users.find_by(account: account).update!(custom_role: role)
      agent
    end

    it 'sem a permissão da prospecção responde 401 e não entrega arquivo' do
      get "#{base_path}/searches/#{search.id}/export", params: { format: 'csv' }, headers: auth_headers(agent_with(['conversation_manage']))

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).not_to include('Clinica Sorriso')
    end

    it 'com prospecting_view exporta' do
      get "#{base_path}/searches/#{search.id}/export", params: { format: 'csv' }, headers: auth_headers(agent_with(['prospecting_view']))

      expect(response).to have_http_status(:ok)
    end

    it 'com a prospecção desligada na conta responde 404' do
      Autonomia::Prospecting::Config.disable_for!(account)

      get "#{base_path}/searches/#{search.id}/export", params: { format: 'csv' }, headers: auth_headers(admin)

      expect(response).to have_http_status(:not_found)
    end
  end
end
