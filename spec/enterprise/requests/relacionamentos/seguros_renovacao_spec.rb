require 'rails_helper'

# E5 (#2898) — a parte da renovação da carteira que depende do Enterprise: o que a função personalizada muda. Ler pede
# ver contatos; guardar os ajustes pede as DUAS chaves, editar contatos e montar os funis (que já traz a de ver o
# CRM); dizer como a renovação terminou pede editar contatos e poder mexer naquele card no quadro; o id do card só
# vai para quem o enxerga; o aviso no sino vai a quem vê contatos e o CRM. Tudo fictício.
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

    # Guardar muda uma escolha da conta inteira e diz em que funil o CRM recebe os cards: pede as duas chaves.
    # Os quatro casos: nenhuma, só editar contatos, só montar os funis, as duas.
    {
      'nenhuma das duas' => [%w[contact_view crm_view], false],
      'só a de editar contatos' => [%w[contact_manage crm_view], false],
      'só a de montar os funis' => [%w[contact_view crm_view crm_manage_pipelines], false],
      'as duas' => [%w[contact_manage crm_view crm_manage_pipelines], true]
    }.each do |caso, (chaves, guarda)|
      it "com #{caso}, #{guarda ? 'guarda' : 'lê os funis mas não guarda'}" do
        quem = pessoa_com(chaves)

        lido = ler_ajustes(quem)
        guardado = guardar_ajustes(quem, { dias: 30 })

        expect(lido['funis'].pluck('nome')).to eq(['Renovação'])
        expect([lido['semPermissao'], guardado.first, ajustes.reload.dias_antes]).to eq(guarda ? [false, 200, 30] : [true, 401, 60])
      end
    end

    it 'quem tem as duas chaves guarda com o funil, e fica como quem escolheu' do
      monta = pessoa_com(%w[contact_manage crm_view crm_manage_pipelines])
      outro_funil, outra_etapa = create_crm_pipeline(account: account, user: admin, name: 'Pós-venda')

      guardado = guardar_ajustes(monta, { funilId: outro_funil.id, etapaId: outra_etapa.id, dias: 30 })

      expect(guardado).to eq([200, { 'funilId' => outro_funil.id, 'etapaId' => outra_etapa.id, 'dias' => 30 }])
      expect(ajustes.reload).to have_attributes(pipeline_id: outro_funil.id, user_id: monta.id)
    end

    # Não existe "monta os funis sem ver o CRM": a função com uma chave de mexer no CRM é salva com `crm_view` junto
    # (CustomRole, #2124). Quem tem as duas chaves enxerga os funis e escolhe; mudar só os dias não faz dela quem escolheu.
    it 'a chave de montar os funis já traz a de ver o CRM: quem tem as duas muda os dias e escolhe o funil' do
      monta = pessoa_com(%w[contact_manage crm_manage_pipelines])

      dos_dias = guardar_ajustes(monta, { dias: 45 })
      quem_escolheu = ajustes.reload.user_id
      do_funil = guardar_ajustes(monta, { funilId: ajustes.pipeline_id, etapaId: ajustes.stage_id })

      expect(AccountUser.find_by(account: account, user: monta).custom_role.permissions).to include('crm_view')
      expect([dos_dias.first, quem_escolheu, do_funil.first]).to eq([200, nil, 200])
      expect(ajustes.reload).to have_attributes(dias_antes: 45, user_id: monta.id)
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

    it 'o id do card de renovação só vai para quem enxerga o card no quadro' do
      quem = pessoa_com(%w[contact_view crm_view])
      sem_crm = pessoa_com(%w[contact_view])
      ler_o_card = lambda do |pessoa|
        get "#{base}/seguros/#{seguro.id}", headers: pessoa.create_new_auth_token
        response.parsed_body['renovacao'].slice('cardId', 'funil')
      end

      sem_ver = ler_o_card.call(quem)
      card.update!(owner: sem_crm)
      dona_sem_crm = ler_o_card.call(sem_crm)
      card.update!(owner: quem)

      expect([sem_ver, dona_sem_crm]).to all(eq('cardId' => nil, 'funil' => 'Renovação'))
      expect(ler_o_card.call(quem)).to eq('cardId' => card.id, 'funil' => 'Renovação')
      expect(ler_o_card.call(admin)).to eq('cardId' => card.id, 'funil' => 'Renovação')
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
