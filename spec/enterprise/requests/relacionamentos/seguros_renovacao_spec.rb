require 'rails_helper'

# E5 (#2898) — a parte da renovação da carteira que depende do Enterprise: o que a função personalizada muda. Ler pede
# ver contatos; guardar os ajustes pede editar contatos; escolher o funil pede também ver o CRM; dizer como a renovação
# terminou pede editar contatos e poder mexer naquele card no quadro; o aviso no sino vai a quem vê contatos e o CRM.
# Tudo fictício.
RSpec.describe 'Carteira de seguros: renovação e funções', type: :request do
  # Meio-dia em São Paulo: para a conta, hoje é 12/11/2026.
  let(:agora) { Time.utc(2026, 11, 12, 15) }
  let(:hoje) { Date.new(2026, 11, 12) }
  let(:account) { conta_com_carteira(reporting_timezone: 'America/Sao_Paulo', locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:base) { "/api/v1/accounts/#{account.id}/relacionamentos" }
  let(:caixa) { create(:inbox, account: account, enable_email_collect: false) }
  let(:ajustes) { escolher_funil_de_renovacao(account, user: admin) }
  let(:marina) { create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000023', contact_type: :customer) }
  let(:seguro) { criar_apolice(marina, numero: 'EX-000001', fim_vigencia: hoje + 5) }
  let(:card) { por_em_renovacao(seguro, ajustes) }
  let(:acoes) { %w[renovou nao_renovou desfazer_desfecho] }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before do
    travel_to(agora)
    card
  end

  def pessoa_com(permissions)
    user = create(:user, account: account, role: :agent)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    create(:inbox_member, user: user, inbox: caixa)
    user
  end

  def ler_ajustes(quem)
    get "#{base}/seguros/renovacoes", headers: quem.create_new_auth_token
    response.parsed_body
  end

  def guardar_ajustes(quem, dados)
    put "#{base}/seguros/renovacoes", params: dados, headers: quem.create_new_auth_token, as: :json
    [response.status, response.parsed_body]
  end

  # O código de cada resposta de "Renovou", "Não renovou" e "Desfazer", nessa ordem.
  def dizer_o_desfecho(quem)
    acoes.map do |nome|
      post "#{base}/seguros/#{seguro.id}/#{nome}", headers: quem.create_new_auth_token, as: :json
      response.status
    end
  end

  describe 'ajustar renovações' do
    it 'quem só vê contatos lê os ajustes, sem os funis e avisada de que não muda' do
      lido = ler_ajustes(pessoa_com(%w[contact_view]))

      expect(response).to have_http_status(:ok)
      expect(lido).to include('funis' => [], 'semPermissao' => true)
      expect(lido['ajustes']).to include('funilId' => ajustes.pipeline_id, 'dias' => 60)
    end

    it 'quem vê contatos e o CRM lê os funis, mas não guarda' do
      so_ve = pessoa_com(%w[contact_view crm_view])

      lido = ler_ajustes(so_ve)
      guardado = guardar_ajustes(so_ve, { dias: 30 })

      expect(lido['funis'].pluck('nome')).to eq(['Renovação'])
      expect(lido['semPermissao']).to be(true)
      expect([guardado.first, ajustes.reload.dias_antes]).to eq([401, 60])
    end

    it 'quem edita contatos e vê o CRM guarda, com o funil' do
      edita = pessoa_com(%w[contact_manage crm_view])
      outro_funil, outra_etapa = create_crm_pipeline(account: account, user: admin, name: 'Pós-venda')

      lido = ler_ajustes(edita)
      guardado = guardar_ajustes(edita, { funilId: outro_funil.id, etapaId: outra_etapa.id, dias: 30 })

      expect(lido['semPermissao']).to be(false)
      expect(guardado).to eq([200, { 'funilId' => outro_funil.id, 'etapaId' => outra_etapa.id, 'dias' => 30, 'mensagens' => 'mandar' }])
      expect(ajustes.reload).to have_attributes(pipeline_id: outro_funil.id, user_id: edita.id)
    end

    it 'quem edita contatos sem ver o CRM muda os dias, mas não escolhe o funil' do
      edita = pessoa_com(%w[contact_manage])

      dos_dias = guardar_ajustes(edita, { dias: 45 })
      do_funil = guardar_ajustes(edita, { funilId: ajustes.pipeline_id, etapaId: ajustes.stage_id })

      expect([dos_dias.first, do_funil]).to eq([200, [422, { 'error' => 'funil_desconhecido' }]])
      expect(ajustes.reload).to have_attributes(dias_antes: 45, user_id: edita.id)
    end

    it 'sem a chave de contatos não lê nem guarda' do
      sem_contatos = pessoa_com(%w[conversation_manage crm_view])

      ler_ajustes(sem_contatos)
      lendo = response.status

      expect([lendo, guardar_ajustes(sem_contatos, { dias: 30 }).first, ajustes.reload.dias_antes]).to eq([401, 401, 60])
    end
  end

  describe 'como terminou a renovação' do
    it 'quem só vê contatos não diz o desfecho, mesmo mexendo em cards' do
      expect(dizer_o_desfecho(pessoa_com(%w[contact_view crm_view crm_manage_cards]))).to eq([401, 401, 401])
      expect([card.reload.status, seguro.eventos.count]).to eq(['open', 1])
    end

    it 'quem edita contatos mas não mexe em cards também não' do
      expect(dizer_o_desfecho(pessoa_com(%w[contact_manage crm_view]))).to eq([401, 401, 401])
      expect(card.reload.status).to eq('open')
    end

    it 'quem edita contatos e mexe em cards só fecha o card que enxerga no quadro: o dela' do
      quem = pessoa_com(%w[contact_manage crm_view crm_manage_cards])

      sem_o_card = dizer_o_desfecho(quem)
      card.update!(owner: quem)
      post "#{base}/seguros/#{seguro.id}/renovou", headers: quem.create_new_auth_token, as: :json

      expect(sem_o_card).to eq([401, 401, 401])
      expect([response.status, card.reload.status, seguro.reload.renovado_em]).to eq([200, 'won', agora])
    end

    it 'guardar a apólice nova pede só editar contatos' do
      nova = { anteriorId: seguro.id, tipo: 'auto', seguradora: 'Outra Seguradora Exemplo', numero: 'OS-777001', termina: '2027-11-17' }
      respostas = [pessoa_com(%w[contact_view crm_view crm_manage_cards]), pessoa_com(%w[contact_manage])].map do |quem|
        post "#{base}/seguros", params: nova, headers: quem.create_new_auth_token, as: :json
        response.status
      end

      expect(respostas).to eq([401, 201])
      expect([card.reload.status, seguro.reload.renovado_em]).to eq(['won', agora])
    end
  end

  describe 'o aviso no sino' do
    it 'vai a quem vê contatos e o CRM, e não a quem falta um dos dois' do
      ve_os_dois = pessoa_com(%w[contact_view crm_view])
      pessoa_com(%w[contact_view])
      pessoa_com(%w[conversation_manage crm_view])

      Carteira::Aviso.new(account, ajustes).entraram

      expect(Notification.where(notification_type: 'carteira_renovacao').pluck(:user_id)).to contain_exactly(admin.id, ve_os_dois.id)
    end
  end
end
