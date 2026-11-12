require 'rails_helper'

# #2895 — as leituras da ficha da pessoa de Relacionamentos, no formato que a tela lê: a pessoa, as conversas, os cards,
# as notas, os arquivos e de onde ela veio. A metade de função personalizada e a ficha da empresa ficam em
# spec/enterprise/requests/relacionamentos/ficha_spec.rb.
RSpec.describe 'Ficha da pessoa de Relacionamentos', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/relacionamentos" }
  let(:agora) { Time.zone.parse('2026-11-11 12:00:00') }
  # Sem o "pedir e-mail" da caixa do site: com ele, cada mensagem que chega ganha uma resposta automática da caixa.
  let(:caixa) { create(:inbox, account: account, enable_email_collect: false) }
  let(:outra_caixa) { create(:inbox, account: account) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let!(:ana) { create(:contact, account: account, name: 'Ana Albuquerino', contact_type: :lead, created_at: agora - 40.days) }
  let(:partes) { ['', '/conversas', '/cards', '/notas', '/arquivos', '/origem'] }
  let(:leituras) { partes.map { |parte| "pessoas/#{ana.id}#{parte}" } }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before do
    account.enable_features!('relacionamentos_novo')
    travel_to(agora)
    create(:inbox_member, user: agente, inbox: caixa)
  end

  def ler(caminho, quem: agente, **params)
    get "#{base}/#{caminho}", params: params, headers: quem.create_new_auth_token
  end

  def conversa_de(pessoa, caixa_dela: caixa, falou: agora, **dados)
    create(:conversation, account: account, inbox: caixa_dela, contact: pessoa, **dados).tap { |conversa| conversa.update!(last_activity_at: falou) }
  end

  def mensagem(conversa, texto, tipo: :incoming)
    create(:message, account: conversa.account, inbox: conversa.inbox, conversation: conversa, content: texto, message_type: tipo)
  end

  def arquivo(conversa, nome, tipo, formato, quando: agora)
    anexo = mensagem(conversa, nil).attachments.new(account_id: conversa.account_id, file_type: tipo, created_at: quando)
    anexo.file.attach(io: StringIO.new('conteudo'), filename: nome, content_type: formato, identify: false)
    anexo.tap(&:save!)
  end

  def card_de(pessoa, funil: vendas, **dados)
    account.crm_cards.create!(pipeline: funil.first, stage: funil.last, contact: pessoa, title: 'Pedido de orçamento', **dados)
  end

  def consultas_feitas(&)
    feitas = 0
    contar = ->(*, dados) { feitas += 1 unless dados[:cached] || %w[SCHEMA TRANSACTION].include?(dados[:name]) }
    ActiveSupport::Notifications.subscribed(contar, 'sql.active_record', &)
    feitas
  end

  describe 'em todas as leituras' do
    it 'responde 401 sem login' do
      leituras.each do |caminho|
        get "#{base}/#{caminho}"

        expect(response).to have_http_status(:unauthorized), caminho
      end
    end

    it 'responde 404 com a chave da conta desligada' do
      account.disable_features!('relacionamentos_novo')

      leituras.each do |caminho|
        ler(caminho)

        expect(response).to have_http_status(:not_found), caminho
      end
    end

    it 'atende o agente comum, como o contato de hoje' do
      leituras.each do |caminho|
        ler(caminho)

        expect(response).to have_http_status(:ok), caminho
      end
    end

    it 'responde 404 para pessoa de outra conta e para pessoa que não existe' do
      de_fora = create(:contact, account: create(:account), name: 'Bruno de outra conta')

      [de_fora.id, 0].each do |id|
        partes.each do |parte|
          ler("pessoas/#{id}#{parte}")

          expect(response).to have_http_status(:not_found), "#{id}#{parte}"
        end
      end
    end

    it 'responde 422 com a frase para parâmetro que a ficha não conhece' do
      leituras.each do |caminho|
        ler(caminho, pagina: 2)

        expect(response).to have_http_status(:unprocessable_entity), caminho
        expect(response.parsed_body).to eq('error' => 'parâmetro desconhecido: pagina')
      end
    end

    it 'não mistura o que é de outra pessoa da conta' do
      bruno = create(:contact, account: account, name: 'Bruno Brandolim')
      arquivo(conversa_de(bruno), 'comprovante.pdf', :file, 'application/pdf')
      card_de(bruno, inbox: caixa)
      create(:note, account: account, contact: bruno, user: admin, content: 'Pediu retorno.')

      %w[conversas cards notas arquivos].each do |parte|
        ler("pessoas/#{ana.id}/#{parte}")

        expect(response.parsed_body).to eq([]), parte
      end
    end
  end

  describe 'GET pessoas/:id' do
    it 'devolve a pessoa com os campos da lista e as informações inteiras' do
      account.disable_features!('companies')
      ana.update!(email: 'ana.albuquerino@exemplo.com.br', phone_number: '+5511910310001', contact_type: :customer,
                  customer_since: agora - 20.days, last_activity_at: agora - 2.days, opted_out_at: agora - 1.day, opt_out_source: 'manual',
                  additional_attributes: { city: 'Campinas', company_name: 'Padaria Bom Dia', social_profiles: { instagram: '@ana.albuquerino' } },
                  custom_attributes: { cpf: '123.456.789-00', melhor_horario: 'Tarde' })
      ana.update_labels(%w[feira])

      ler("pessoas/#{ana.id}")

      expect(response.parsed_body).to eq(
        'id' => ana.id, 'name' => 'Ana Albuquerino', 'email' => 'ana.albuquerino@exemplo.com.br',
        'phone_number' => '+5511910310001', 'thumbnail' => '', 'blocked' => false, 'contact_type' => 'customer',
        'customer_since' => (agora - 20.days).to_i, 'last_activity_at' => (agora - 2.days).to_i, 'created_at' => (agora - 40.days).to_i,
        'additional_attributes' => { 'city' => 'Campinas', 'company_name' => 'Padaria Bom Dia',
                                     'social_profiles' => { 'instagram' => '@ana.albuquerino' } },
        'custom_attributes' => { 'cpf' => '123.456.789-00', 'melhor_horario' => 'Tarde' }, 'labels' => %w[feira],
        'opted_out_at' => (agora - 1.day).to_i, 'opt_out_source' => 'manual'
      )
    end
  end

  describe 'GET pessoas/:id/conversas' do
    it 'devolve canal, trecho da última mensagem que alguém escreveu, quando e situação, da mais recente para trás' do
      antiga = conversa_de(ana)
      mensagem(antiga, 'Oi, tudo bem? Queria saber os horários.')
      mensagem(antiga, 'Combinado, então fico no aguardo.')
      mensagem(antiga, 'Conversa resolvida por Sônia', tipo: :activity)
      antiga.update!(status: :resolved, last_activity_at: agora - 9.days)
      nova = conversa_de(ana, falou: agora - 2.days)

      ler("pessoas/#{ana.id}/conversas")

      expect(response.parsed_body).to eq(
        [{ 'id' => nova.display_id, 'canal' => 'site', 'trecho' => nil, 'quando' => (agora - 2.days).to_i, 'situacao' => 'aberta' },
         { 'id' => antiga.display_id, 'canal' => 'site', 'trecho' => 'Combinado, então fico no aguardo.',
           'quando' => (agora - 9.days).to_i, 'situacao' => 'resolvida' }]
      )
    end

    it 'diz a situação de cada conversa em palavra' do
      %i[open pending resolved snoozed].each_with_index { |status, dias| conversa_de(ana, status: status, falou: agora - dias.days) }

      ler("pessoas/#{ana.id}/conversas")

      expect(response.parsed_body.pluck('situacao')).to eq(%w[aberta pendente resolvida adiada])
    end

    it 'diz o canal da caixa: a caixa do WhatsApp pelo celular é WhatsApp, a de API comum é outro' do
      celular = create_crm_inbox(account: account, name: 'WhatsApp do balcão', members: [agente])
      celular.channel.update!(additional_attributes: { provider: 'waha' })
      conversa_de(ana, caixa_dela: celular, falou: agora - 1.day)
      conversa_de(ana, caixa_dela: create_crm_inbox(account: account, members: [agente]), falou: agora - 2.days)

      ler("pessoas/#{ana.id}/conversas")

      expect(response.parsed_body.pluck('canal')).to eq(%w[whatsapp outro])
    end

    it 'o trecho é o que alguém escreveu: mensagem automática da caixa não entra' do
      conversa = conversa_de(ana)
      mensagem(conversa, 'Quero renovar o seguro do carro.')
      mensagem(conversa, 'Get notified by email', tipo: :template)

      ler("pessoas/#{ana.id}/conversas")

      expect(response.parsed_body.first['trecho']).to eq('Quero renovar o seguro do carro.')
    end

    it 'nota interna da equipe não é trecho: vale a última mensagem trocada com a pessoa' do
      conversa = conversa_de(ana)
      mensagem(conversa, 'Pode me ligar depois das 18h?')
      mensagem(conversa, 'Cliente difícil, cuidado.', tipo: :outgoing).update!(private: true)

      ler("pessoas/#{ana.id}/conversas")

      expect(response.parsed_body.first['trecho']).to eq('Pode me ligar depois das 18h?')
    end

    it 'corta o trecho comprido' do
      mensagem(conversa_de(ana), 'a' * 500)

      ler("pessoas/#{ana.id}/conversas")

      expect(response.parsed_body.first['trecho'].length).to eq(Relacionamentos::Ficha::Conversas::TRECHO)
    end

    it 'não mostra ao agente a conversa de caixa que ele não lê; o administrador vê' do
      dele = conversa_de(ana)
      de_outra_caixa = conversa_de(ana, caixa_dela: outra_caixa, falou: agora - 1.day)

      ler("pessoas/#{ana.id}/conversas")
      expect(response.parsed_body.pluck('id')).to eq([dele.display_id])

      ler("pessoas/#{ana.id}/conversas", quem: admin)
      expect(response.parsed_body.pluck('id')).to eq([dele.display_id, de_outra_caixa.display_id])
    end

    it 'devolve só as mais recentes, até o teto' do
      stub_const('Relacionamentos::Ficha::Conversas::TETO', 1)
      conversa_de(ana, falou: agora - 3.days)
      recente = conversa_de(ana, falou: agora - 1.day)

      ler("pessoas/#{ana.id}/conversas")

      expect(response.parsed_body.pluck('id')).to eq([recente.display_id])
    end

    it 'não faz uma consulta a mais por conversa' do
      criar = -> { mensagem(conversa_de(ana), 'Bom dia! Chegou o que eu pedi?') }
      criar.call
      cabecalhos = agente.create_new_auth_token
      pedir = -> { get "#{base}/pessoas/#{ana.id}/conversas", headers: cabecalhos }
      pedir.call
      com_uma = consultas_feitas(&pedir)
      3.times { criar.call }

      expect(consultas_feitas(&pedir)).to eq(com_uma)
      expect(response.parsed_body.pluck('trecho')).to eq(['Bom dia! Chegou o que eu pedi?'] * 4)
    end
  end

  describe 'GET pessoas/:id/cards' do
    it 'devolve título, funil, etapa, valor em reais e situação: abertos primeiro, mais novos primeiro' do
      fechado = card_de(ana, title: 'Plano mensal', value_cents: 30_000, status: :won, created_at: agora - 1.day)
      antigo = card_de(ana, title: 'Visita agendada', created_at: agora - 9.days)
      novo = card_de(ana, value_cents: 150_050, created_at: agora - 2.days)

      ler("pessoas/#{ana.id}/cards", quem: admin)

      expect(response.parsed_body).to eq(
        [{ 'id' => novo.id, 'titulo' => 'Pedido de orçamento', 'funil' => 'Vendas', 'etapa' => 'Novo Lead', 'valor' => 1500.5,
           'situacao' => 'aberto' },
         { 'id' => antigo.id, 'titulo' => 'Visita agendada', 'funil' => 'Vendas', 'etapa' => 'Novo Lead', 'valor' => 0.0,
           'situacao' => 'aberto' },
         { 'id' => fechado.id, 'titulo' => 'Plano mensal', 'funil' => 'Vendas', 'etapa' => 'Novo Lead', 'valor' => 300.0,
           'situacao' => 'ganho' }]
      )
    end

    it 'diz a situação de cada card em palavra; o arquivado não aparece' do
      atendimento = create_crm_pipeline(account: account, user: admin, name: 'Atendimento').tap { |funil, _| funil.update!(counts_as_sale: false) }
      { open: vendas, won: vendas, lost: vendas, resolved: atendimento, cancelled: atendimento }.each_with_index do |(status, funil), dias|
        card_de(ana, funil: funil, status: status, created_at: agora - dias.days)
      end
      card_de(ana, status: :archived)

      ler("pessoas/#{ana.id}/cards", quem: admin)

      expect(response.parsed_body.pluck('situacao')).to eq(%w[aberto ganho perdido resolvido cancelado])
    end

    it 'mostra ao agente só os cards que ele enxerga no CRM' do
      dele = card_de(ana, inbox: caixa)
      card_de(ana, inbox: outra_caixa)

      ler("pessoas/#{ana.id}/cards")

      expect(response.parsed_body.pluck('id')).to eq([dele.id])
    end

    it 'vem vazio com o CRM desligado' do
      card_de(ana, inbox: caixa)

      with_modified_env(CRM_KANBAN_ENABLED: 'false') { ler("pessoas/#{ana.id}/cards") }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([])
    end

    it 'devolve só até o teto' do
      stub_const('Relacionamentos::Ficha::Cards::TETO', 1)
      card_de(ana, created_at: agora - 3.days)
      recente = card_de(ana, created_at: agora - 1.day)

      ler("pessoas/#{ana.id}/cards", quem: admin)

      expect(response.parsed_body.pluck('id')).to eq([recente.id])
    end

    it 'não faz uma consulta a mais por card' do
      criar = ->(nome) { card_de(ana, funil: create_crm_pipeline(account: account, user: admin, name: nome)) }
      criar.call('Funil 0')
      cabecalhos = admin.create_new_auth_token
      pedir = -> { get "#{base}/pessoas/#{ana.id}/cards", headers: cabecalhos }
      pedir.call
      com_um = consultas_feitas(&pedir)
      3.times { |n| criar.call("Funil #{n + 1}") }

      expect(consultas_feitas(&pedir)).to eq(com_um)
      expect(response.parsed_body.pluck('funil')).to contain_exactly('Funil 0', 'Funil 1', 'Funil 2', 'Funil 3')
    end
  end

  describe 'GET pessoas/:id/notas' do
    it 'devolve autor, quando e texto, das mais novas para trás' do
      sonia = create(:user, account: account, role: :agent, name: 'Sônia Valtorini')
      antiga = create(:note, account: account, contact: ana, user: sonia, content: 'Pediu retorno na próxima semana.',
                             created_at: agora - 35.days)
      nova = create(:note, account: account, contact: ana, user: nil, content: 'Prefere conversar à tarde.', created_at: agora - 3.days)

      ler("pessoas/#{ana.id}/notas")

      expect(response.parsed_body).to eq(
        [{ 'id' => nova.id, 'autor' => nil, 'quando' => (agora - 3.days).to_i, 'texto' => 'Prefere conversar à tarde.' },
         { 'id' => antiga.id, 'autor' => 'Sônia Valtorini', 'quando' => (agora - 35.days).to_i, 'texto' => 'Pediu retorno na próxima semana.' }]
      )
    end

    it 'não faz uma consulta a mais por nota' do
      criar = -> { create(:note, account: account, contact: ana, user: create(:user, account: account), content: 'Indicou um amigo.') }
      criar.call
      cabecalhos = agente.create_new_auth_token
      pedir = -> { get "#{base}/pessoas/#{ana.id}/notas", headers: cabecalhos }
      pedir.call
      com_uma = consultas_feitas(&pedir)
      3.times { criar.call }

      expect(consultas_feitas(&pedir)).to eq(com_uma)
      expect(response.parsed_body.size).to eq(4)
    end
  end

  describe 'GET pessoas/:id/arquivos' do
    it 'devolve nome, tipo e quando de cada arquivo das conversas, do mais novo para trás' do
      conversa = conversa_de(ana)
      foto = arquivo(conversa, 'foto-da-fachada.jpg', :image, 'image/jpeg', quando: agora - 1.day)
      audio = arquivo(conversa, 'audio-do-pedido.ogg', :audio, 'audio/ogg', quando: agora - 2.days)
      video = arquivo(conversa, 'video-do-local.mp4', :video, 'video/mp4', quando: agora - 3.days)
      pdf = arquivo(conversa, 'comprovante.pdf', :file, 'application/pdf', quando: agora - 4.days)
      mensagem(conversa, nil).attachments.create!(account_id: account.id, file_type: :location, coordinates_lat: -23.5, coordinates_long: -46.6)

      ler("pessoas/#{ana.id}/arquivos")

      expect(response.parsed_body).to eq(
        [{ 'id' => foto.id, 'nome' => 'foto-da-fachada.jpg', 'tipo' => 'imagem', 'quando' => (agora - 1.day).to_i },
         { 'id' => audio.id, 'nome' => 'audio-do-pedido.ogg', 'tipo' => 'audio', 'quando' => (agora - 2.days).to_i },
         { 'id' => video.id, 'nome' => 'video-do-local.mp4', 'tipo' => 'video', 'quando' => (agora - 3.days).to_i },
         { 'id' => pdf.id, 'nome' => 'comprovante.pdf', 'tipo' => 'documento', 'quando' => (agora - 4.days).to_i }]
      )
    end

    it 'arquivo de nota interna da equipe não entra: só o que foi trocado com a pessoa' do
      conversa = conversa_de(ana)
      trocado = arquivo(conversa, 'comprovante.pdf', :file, 'application/pdf')
      arquivo(conversa, 'anotacao-interna.pdf', :file, 'application/pdf', quando: agora - 1.day).message.update!(private: true)

      ler("pessoas/#{ana.id}/arquivos")

      expect(response.parsed_body.pluck('id')).to eq([trocado.id])
    end

    it 'não mostra ao agente o arquivo de caixa que ele não lê; o administrador vê' do
      dele = arquivo(conversa_de(ana), 'comprovante.pdf', :file, 'application/pdf')
      de_outra_caixa = arquivo(conversa_de(ana, caixa_dela: outra_caixa), 'planilha-de-itens.pdf', :file, 'application/pdf', quando: agora - 1.day)

      ler("pessoas/#{ana.id}/arquivos")
      expect(response.parsed_body.pluck('id')).to eq([dele.id])

      ler("pessoas/#{ana.id}/arquivos", quem: admin)
      expect(response.parsed_body.pluck('id')).to eq([dele.id, de_outra_caixa.id])
    end

    it 'devolve só os mais novos, até o teto' do
      stub_const('Relacionamentos::Ficha::Arquivos::TETO', 1)
      conversa = conversa_de(ana)
      arquivo(conversa, 'comprovante.pdf', :file, 'application/pdf', quando: agora - 3.days)
      recente = arquivo(conversa, 'foto-da-fachada.jpg', :image, 'image/jpeg', quando: agora - 1.day)

      ler("pessoas/#{ana.id}/arquivos")

      expect(response.parsed_body.pluck('id')).to eq([recente.id])
    end

    it 'não faz uma consulta a mais por arquivo' do
      conversa = conversa_de(ana)
      criar = -> { arquivo(conversa, 'comprovante.pdf', :file, 'application/pdf') }
      criar.call
      cabecalhos = agente.create_new_auth_token
      pedir = -> { get "#{base}/pessoas/#{ana.id}/arquivos", headers: cabecalhos }
      pedir.call
      com_um = consultas_feitas(&pedir)
      3.times { criar.call }

      expect(consultas_feitas(&pedir)).to eq(com_um)
      expect(response.parsed_body.pluck('nome')).to eq(['comprovante.pdf'] * 4)
    end
  end

  describe 'GET pessoas/:id/origem' do
    def importacao(conta: account, **dados)
      conta.campaign_imports.create!(user: create(:user, account: conta), status: :completed, **dados)
    end

    def linha_de(lista, pessoa, ja_existia:)
      lista.campaign_import_rows.create!(row_number: 1, contact_id: pessoa.id, status: :imported, was_existing_contact: ja_existia)
    end

    it 'diz a lista quando a pessoa foi criada por uma importação, com a data em que ela chegou' do
      linha_de(importacao(name: 'Feira de maio'), ana, ja_existia: false)
      create(:contact_inbox, contact: ana, inbox: caixa)

      ler("pessoas/#{ana.id}/origem")

      expect(response.parsed_body).to eq('tipo' => 'lista', 'nome' => 'Feira de maio', 'quando' => (agora - 40.days).to_i)
    end

    it 'a base de campanha antiga, sem nome, leva o nome da campanha' do
      linha_de(importacao(name: nil, campaign_name: 'Clientes 2025'), ana, ja_existia: false)

      ler("pessoas/#{ana.id}/origem")

      expect(response.parsed_body).to include('tipo' => 'lista', 'nome' => 'Clientes 2025')
    end

    it 'diz o canal da primeira caixa quando a importação só achou a pessoa que já existia' do
      linha_de(importacao(name: 'Indicações'), ana, ja_existia: true)
      de_la = create(:account)
      linha_de(importacao(conta: de_la, name: 'De outra conta'), ana, ja_existia: false)
      create(:contact_inbox, contact: ana, inbox: create_crm_inbox(account: account), created_at: agora - 5.days)
      create(:contact_inbox, contact: ana, inbox: caixa, created_at: agora - 30.days)

      ler("pessoas/#{ana.id}/origem")

      expect(response.parsed_body).to eq('tipo' => 'canal', 'canal' => 'site', 'quando' => (agora - 30.days).to_i)
    end

    it 'vem vazia para quem não veio de lista nem entrou por caixa nenhuma' do
      ler("pessoas/#{ana.id}/origem")

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to be_nil
    end
  end

  # O PATCH do contato leva o CPF em custom_attributes, e o da empresa leva o CNPJ: nenhum dos dois vai para o log.
  it 'CPF, CNPJ, documento e o texto da busca saem filtrados da linha de parâmetros do log' do
    filtro = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    pedido = { 'name' => 'Ana Albuquerino', 'custom_attributes' => { 'cpf' => '123.456.789-00', 'melhor_horario' => 'Tarde' },
               'additional_attributes' => { 'cnpj' => '12.345.678/0001-00', 'city' => 'Campinas' }, 'documento' => '12345678900',
               'busca' => '123.456.789-00' }

    expect(filtro.filter(pedido)).to eq(
      'name' => 'Ana Albuquerino', 'custom_attributes' => { 'cpf' => '[FILTERED]', 'melhor_horario' => 'Tarde' },
      'additional_attributes' => { 'cnpj' => '[FILTERED]', 'city' => 'Campinas' }, 'documento' => '[FILTERED]', 'busca' => '[FILTERED]'
    )
  end
end
