require 'rails_helper'

# #2895 — a parte da ficha de Relacionamentos que depende do Enterprise: a ficha da empresa (a empresa, as pessoas, as
# conversas e os cards dela) e o que a função personalizada muda na ficha da pessoa (ver contatos, ler conversas, ver o
# CRM e ver o valor de venda).
RSpec.describe 'Ficha de Relacionamentos: empresa e funções', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/relacionamentos" }
  let(:agora) { Time.zone.parse('2026-11-11 12:00:00') }
  # Sem o "pedir e-mail" da caixa do site: com ele, cada mensagem que chega ganha uma resposta automática da caixa.
  let(:caixa) { create(:inbox, account: account, enable_email_collect: false) }
  let(:outra_caixa) { create(:inbox, account: account) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let!(:padaria) do
    create(:company, account: account, name: 'Padaria Bom Dia', domain: 'padaria-bom-dia.exemplo.com.br', created_at: agora - 30.days,
                     last_activity_at: agora - 2.days, additional_attributes: { cnpj: '12.345.678/0001-00', city: 'Campinas' })
  end
  let!(:ana) { pessoa_da(padaria, name: 'Ana Albuquerino', contact_type: :customer, created_at: agora - 10.days) }
  let(:partes_da_empresa) { ['', '/pessoas', '/conversas', '/cards'] }
  let(:leituras_da_empresa) { partes_da_empresa.map { |parte| "empresas/#{padaria.id}#{parte}" } }
  let(:leituras_da_pessoa) { ['', '/conversas', '/notas', '/arquivos', '/origem'].map { |parte| "pessoas/#{ana.id}#{parte}" } }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before do
    account.enable_features!('relacionamentos_novo', 'companies')
    travel_to(agora)
    create(:inbox_member, user: agente, inbox: caixa)
  end

  def ler(caminho, quem: agente, **params)
    get "#{base}/#{caminho}", params: params, headers: quem.create_new_auth_token
  end

  def pessoa_com(permissions, caixas: [caixa])
    user = create(:user, account: account, role: :agent)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    caixas.each { |inbox| create(:inbox_member, user: user, inbox: inbox) }
    user
  end

  def pessoa_da(empresa, **dados)
    create(:contact, account: account, company: empresa, contact_type: :lead, **dados)
  end

  def conversa_de(pessoa, caixa_dela: caixa, falou: agora, **dados)
    create(:conversation, account: account, inbox: caixa_dela, contact: pessoa, **dados).tap { |conversa| conversa.update!(last_activity_at: falou) }
  end

  def mensagem(conversa, texto)
    create(:message, account: account, inbox: conversa.inbox, conversation: conversa, content: texto, message_type: :incoming)
  end

  def card_de(pessoa, **dados)
    account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, contact: pessoa, title: 'Pedido de orçamento', inbox: caixa, **dados)
  end

  def consultas_feitas(&)
    feitas = 0
    contar = ->(*, dados) { feitas += 1 unless dados[:cached] || %w[SCHEMA TRANSACTION].include?(dados[:name]) }
    ActiveSupport::Notifications.subscribed(contar, 'sql.active_record', &)
    feitas
  end

  describe 'ficha da empresa, em todas as leituras' do
    it 'responde 401 sem login' do
      leituras_da_empresa.each do |caminho|
        get "#{base}/#{caminho}"

        expect(response).to have_http_status(:unauthorized), caminho
      end
    end

    it 'responde 404 com a chave da conta desligada' do
      account.disable_features!('relacionamentos_novo')

      leituras_da_empresa.each do |caminho|
        ler(caminho)

        expect(response).to have_http_status(:not_found), caminho
      end
    end

    it 'responde 403 sem Empresas ligado na conta, como a empresa de hoje' do
      account.disable_features!('companies')

      leituras_da_empresa.each do |caminho|
        ler(caminho)

        expect(response).to have_http_status(:forbidden), caminho
      end
    end

    it 'atende o agente comum' do
      leituras_da_empresa.each do |caminho|
        ler(caminho)

        expect(response).to have_http_status(:ok), caminho
      end
    end

    it 'responde 404 para empresa de outra conta e para empresa que não existe' do
      de_fora = create(:company, account: create(:account), name: 'Oficina de outra conta')

      [de_fora.id, 0].each do |id|
        partes_da_empresa.each do |parte|
          ler("empresas/#{id}#{parte}")

          expect(response).to have_http_status(:not_found), "#{id}#{parte}"
        end
      end
    end

    it 'responde 422 com a frase para parâmetro que a ficha não conhece' do
      leituras_da_empresa.each do |caminho|
        ler(caminho, busca: 'padaria')

        expect(response).to have_http_status(:unprocessable_entity), caminho
        expect(response.parsed_body).to eq('error' => 'parâmetro desconhecido: busca')
      end
    end

    it 'não mistura o que é de outra empresa da conta' do
      bruno = pessoa_da(create(:company, account: account, name: 'Oficina Carvalhedo', domain: nil), name: 'Bruno Brandolim')
      mensagem(conversa_de(bruno), 'Consegue me ligar amanhã?')
      card_de(bruno)

      ler("empresas/#{padaria.id}/pessoas")
      expect(response.parsed_body.pluck('name')).to eq(['Ana Albuquerino'])

      %w[conversas cards].each do |parte|
        ler("empresas/#{padaria.id}/#{parte}")

        expect(response.parsed_body).to eq([]), parte
      end
    end
  end

  describe 'GET empresas/:id' do
    it 'devolve a empresa com os campos da lista' do
      pessoa_da(padaria)

      ler("empresas/#{padaria.id}")

      expect(response.parsed_body).to eq(
        'id' => padaria.id, 'name' => 'Padaria Bom Dia', 'domain' => 'padaria-bom-dia.exemplo.com.br',
        'cnpj' => '12.345.678/0001-00', 'created_at' => (agora - 30.days).to_i, 'contacts_count' => 2,
        'customers_count' => 1, 'last_activity_at' => (agora - 2.days).to_i
      )
    end
  end

  describe 'GET empresas/:id/pessoas' do
    it 'devolve as pessoas da empresa no formato da lista, por nome' do
      ana.update_labels(%w[feira])
      pessoa_da(padaria, name: 'Álvaro Abreuzal')

      ler("empresas/#{padaria.id}/pessoas")

      expect(response.parsed_body.pluck('name')).to eq(['Álvaro Abreuzal', 'Ana Albuquerino'])
      expect(response.parsed_body.last).to eq(
        'id' => ana.id, 'name' => 'Ana Albuquerino', 'email' => nil, 'phone_number' => nil, 'thumbnail' => '', 'blocked' => false,
        'contact_type' => 'customer', 'customer_since' => nil, 'last_activity_at' => nil, 'created_at' => (agora - 10.days).to_i,
        'additional_attributes' => { 'company_name' => 'Padaria Bom Dia' }, 'custom_attributes' => {}, 'labels' => %w[feira],
        'company_id' => padaria.id, 'opted_out_at' => nil, 'opt_out_source' => nil
      )
    end

    it 'devolve só até o teto' do
      stub_const('Api::V1::Accounts::Relacionamentos::EmpresasController::PESSOAS_NA_FICHA', 1)
      pessoa_da(padaria, name: 'Bruno Brandolim')

      ler("empresas/#{padaria.id}/pessoas")

      expect(response.parsed_body.pluck('name')).to eq(['Ana Albuquerino'])
    end

    it 'não faz uma consulta a mais por pessoa (etiquetas e foto)' do
      criar = ->(nome) { create(:contact, :with_avatar, account: account, company: padaria, name: nome).update_labels(%w[feira]) }
      criar.call('Pessoa 0')
      cabecalhos = agente.create_new_auth_token
      pedir = -> { get "#{base}/empresas/#{padaria.id}/pessoas", headers: cabecalhos }
      pedir.call
      com_duas = consultas_feitas(&pedir)
      3.times { |n| criar.call("Outra #{n}") }

      expect(consultas_feitas(&pedir)).to eq(com_duas)
      expect(response.parsed_body.size).to eq(5)
    end
  end

  describe 'GET empresas/:id/conversas' do
    it 'devolve as conversas das pessoas da empresa, com o nome de quem é, da mais recente para trás' do
      bruno = pessoa_da(padaria, name: 'Bruno Brandolim')
      da_ana = conversa_de(ana)
      mensagem(da_ana, 'Posso trocar a data que a gente combinou?')
      da_ana.update!(status: :pending, last_activity_at: agora - 5.days)
      do_bruno = conversa_de(bruno, falou: agora - 1.day)

      ler("empresas/#{padaria.id}/conversas")

      expect(response.parsed_body).to eq(
        [{ 'id' => do_bruno.display_id, 'canal' => 'site', 'trecho' => nil, 'quando' => (agora - 1.day).to_i, 'situacao' => 'aberta',
           'pessoa' => 'Bruno Brandolim' },
         { 'id' => da_ana.display_id, 'canal' => 'site', 'trecho' => 'Posso trocar a data que a gente combinou?',
           'quando' => (agora - 5.days).to_i, 'situacao' => 'pendente', 'pessoa' => 'Ana Albuquerino' }]
      )
    end

    it 'não mostra ao agente a conversa de caixa que ele não lê; o administrador vê' do
      dele = conversa_de(ana)
      de_outra_caixa = conversa_de(ana, caixa_dela: outra_caixa, falou: agora - 1.day)

      ler("empresas/#{padaria.id}/conversas")
      expect(response.parsed_body.pluck('id')).to eq([dele.display_id])

      ler("empresas/#{padaria.id}/conversas", quem: admin)
      expect(response.parsed_body.pluck('id')).to eq([dele.display_id, de_outra_caixa.display_id])
    end

    it 'não faz uma consulta a mais por conversa' do
      criar = ->(nome) { mensagem(conversa_de(pessoa_da(padaria, name: nome)), 'Recebi o material, ficou ótimo.') }
      criar.call('Pessoa 0')
      cabecalhos = agente.create_new_auth_token
      pedir = -> { get "#{base}/empresas/#{padaria.id}/conversas", headers: cabecalhos }
      pedir.call
      com_uma = consultas_feitas(&pedir)
      3.times { |n| criar.call("Outra #{n}") }

      expect(consultas_feitas(&pedir)).to eq(com_uma)
      expect(response.parsed_body.pluck('pessoa')).to contain_exactly('Pessoa 0', 'Outra 0', 'Outra 1', 'Outra 2')
    end
  end

  describe 'GET empresas/:id/cards' do
    it 'devolve os cards da empresa com o nome de quem é: o da pessoa dela e o de prospecção, sem pessoa' do
      da_ana = card_de(ana, value_cents: 150_000, created_at: agora - 1.day)
      prospeccao = account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, title: 'Reforma da recepção', inbox: caixa,
                                             created_at: agora - 2.days,
                                             metadata: { 'autonomia_prospecting' => { 'company' => { 'id' => padaria.id.to_s } } })

      ler("empresas/#{padaria.id}/cards")

      expect(response.parsed_body).to eq(
        [{ 'id' => da_ana.id, 'titulo' => 'Pedido de orçamento', 'funil' => 'Vendas', 'etapa' => 'Novo Lead', 'valor' => 1500.0,
           'situacao' => 'aberto', 'pessoa' => 'Ana Albuquerino' },
         { 'id' => prospeccao.id, 'titulo' => 'Reforma da recepção', 'funil' => 'Vendas', 'etapa' => 'Novo Lead', 'valor' => 0.0,
           'situacao' => 'aberto', 'pessoa' => nil }]
      )
    end

    it 'mostra ao agente só os cards que ele enxerga no CRM' do
      dele = card_de(ana)
      card_de(ana, inbox: outra_caixa)

      ler("empresas/#{padaria.id}/cards")

      expect(response.parsed_body.pluck('id')).to eq([dele.id])
    end

    it 'vem vazio com o CRM desligado' do
      card_de(ana)

      with_modified_env(CRM_KANBAN_ENABLED: 'false') { ler("empresas/#{padaria.id}/cards") }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([])
    end

    it 'não faz uma consulta a mais por card' do
      criar = ->(nome) { card_de(pessoa_da(padaria, name: nome)) }
      criar.call('Pessoa 0')
      cabecalhos = agente.create_new_auth_token
      pedir = -> { get "#{base}/empresas/#{padaria.id}/cards", headers: cabecalhos }
      pedir.call
      com_um = consultas_feitas(&pedir)
      3.times { |n| criar.call("Outra #{n}") }

      expect(consultas_feitas(&pedir)).to eq(com_um)
      expect(response.parsed_body.pluck('pessoa')).to contain_exactly('Pessoa 0', 'Outra 0', 'Outra 1', 'Outra 2')
    end
  end

  describe 'funções personalizadas' do
    it 'recusa a função sem a chave de contatos em todas as leituras da ficha' do
      sem_contatos = pessoa_com(%w[conversation_manage crm_view])

      (leituras_da_pessoa + ["pessoas/#{ana.id}/cards"] + leituras_da_empresa).each do |caminho|
        ler(caminho, quem: sem_contatos)

        expect(response).to have_http_status(:unauthorized), caminho
      end
    end

    it 'atende a função com contact_view e o administrador' do
      [pessoa_com(%w[contact_view]), admin].each do |quem|
        (leituras_da_pessoa + leituras_da_empresa.first(3)).each do |caminho|
          ler(caminho, quem: quem)

          expect(response).to have_http_status(:ok), "#{caminho} (#{quem.id})"
        end
      end
    end

    it 'os cards pedem também a chave de ver o CRM, como os funis da lista' do
      card_de(ana)

      ["pessoas/#{ana.id}/cards", "empresas/#{padaria.id}/cards"].each do |caminho|
        ler(caminho, quem: pessoa_com(%w[contact_view]))
        expect(response).to have_http_status(:unauthorized), caminho

        ler(caminho, quem: pessoa_com(%w[contact_view crm_view]))
        expect(response).to have_http_status(:ok), caminho
        expect(response.parsed_body.size).to eq(1), caminho
      end
    end

    it 'conversas e arquivos seguem a regra de leitura das conversas: quem só lê (conversation_view) vê, quem não lê não vê' do
      conversa = conversa_de(ana)
      anexo = mensagem(conversa, nil).attachments.new(account_id: account.id, file_type: :file)
      anexo.file.attach(io: StringIO.new('conteudo'), filename: 'comprovante.pdf', content_type: 'application/pdf', identify: false)
      anexo.save!
      conversa_de(ana, caixa_dela: outra_caixa)
      so_le = pessoa_com(%w[contact_view conversation_view])
      nao_le = pessoa_com(%w[contact_view])

      { "pessoas/#{ana.id}/conversas" => [conversa.display_id], "empresas/#{padaria.id}/conversas" => [conversa.display_id],
        "pessoas/#{ana.id}/arquivos" => [anexo.id] }.each do |caminho, esperado|
        ler(caminho, quem: so_le)
        expect(response.parsed_body.pluck('id')).to eq(esperado), caminho

        ler(caminho, quem: nao_le)
        expect(response.parsed_body).to eq([]), caminho
      end
    end

    it 'o valor do card some para a função sem sales_value_view, menos no card de que ela é dona' do
      sem_chave = pessoa_com(%w[contact_view crm_view])
      com_chave = pessoa_com(%w[contact_view crm_view sales_value_view])
      card_de(ana, title: 'Alheio', value_cents: 500_000, owner: admin)
      card_de(ana, title: 'Próprio', value_cents: 120_000, owner: sem_chave)
      valores = ->(caminho, quem) { ler(caminho, quem: quem).then { response.parsed_body.to_h { |card| [card['titulo'], card['valor']] } } }

      ["pessoas/#{ana.id}/cards", "empresas/#{padaria.id}/cards"].each do |caminho|
        expect(valores.call(caminho, sem_chave)).to eq('Alheio' => nil, 'Próprio' => 1200.0), caminho
        expect(valores.call(caminho, com_chave)).to eq('Alheio' => 5000.0, 'Próprio' => 1200.0), caminho
        expect(valores.call(caminho, agente)).to eq('Alheio' => 5000.0, 'Próprio' => 1200.0), caminho
      end
    end
  end
end
