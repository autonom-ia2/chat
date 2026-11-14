require 'rails_helper'

# E5 (#2898) — a parte da renovação da carteira que depende do Enterprise: o que a função personalizada muda. Ler pede
# ver contatos; guardar os ajustes pede editar contatos e a chave de funis, uma das duas (montar os funis, que já traz
# a de ver o CRM, ou administrar o CRM); dizer como a renovação terminou pede editar contatos e poder mexer naquele card
# no quadro; o card de renovação (id, funil, etapa, dono) só vai para quem o enxerga; o recorte por quem cuida só vai
# para quem vê os relatórios; o aviso no sino vai a quem vê contatos e o CRM. Tudo fictício.
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

    # Guardar muda uma escolha da conta inteira e diz em que funil o CRM recebe os cards: pede editar contatos E a chave
    # de funis, que é uma das duas (montar os funis ou administrar o CRM, como na Automação: RegraDoFunil.chave?).
    {
      'nenhuma das duas' => [%w[contact_view crm_view], false],
      'só a de editar contatos' => [%w[contact_manage crm_view], false],
      'só a de montar os funis' => [%w[contact_view crm_view crm_manage_pipelines], false],
      'as duas' => [%w[contact_manage crm_view crm_manage_pipelines], true],
      'a de editar contatos e a de administrar o CRM' => [%w[contact_manage crm_admin], true],
      'só a de administrar o CRM' => [%w[contact_view crm_admin], false]
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

    it 'sem a chave de contatos não lê nem guarda, nem administrando o CRM' do
      respostas = [%w[conversation_manage crm_view], %w[crm_admin]].map do |chaves|
        sem_contatos = pessoa_com(chaves)
        ler_ajustes(sem_contatos)
        [response.status, guardar_ajustes(sem_contatos, { dias: 30 }).first]
      end

      expect([respostas, ajustes.reload.dias_antes]).to eq([[[401, 401], [401, 401]], 60])
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

    it 'o card de renovação (id, funil, etapa e dono) só vai para quem o enxerga no quadro; os outros leem só o desfecho' do
      quem = pessoa_com(%w[contact_view crm_view])
      sem_crm = pessoa_com(%w[contact_view])
      ler_o_card = lambda do |pessoa|
        get "#{base}/seguros/#{seguro.id}", headers: pessoa.create_new_auth_token
        response.parsed_body['renovacao']
      end

      sem_ver = ler_o_card.call(quem)
      card.update!(owner: sem_crm)
      dona_sem_crm = ler_o_card.call(sem_crm)
      card.update!(owner: quem)

      inteiro = { 'cardId' => card.id, 'funil' => 'Renovação', 'etapa' => 'Novo Lead', 'desfecho' => nil, 'cuida' => quem.name,
                  'cuidaId' => quem.id }
      expect([sem_ver, dona_sem_crm]).to all(eq('desfecho' => nil))
      expect([ler_o_card.call(quem), ler_o_card.call(admin)]).to all(eq(inteiro))
    end

    it 'quem cuida, no filtro e nas opções, só conta os cards que quem pede enxerga' do
      quem = pessoa_com(%w[contact_view crm_view])
      card.update!(owner: admin)
      ler_quem_cuida = lambda do |dono|
        get "#{base}/seguros/opcoes_de_filtro", headers: quem.create_new_auth_token
        opcoes = response.parsed_body['cuida'].pluck('id')
        get "#{base}/seguros", params: { filtros: { cuida: dono.id } }, headers: quem.create_new_auth_token
        [opcoes, response.parsed_body['total']]
      end

      sem_ver = ler_quem_cuida.call(admin)
      card.update!(owner: quem)

      expect([sem_ver, ler_quem_cuida.call(quem)]).to eq([[[], 0], [[quem.id], 1]])
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

  describe 'os resultados das renovações' do
    it 'o recorte por quem cuida só vai para quem vê os relatórios; os outros nem recebem a chave' do
      recortes_de = lambda do |chaves|
        get "#{base}/seguros/resultados", headers: pessoa_com(chaves).create_new_auth_token
        [response.status, response.parsed_body['periodos'].map { |periodo| periodo['recortes'].keys }.uniq]
      end

      expect(recortes_de.call(%w[contact_view])).to eq([200, [%w[tipo seguradora]]])
      expect(recortes_de.call(%w[contact_view crm_view crm_manage_cards])).to eq([200, [%w[tipo seguradora]]])
      expect(recortes_de.call(%w[contact_view report_manage])).to eq([200, [%w[tipo seguradora cuida]]])
    end
  end

  describe 'quem cuida do card que nasce' do
    def card_do_proximo(numero)
      proximo = criar_apolice(marina, numero: numero, fim_vigencia: hoje + 6)
      Carteira::Renovacao::DaContaJob.perform_now(account.id)
      proximo.reload.crm_card
    end

    it 'quem escolheu o funil e perdeu o CRM na função não vira dona: o card nasce sem dono' do
      com_crm = pessoa_com(%w[contact_manage crm_view crm_manage_pipelines])
      ajustes.update!(user: com_crm)
      dela = card_do_proximo('EX-000002')
      AccountUser.find_by(account: account, user: com_crm).custom_role.update!(permissions: %w[contact_manage])

      sem_dono = card_do_proximo('EX-000003')

      expect([dela.owner_id, sem_dono.owner_id]).to eq([com_crm.id, nil])
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
