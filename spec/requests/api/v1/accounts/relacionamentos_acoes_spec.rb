require 'rails_helper'

# #2894 — as ações em grupo da Lista nova de Relacionamentos: os funis com as etapas (numa chamada só), criar cards,
# etiquetar e apagar. A regra de cada ação, pessoa por pessoa, está em spec/services/relacionamentos.
RSpec.describe 'Ações em grupo da Lista de Relacionamentos', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/relacionamentos" }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:outra_conta) { create(:account) }
  let(:escritas) { %w[cards etiqueta apagar] }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before { account.enable_features!('relacionamentos_novo') }

  def pessoa(nome, conta: account, **dados)
    create(:contact, account: conta, name: nome, **dados)
  end

  def pedir(caminho, quem: agente, **corpo)
    post "#{base}/#{caminho}", params: corpo, headers: quem.create_new_auth_token, as: :json
  end

  def nao_existe_mais(pessoa_id)
    { 'id' => pessoa_id, 'nome' => nil, 'motivo' => 'nao_existe_mais' }
  end

  def ler_funis(quem: agente)
    get "#{base}/funis", headers: quem.create_new_auth_token
  end

  def card_de(contato, funil: vendas, **dados)
    account.crm_cards.create!(pipeline: funil.first, stage: funil.last, contact: contato, title: 'Pedido', **dados)
  end

  def consultas_feitas(&)
    feitas = 0
    contar = ->(*, dados) { feitas += 1 unless dados[:cached] || %w[SCHEMA TRANSACTION].include?(dados[:name]) }
    ActiveSupport::Notifications.subscribed(contar, 'sql.active_record', &)
    feitas
  end

  it 'responde 401 sem login' do
    get "#{base}/funis"
    expect(response).to have_http_status(:unauthorized)

    escritas.each do |caminho|
      post "#{base}/#{caminho}", params: { pessoa_ids: [1] }, as: :json

      expect(response).to have_http_status(:unauthorized), caminho
    end
  end

  it 'responde 404 com a chave da conta desligada' do
    account.disable_features!('relacionamentos_novo')

    ler_funis(quem: admin)
    expect(response).to have_http_status(:not_found)

    escritas.each do |caminho|
      pedir(caminho, quem: admin, pessoa_ids: [pessoa('Ana Albuquerino').id])

      expect(response).to have_http_status(:not_found), caminho
    end
    expect(account.contacts.count).to eq(3)
  end

  it 'não atende quem é de outra conta' do
    de_fora = create(:user, account: outra_conta, role: :administrator)
    ana = pessoa('Ana Albuquerino')

    ler_funis(quem: de_fora)
    expect(response).to have_http_status(:unauthorized)

    escritas.each do |caminho|
      pedir(caminho, quem: de_fora, pessoa_ids: [ana.id], funil_id: vendas.first.id, etapa_id: vendas.last.id, etiqueta: 'feira')

      expect(response).to have_http_status(:unauthorized), caminho
    end
    expect([account.contacts.exists?(ana.id), account.crm_cards.count, ana.reload.label_list]).to eq([true, 0, []])
  end

  # O permit do Rails descarta em silêncio o que não conhece: sem a conferência, um pedido torto seguiria pela metade.
  it 'responde 422 ao parâmetro que a ação não conhece ou que chega em formato errado, sem fazer nada' do
    ana = pessoa('Ana Albuquerino')
    create(:label, account: account, title: 'feira')
    destino = { funil_id: vendas.first.id, etapa_id: vendas.last.id }
    tortos = [
      ['cards', { pessoa_ids: [ana.id], **destino, dono_id: admin.id }, 'parâmetro desconhecido: dono_id'],
      ['cards', { pessoa_ids: ana.id, **destino }, 'pessoa_ids em formato inválido'],
      ['cards', { pessoa_ids: ['abc'], **destino }, 'pessoa_ids em formato inválido'],
      ['cards', { pessoa_ids: [ana.id], funil_id: [vendas.first.id], etapa_id: vendas.last.id }, 'funil_id em formato inválido'],
      ['cards', { pessoa_ids: [], **destino }, 'escolha pelo menos uma pessoa'],
      ['etiqueta', { pessoa_ids: [ana.id], etiqueta: 'feira', etiquetas: ['site'] }, 'parâmetro desconhecido: etiquetas'],
      ['etiqueta', { pessoa_ids: [ana.id], etiqueta: ['feira'] }, 'etiqueta em formato inválido'],
      ['etiqueta', { etiqueta: 'feira' }, 'escolha pelo menos uma pessoa'],
      ['apagar', { pessoa_ids: [ana.id], todas: true }, 'parâmetro desconhecido: todas'],
      ['apagar', { pessoa_ids: { id: ana.id } }, 'pessoa_ids em formato inválido'],
      ['apagar', {}, 'escolha pelo menos uma pessoa']
    ]

    tortos.each do |caminho, corpo, mensagem|
      pedir(caminho, quem: admin, **corpo)

      expect(response).to have_http_status(:unprocessable_entity), "#{caminho} #{corpo}"
      expect(response.parsed_body).to eq('error' => mensagem)
    end
    expect([account.contacts.exists?(ana.id), account.crm_cards.count, ana.reload.label_list]).to eq([true, 0, []])
  end

  describe 'GET funis' do
    it 'devolve os funis ativos com as etapas, na ordem do quadro' do
      funil, primeira = vendas
      fechando = create_crm_stage(account: account, pipeline: funil, name: 'Fechando', position: 2)
      combinando = create_crm_stage(account: account, pipeline: funil, name: 'Combinando', position: 1)
      depois, boas_vindas = create_crm_pipeline(account: account, user: admin, name: 'Depois da compra')
      create_crm_pipeline(account: account, user: admin, name: 'Antigo').first.update!(status: :archived)
      create_crm_pipeline(account: outra_conta, user: create(:user, account: outra_conta), name: 'De outra conta')

      ler_funis

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        [
          { 'id' => funil.id, 'nome' => 'Vendas',
            'etapas' => [{ 'id' => primeira.id, 'nome' => 'Novo Lead' }, { 'id' => combinando.id, 'nome' => 'Combinando' },
                         { 'id' => fechando.id, 'nome' => 'Fechando' }] },
          { 'id' => depois.id, 'nome' => 'Depois da compra', 'etapas' => [{ 'id' => boas_vindas.id, 'nome' => 'Novo Lead' }] }
        ]
      )
    end

    it 'não consulta mais por ter mais funis' do
      vendas
      ler_funis
      com_um = consultas_feitas { ler_funis }
      3.times { |n| create_crm_pipeline(account: account, user: admin, name: "Funil #{n}") }

      com_quatro = consultas_feitas { ler_funis }

      expect(response.parsed_body.size).to eq(4)
      expect(com_quatro).to eq(com_um)
    end

    it 'devolve lista vazia com o CRM desligado, para a tela dizer que não há funil' do
      vendas

      with_modified_env(CRM_KANBAN_ENABLED: 'false') { ler_funis }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([])
    end
  end

  describe 'POST cards' do
    let(:destino) { { funil_id: vendas.first.id, etapa_id: vendas.last.id } }

    it 'cria um card aberto por pessoa, na etapa escolhida e com quem pediu de dono' do
      ana = pessoa('Ana Albuquerino')
      bruno = pessoa('Bruno Brandolim')

      pedir('cards', pessoa_ids: [ana.id, bruno.id], **destino)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('criados' => 2, 'de_fora' => [])
      expect(account.crm_cards.order(:id).map { |card| card.slice(:title, :contact_id, :pipeline_id, :stage_id, :owner_id, :status).values })
        .to eq([['Ana Albuquerino', ana.id, vendas.first.id, vendas.last.id, agente.id, 'open'],
                ['Bruno Brandolim', bruno.id, vendas.first.id, vendas.last.id, agente.id, 'open']])
    end

    it 'aceita os ids como texto, como chegam de um formulário' do
      ana = pessoa('Ana Albuquerino')

      post "#{base}/cards", params: { pessoa_ids: [ana.id.to_s], funil_id: vendas.first.id.to_s, etapa_id: vendas.last.id.to_s },
                            headers: agente.create_new_auth_token

      expect(response.parsed_body).to eq('criados' => 1, 'de_fora' => [])
    end

    it 'deixa de fora só quem já tem card aberto naquele funil, com o motivo que a tela conhece' do
      outro_funil = create_crm_pipeline(account: account, user: admin, name: 'Depois da compra')
      fechado = Crm::Cards::Outcome.status_for(vendas.first, 'lost')
      ana = pessoa('Ana Albuquerino').tap { |contato| card_de(contato) }
      bruno = pessoa('Bruno Brandolim').tap { |contato| card_de(contato, status: fechado) }
      carla = pessoa('Carla Carvalhedo').tap { |contato| card_de(contato, status: :archived) }
      diego = pessoa('Diego Dornelaz').tap { |contato| card_de(contato, funil: outro_funil) }

      pedir('cards', pessoa_ids: [ana.id, bruno.id, carla.id, diego.id], **destino)

      expect(response.parsed_body).to eq('criados' => 3, 'de_fora' => [{ 'id' => ana.id, 'nome' => 'Ana Albuquerino', 'motivo' => 'ja_tem_card' }])
      abertos = account.crm_cards.where(pipeline_id: vendas.first.id, status: :open)
      expect(abertos.group(:contact_id).count).to eq(ana.id => 1, bruno.id => 1, carla.id => 1, diego.id => 1)
    end

    it 'cria um card só para a pessoa que veio repetida no pedido' do
      ana = pessoa('Ana Albuquerino')

      pedir('cards', pessoa_ids: [ana.id, ana.id], **destino)

      expect(response.parsed_body).to eq('criados' => 1, 'de_fora' => [])
      expect(account.crm_cards.where(contact_id: ana.id).count).to eq(1)
    end

    it 'responde 422 e não cria nada com funil ou etapa que não é da conta, sem dizer de quem é' do
      ana = pessoa('Ana Albuquerino')
      outro_funil = create_crm_pipeline(account: account, user: admin, name: 'Depois da compra')
      arquivado = create_crm_pipeline(account: account, user: admin, name: 'Antigo').tap { |funil, _| funil.update!(status: :archived) }
      de_la = create_crm_pipeline(account: outra_conta, user: create(:user, account: outra_conta), name: 'De outra conta')
      recusados = [
        [{ pessoa_ids: [ana.id], funil_id: vendas.first.id, etapa_id: outro_funil.last.id }, 'etapa não é deste funil'],
        [{ pessoa_ids: [ana.id], funil_id: vendas.first.id, etapa_id: de_la.last.id }, 'etapa não é deste funil'],
        [{ pessoa_ids: [ana.id], funil_id: vendas.first.id, etapa_id: 0 }, 'etapa não é deste funil'],
        [{ pessoa_ids: [ana.id], funil_id: de_la.first.id, etapa_id: de_la.last.id }, 'funil desconhecido'],
        [{ pessoa_ids: [ana.id], funil_id: arquivado.first.id, etapa_id: arquivado.last.id }, 'funil desconhecido'],
        [{ pessoa_ids: [ana.id], funil_id: 0, etapa_id: vendas.last.id }, 'funil desconhecido'],
        [{ pessoa_ids: [ana.id], etapa_id: vendas.last.id }, 'funil desconhecido']
      ]

      recusados.each do |corpo, mensagem|
        pedir('cards', **corpo)

        expect(response).to have_http_status(:unprocessable_entity), corpo.to_s
        expect(response.parsed_body).to eq('error' => mensagem)
      end
      expect(Crm::Card.count).to eq(0)
    end

    it 'responde 422 com o CRM desligado' do
      ana = pessoa('Ana Albuquerino')

      with_modified_env(CRM_KANBAN_ENABLED: 'false') { pedir('cards', pessoa_ids: [ana.id], **destino) }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'o CRM está desligado')
      expect(Crm::Card.count).to eq(0)
    end
  end

  describe 'POST etiqueta' do
    before { create(:label, account: account, title: 'feira') }

    it 'aplica a etiqueta em cada pessoa, sem tirar as que ela já tinha' do
      ana = pessoa('Ana Albuquerino').tap { |contato| contato.update_labels(%w[site]) }
      bruno = pessoa('Bruno Brandolim')
      carla = pessoa('Carla Carvalhedo')

      pedir('etiqueta', pessoa_ids: [ana.id, bruno.id], etiqueta: 'feira')

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('aplicadas' => 2, 'de_fora' => [])
      expect([ana, bruno, carla].map { |contato| contato.reload.label_list.sort }).to eq([%w[feira site], %w[feira], []])
    end

    it 'responde 422 e não etiqueta ninguém com etiqueta que a conta não tem' do
      create(:label, account: outra_conta, title: 'evento')
      ana = pessoa('Ana Albuquerino')
      pessoa_de_la = pessoa('Elisa Esteviano', conta: outra_conta)
      recusados = [
        [{ pessoa_ids: [ana.id], etiqueta: 'evento' }, 'etiqueta desconhecida'],
        [{ pessoa_ids: [ana.id], etiqueta: '' }, 'etiqueta desconhecida'],
        [{ pessoa_ids: [ana.id] }, 'etiqueta desconhecida']
      ]

      recusados.each do |corpo, mensagem|
        pedir('etiqueta', **corpo)

        expect(response).to have_http_status(:unprocessable_entity), corpo.to_s
        expect(response.parsed_body).to eq('error' => mensagem)
      end
      expect([ana, pessoa_de_la].map { |contato| contato.reload.label_list }).to eq([[], []])
    end
  end

  # Quem some no meio do caminho (apagada por outra pessoa da equipe) ou nunca foi da conta não derruba o lote: fica de
  # fora como "não existe mais", igual nos dois casos e sem nome, e as outras seguem. Assim repetir o pedido não trava.
  describe 'pessoa que não é da conta ou não existe mais' do
    let(:ana) { pessoa('Ana Albuquerino') }
    let(:pessoa_de_la) { pessoa('Elisa Esteviano', conta: outra_conta) }
    let(:destino) { { funil_id: vendas.first.id, etapa_id: vendas.last.id } }
    let(:ids) { [ana.id, pessoa_de_la.id, 0] }
    let(:de_fora) { [nao_existe_mais(pessoa_de_la.id), nao_existe_mais(0)] }

    it 'cria o card só de quem é da conta' do
      pedir('cards', quem: admin, pessoa_ids: ids, **destino)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('criados' => 1, 'de_fora' => de_fora)
      expect(Crm::Card.pluck(:contact_id)).to eq([ana.id])
    end

    it 'etiqueta só quem é da conta' do
      create(:label, account: account, title: 'feira')

      pedir('etiqueta', quem: admin, pessoa_ids: ids, etiqueta: 'feira')

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('aplicadas' => 1, 'de_fora' => de_fora)
      expect(pessoa_de_la.reload.label_list).to be_empty
    end

    it 'com ninguém da conta no pedido, não faz nada e diz quem ficou de fora' do
      pedir('apagar', quem: admin, pessoa_ids: [pessoa_de_la.id])

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('apagadas' => 0, 'de_fora' => [nao_existe_mais(pessoa_de_la.id)])
      expect(Contact.exists?(pessoa_de_la.id)).to be(true)
    end
  end

  describe 'POST apagar' do
    def auditorias(acao)
      Audited.audit_class.where(auditable: account, action: acao)
    end

    it 'apaga as pessoas e conta quantas saíram' do
      ana = pessoa('Ana Albuquerino')
      bruno = pessoa('Bruno Brandolim')
      carla = pessoa('Carla Carvalhedo')

      pedir('apagar', quem: admin, pessoa_ids: [ana.id, bruno.id])

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('apagadas' => 2, 'de_fora' => [])
      expect(account.contacts.pluck(:id)).to eq([carla.id])
    end

    it 'não deixa o agente comum apagar, como a lista de contatos de hoje' do
      ana = pessoa('Ana Albuquerino')

      pedir('apagar', quem: agente, pessoa_ids: [ana.id])

      expect(response).to have_http_status(:unauthorized)
      expect(account.contacts.exists?(ana.id)).to be(true)
    end

    it 'não apaga a pessoa de outra conta: ela fica de fora, sem nome, e a daqui sai' do
      ana = pessoa('Ana Albuquerino')
      pessoa_de_la = pessoa('Elisa Esteviano', conta: outra_conta)

      pedir('apagar', quem: admin, pessoa_ids: [ana.id, pessoa_de_la.id])

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('apagadas' => 1, 'de_fora' => [nao_existe_mais(pessoa_de_la.id)])
      expect(Contact.where(id: [ana.id, pessoa_de_la.id]).pluck(:id)).to eq([pessoa_de_la.id])
    end

    # LGPD (#2096): o que a exclusão em lote de hoje protege continua valendo, porque é ela que roda.
    context 'with the crm_arquivados flag' do
      before { account.enable_features!(:crm_arquivados) }

      def reuniao_do_google(card)
        caixa = create(:channel_email, account: account, calendar_enabled: true).inbox
        account.crm_meetings.new(card: card, inbox: caixa, created_by: admin, title: 'Visita', provider: :google, status: :scheduled,
                                 external_event_id: "evt-#{SecureRandom.hex(4)}", timezone: 'America/Sao_Paulo',
                                 starts_at: 2.days.from_now, ends_at: 2.days.from_now + 30.minutes).tap { |m| m.save!(validate: false) }
      end

      def o_google_nao_cancela
        servico = instance_double(Google::CalendarEventService)
        allow(servico).to receive(:delete_event).and_raise(RuntimeError, 'A refresh_token is not available')
        allow(Google::CalendarEventService).to receive(:new).and_return(servico)
        allow(Crm::Config).to receive(:calendar_google_simulate?).and_return(false)
      end

      it 'deixa o card sem dado pessoal e registra na Auditoria quem apagou' do
        ana = pessoa('Ana Albuquerino')
        card = card_de(ana)

        pedir('apagar', quem: admin, pessoa_ids: [ana.id])

        expect(response.parsed_body).to eq('apagadas' => 1, 'de_fora' => [])
        expect([account.contacts.exists?(ana.id), card.reload.contact_id, card.title]).to eq([false, nil, "Removed customer ##{card.id}"])
        expect(auditorias(Crm::ExclusaoDefinitiva::ACAO).sole.user).to eq(admin)
      end

      it 'deixa de fora, inteira e com o motivo, quem a exclusão de hoje não deixa sair; as outras saem' do
        ana = pessoa('Ana Albuquerino')
        card = card_de(ana)
        reuniao = reuniao_do_google(card)
        bruno = pessoa('Bruno Brandolim')
        o_google_nao_cancela

        pedir('apagar', quem: admin, pessoa_ids: [ana.id, bruno.id])

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq('apagadas' => 1, 'de_fora' => [{ 'id' => ana.id, 'nome' => 'Ana Albuquerino', 'motivo' => 'nao_apagada' }])
        expect([account.contacts.exists?(ana.id), account.contacts.exists?(bruno.id), reuniao.reload.status, card.reload.title])
          .to eq([true, false, 'scheduled', 'Pedido'])
        expect(auditorias(Crm::ExclusaoDefinitiva::FALHOU).sole.audited_changes)
          .to include('motivo' => 'meeting_cancel_failed', 'contact_id' => ana.id)
      end
    end
  end
end
