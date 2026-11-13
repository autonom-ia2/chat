require 'rails_helper'

# E5 (#2898) — a renovação na aba Seguros e na gaveta: o seguro com o card de renovação, o grupo "Em renovação", o
# filtro "quem cuida", o resumo, e "Renovou", "Não renovou" e "Desfazer", que fecham e reabrem o CARD (quem escreve no
# seguro é o ouvinte do card, o mesmo caminho do quadro). A recusa é um código em `error`. A metade de função
# personalizada fica em spec/enterprise/requests/relacionamentos/seguros_renovacao_spec.rb. Tudo fictício.
RSpec.describe 'Carteira de seguros: renovação de um seguro', type: :request do
  # Meio-dia em São Paulo: para a conta, hoje é 12/11/2026.
  let(:agora) { Time.utc(2026, 11, 12, 15) }
  let(:hoje) { Date.new(2026, 11, 12) }
  let(:account) { conta_com_carteira(reporting_timezone: 'America/Sao_Paulo', locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Bia Exemplo') }
  let(:base) { "/api/v1/accounts/#{account.id}/relacionamentos" }
  let(:ajustes) { escolher_funil_de_renovacao(account, user: admin) }
  let(:marina) { create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000023', contact_type: :customer) }
  let(:seguro) { criar_apolice(marina, numero: 'EX-000001', fim_vigencia: hoje + 5) }
  let(:card) { por_em_renovacao(seguro, ajustes) }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before do
    travel_to(agora)
    card
  end

  def cabecalhos(quem)
    quem.create_new_auth_token
  end

  def ler(caminho, quem: admin, **params)
    get "#{base}/#{caminho}", params: params, headers: cabecalhos(quem)
    response.parsed_body
  end

  def acao(nome, quem: admin, id: seguro.id, **dados)
    post "#{base}/seguros/#{id}/#{nome}", params: dados, headers: cabecalhos(quem), as: :json
  end

  def recusa
    [response.status, response.parsed_body]
  end

  def passos(apolice = seguro)
    apolice.eventos.order(:id).pluck(:tipo)
  end

  def no_quadro(resultado, o_card: card)
    Crm::Cards::Closer.new(card: o_card.reload, actor: admin, result: resultado).perform
  end

  describe 'o seguro em renovação, nas leituras' do
    it 'traz o card de renovação: o funil, a etapa, quem cuida e nenhum desfecho' do
      card.update!(owner: admin)

      expect(ler("seguros/#{seguro.id}")).to include(
        'selo' => 'em_renovacao', 'renovadoEm' => nil, 'motivo' => nil, 'motivoEscrito' => nil, 'apoliceNova' => false,
        'renovacao' => { 'cardId' => card.id, 'funil' => 'Renovação', 'etapa' => 'Novo Lead', 'desfecho' => nil, 'cuida' => 'Bia Exemplo',
                         'cuidaId' => admin.id }
      )
    end

    it 'quem não enxerga o card no quadro lê a renovação sem o id do card' do
      agente = create(:user, account: account, role: :agent)

      do_agente = ler("seguros/#{seguro.id}", quem: agente)['renovacao']
      da_lista = ler('seguros', quem: agente)['itens'].sole['renovacao']

      expect(do_agente).to eq('cardId' => nil, 'funil' => 'Renovação', 'etapa' => 'Novo Lead', 'desfecho' => nil, 'cuida' => nil,
                              'cuidaId' => nil)
      expect(da_lista).to eq(do_agente)
      expect(ler('seguros')['itens'].sole['renovacao']).to include('cardId' => card.id)
    end

    it 'o card sem dono vem sem "quem cuida", e o card tirado do quadro some do seguro' do
      sem_dono = ler("seguros/#{seguro.id}")['renovacao']
      Crm::Cards::Archiver.new(card: card, actor: admin).perform

      expect(sem_dono).to include('cuida' => nil, 'cuidaId' => nil)
      expect(ler("seguros/#{seguro.id}")).to include('selo' => 'ativo', 'renovacao' => nil)
    end

    it 'o grupo "Em renovação", as contagens e o resumo contam só quem tem a renovação aberta e ainda vale' do
      fora = {
        'EX-SEM-CARD' => {}, 'EX-RENOVADO' => { renovado_em: agora }, 'EX-NAO-RENOVOU' => { nao_renovou_em: agora },
        'EX-TIRADO' => { renovacao_card_removido_em: agora }, 'EX-CANCELADO' => { cancelado_em: agora }, 'EX-VENCIDO' => { fim_vigencia: hoje - 1 }
      }
      fora.each do |numero, campos|
        apolice = criar_apolice(marina, numero: numero, fim_vigencia: hoje + 20)
        por_em_renovacao(apolice, ajustes) unless numero == 'EX-SEM-CARD'
        apolice.update!(campos)
      end
      longe = criar_apolice(marina, numero: 'EX-LONGE', fim_vigencia: hoje + 40)
      por_em_renovacao(longe, ajustes)

      expect(ler('seguros', grupo: 'em_renovacao')['itens'].pluck('numero', 'selo')).to eq([%w[EX-000001 em_renovacao], %w[EX-LONGE em_renovacao]])
      expect(ler('seguros/contagens')).to include('todos' => 8, 'em_renovacao' => 2, 'vencido' => 1, 'vence_7_dias' => 1)
      expect(ler('seguros/resumo')).to eq('total' => 8, 'vence7' => 1, 'vence7EmRenovacao' => 1, 'emRenovacao' => 2,
                                          'funilEscolhido' => true, 'aggerLigado' => false)
    end

    it 'o renovado sai dos grupos de vencimento e não vira vencido depois do fim' do
      no_quadro('won')
      travel 10.days

      expect(ler('seguros/contagens')).to include('todos' => 1, 'vence_7_dias' => 0, 'vence_90_dias' => 0, 'em_renovacao' => 0, 'vencido' => 0)
      expect(ler("seguros/#{seguro.id}")).to include('selo' => 'renovado', 'dias' => -5)
    end

    it 'filtra por quem cuida, pelo id do dono do card, e oferece no filtro só quem cuida de alguma renovação' do
      caio = create(:user, account: account, role: :agent, name: 'Caio Exemplo')
      create(:user, account: account, role: :agent, name: 'Sem Card Exemplo')
      card.update!(owner: admin)
      do_caio = criar_apolice(marina, numero: 'EX-000002', fim_vigencia: hoje + 20)
      por_em_renovacao(do_caio, ajustes).update!(owner: caio)
      criar_apolice(marina, numero: 'EX-000003', fim_vigencia: hoje + 20)

      expect(ler('seguros', filtros: { cuida: caio.id })['itens'].pluck('numero')).to eq(['EX-000002'])
      expect(ler('seguros/contagens', filtros: { cuida: admin.id })).to include('todos' => 1, 'em_renovacao' => 1)
      expect(ler('seguros/opcoes_de_filtro')['cuida']).to eq([{ 'id' => admin.id, 'nome' => 'Bia Exemplo' },
                                                              { 'id' => caio.id, 'nome' => 'Caio Exemplo' }])
    end

    it 'a lista não faz uma consulta a mais por seguro em renovação' do
      criar = lambda do |n|
        apolice = criar_apolice(marina, numero: "EX-0001#{n}", fim_vigencia: hoje + 20 + n)
        por_em_renovacao(apolice, ajustes).update!(owner: admin)
      end
      2.times(&criar)
      do_admin = cabecalhos(admin)
      pedir = -> { get "#{base}/seguros", headers: do_admin }
      pedir.call
      com_tres = consultas_da_carteira(&pedir)
      4.times { |n| criar.call(n + 2) }

      expect(consultas_da_carteira(&pedir)).to eq(com_tres)
      expect(response.parsed_body['itens'].size).to eq(7)
    end
  end

  describe 'Renovou' do
    it 'fecha o card como ganho e devolve o seguro renovado, com o passo na história' do
      acao('renovou')

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('selo' => 'renovado', 'renovadoEm' => agora.to_i)
      expect(response.parsed_body['renovacao']).to include('cardId' => card.id, 'desfecho' => 'renovou')
      expect(card.reload.status).to eq('won')
      expect(card.activities.order(:id).last).to have_attributes(event_type: 'won', actor_type: 'user', actor_id: admin.id)
      expect(ler("seguros/#{seguro.id}/historia").pluck('tipo', 'quem'))
        .to eq([['renovou', { 'id' => admin.id, 'nome' => 'Bia Exemplo' }], ['card_nasceu', nil]])
    end

    it 'pedir de novo não muda nada' do
      acao('renovou')
      travel 1.hour
      acao('renovou')

      expect(response).to have_http_status(:ok)
      expect([response.parsed_body['renovadoEm'], passos]).to eq([agora.to_i, %w[card_nasceu renovou]])
    end

    it 'dá no seguro o mesmo resultado de fechar o card no quadro' do
      outro = criar_apolice(marina, numero: 'EX-000002', fim_vigencia: hoje + 5)
      card_do_outro = por_em_renovacao(outro, ajustes)
      campos = %w[renovado_em nao_renovou_em motivo_nao_renovou motivo_escrito renovacao_card_removido_em]

      acao('renovou')
      no_quadro('won', o_card: card_do_outro)

      expect(seguro.reload.slice(*campos)).to eq(outro.reload.slice(*campos))
      expect(passos).to eq(passos(outro))
      expect([card.reload.status, card_do_outro.reload.status]).to eq(%w[won won])
    end
  end

  describe 'Não renovou' do
    it 'fecha o card como perdido e guarda o motivo no seguro e na história' do
      acao('nao_renovou', motivo: 'achou_caro')

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('selo' => 'ativo', 'renovadoEm' => nil, 'motivo' => 'achou_caro', 'motivoEscrito' => nil)
      expect(response.parsed_body['renovacao']).to include('desfecho' => 'nao_renovou')
      expect(card.reload.status).to eq('lost')
      expect(seguro.eventos.order(:id).last).to have_attributes(tipo: 'nao_renovou', user_id: admin.id, valores: { 'motivo' => 'achou_caro' })
    end

    it 'o motivo "outro" leva o que a pessoa escreveu, sem os espaços das pontas' do
      acao('nao_renovou', motivo: 'outro', texto: '  Mudou de cidade  ')

      expect(response.parsed_body).to include('motivo' => 'outro', 'motivoEscrito' => 'Mudou de cidade')
      expect(seguro.eventos.order(:id).last).to have_attributes(tipo: 'nao_renovou_outro', valores: { 'texto' => 'Mudou de cidade' })
    end

    it 'sem motivo fecha como o quadro fecha, e o motivo pode ser dito depois' do
      acao('nao_renovou')
      sem_motivo = response.parsed_body.slice('motivo', 'renovacao')
      travel 1.hour
      acao('nao_renovou', motivo: 'nao_respondeu')

      expect(sem_motivo).to include('motivo' => nil, 'renovacao' => include('desfecho' => 'nao_renovou'))
      expect(response.parsed_body).to include('motivo' => 'nao_respondeu')
      expect(seguro.reload.nao_renovou_em).to eq(agora)
      expect(passos).to eq(%w[card_nasceu nao_renovou])
      expect(seguro.eventos.order(:id).last.valores).to eq('motivo' => 'nao_respondeu')
    end

    it 'o card perdido no quadro, sem motivo, ganha o motivo pela gaveta, sem fechar de novo' do
      no_quadro('lost')
      atividades = card.activities.count

      acao('nao_renovou', motivo: 'vendeu_o_bem')

      expect(response.parsed_body).to include('motivo' => 'vendeu_o_bem')
      expect(card.activities.count).to eq(atividades)
    end

    it 'trocar o motivo troca também o passo da história' do
      acao('nao_renovou', motivo: 'outro', texto: 'Mudou de cidade')
      acao('nao_renovou', motivo: 'outra_corretora')

      expect(response.parsed_body).to include('motivo' => 'outra_corretora', 'motivoEscrito' => nil)
      expect(seguro.eventos.order(:id).last).to have_attributes(tipo: 'nao_renovou', valores: { 'motivo' => 'outra_corretora' })
    end

    it 'recusa motivo fora da lista, "outro" sem texto e texto longo demais, sem repetir o que veio e sem fechar o card' do
      pedidos = { { motivo: 'talvez' } => 'motivo_desconhecido', { motivo: 'outro' } => 'falta_texto',
                  { motivo: 'outro', texto: '   ' } => 'falta_texto', { motivo: 'outro', texto: 'a' * 501 } => 'texto_longo',
                  { motivo: 'achou_caro', nota: 'x' } => 'pedido_invalido', { motivo: ['achou_caro'] } => 'pedido_invalido' }

      respostas = pedidos.keys.map do |dados|
        acao('nao_renovou', **dados)
        recusa
      end

      expect(respostas).to eq(pedidos.values.map { |codigo| [422, { 'error' => codigo }] })
      expect([card.reload.status, passos]).to eq(['open', ['card_nasceu']])
    end
  end

  describe 'Desfazer' do
    it 'reabre o card, e o seguro volta a estar em renovação, sem desfecho nem motivo' do
      acao('nao_renovou', motivo: 'achou_caro')
      acao('desfazer_desfecho')

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('selo' => 'em_renovacao', 'renovadoEm' => nil, 'motivo' => nil)
      expect(response.parsed_body['renovacao']).to include('desfecho' => nil)
      expect(card.reload.status).to eq('open')
      expect(seguro.reload.nao_renovou_em).to be_nil
    end

    it 'a história guarda quem desfez e qual era o desfecho' do
      acao('renovou')
      travel 1.hour
      acao('desfazer_desfecho')

      historia = ler("seguros/#{seguro.id}/historia")
      expect(historia.pluck('tipo')).to eq(%w[desfez_desfecho renovou card_nasceu])
      expect(historia.first).to include('quando' => (agora + 1.hour).to_i, 'quem' => { 'id' => admin.id, 'nome' => 'Bia Exemplo' },
                                        'valores' => { 'anterior' => 'renovou' })
    end

    it 'depois de desfazer o "renovou", dá para dizer "não renovou"' do
      acao('renovou')
      acao('desfazer_desfecho')
      acao('nao_renovou', motivo: 'achou_caro')

      expect(response.parsed_body).to include('renovadoEm' => nil, 'motivo' => 'achou_caro')
      expect(card.reload.status).to eq('lost')
    end
  end

  # Card de seguro cancelado não fica aberto para sempre: cancelar fecha a renovação como perdida, com o motivo
  # "cancelou". Voltar a ativo não reabre.
  describe 'cancelar o seguro com a renovação aberta' do
    it 'fecha o card como perdido, com o motivo "cancelou", e a história guarda os dois passos com quem cancelou' do
      acao('cancelar')

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('selo' => 'cancelado', 'motivo' => 'cancelou', 'motivoEscrito' => nil, 'renovadoEm' => nil)
      expect(response.parsed_body['renovacao']).to include('desfecho' => 'nao_renovou')
      expect([card.reload.status, seguro.reload.nao_renovou_em, passos]).to eq(['lost', agora, %w[card_nasceu cancelado nao_renovou]])
      expect(seguro.eventos.order(:id).last).to have_attributes(user_id: admin.id, valores: { 'motivo' => 'cancelou' })
      expect(card.activities.order(:id).last).to have_attributes(event_type: 'lost', actor_type: 'user', actor_id: admin.id)
    end

    it 'voltar a ativo não reabre o card, e o cancelado não desfaz o desfecho pela gaveta' do
      acao('cancelar')
      acao('desfazer_desfecho')
      desfazendo_cancelado = recusa
      acao('voltar_a_ativo')

      expect(desfazendo_cancelado).to eq([422, { 'error' => 'ja_cancelado' }])
      expect(response.parsed_body).to include('selo' => 'ativo', 'motivo' => 'cancelou')
      expect([card.reload.status, seguro.reload.nao_renovou_em]).to eq(['lost', agora])
    end

    it 'depois de voltar a ativo, desfazer o desfecho põe o seguro em renovação de novo' do
      acao('cancelar')
      acao('voltar_a_ativo')
      acao('desfazer_desfecho')

      expect(response.parsed_body).to include('selo' => 'em_renovacao', 'motivo' => nil)
      expect(card.reload.status).to eq('open')
    end

    it 'não mexe no card que já tem desfecho nem no que foi tirado do quadro' do
      no_quadro('won')
      tirado = criar_apolice(marina, numero: 'EX-000002', fim_vigencia: hoje + 5)
      card_tirado = por_em_renovacao(tirado, ajustes)
      Crm::Cards::Archiver.new(card: card_tirado, actor: admin).perform

      acao('cancelar')
      acao('cancelar', id: tirado.id)

      expect([card.reload.status, seguro.reload.renovado_em, passos]).to eq(['won', agora, %w[card_nasceu renovou cancelado]])
      expect([card_tirado.reload.status, tirado.reload.nao_renovou_em, passos(tirado)]).to eq(['archived', nil, %w[card_nasceu cancelado]])
    end
  end

  describe 'recusas' do
    it 'não troca um desfecho pelo outro sem desfazer antes, e não desfaz o que não tem desfecho' do
      acao('desfazer_desfecho')
      sem_desfecho = recusa
      acao('renovou')
      acao('nao_renovou', motivo: 'achou_caro')
      depois_de_renovar = recusa
      acao('desfazer_desfecho')
      acao('nao_renovou')
      acao('renovou')

      expect([sem_desfecho, depois_de_renovar, recusa]).to eq(
        [[422, { 'error' => 'sem_desfecho' }], [422, { 'error' => 'ja_tem_desfecho' }], [422, { 'error' => 'ja_tem_desfecho' }]]
      )
    end

    it 'o seguro sem card de renovação, ou com o card tirado do quadro, responde sem_renovacao' do
      sem_card = criar_apolice(marina, numero: 'EX-000002', fim_vigencia: hoje + 20)
      Crm::Cards::Archiver.new(card: card, actor: admin).perform

      respostas = [sem_card.id, seguro.id].product(%w[renovou nao_renovou]).map do |id, nome|
        acao(nome, id: id)
        recusa
      end

      expect(respostas).to all(eq([422, { 'error' => 'sem_renovacao' }]))
      expect([sem_card.reload.renovado_em, sem_card.eventos.count, card.reload.status]).to eq([nil, 0, 'archived'])
    end

    it 'recusa corpo que a ação não conhece' do
      %w[renovou desfazer_desfecho].each do |nome|
        acao(nome, motivo: 'achou_caro')

        expect(recusa).to eq([422, { 'error' => 'pedido_invalido' }]), nome
      end
      expect(card.reload.status).to eq('open')
    end
  end

  describe 'em toda rota' do
    let(:acoes) { %w[renovou nao_renovou desfazer_desfecho] }

    it 'responde 401 sem login' do
      respostas = acoes.map do |nome|
        post "#{base}/seguros/#{seguro.id}/#{nome}", as: :json
        response.status
      end

      expect(respostas).to eq([401, 401, 401])
      expect(card.reload.status).to eq('open')
    end

    it 'responde 404 sem a carteira' do
      account.disable_features!('carteira_seguros')

      respostas = acoes.map do |nome|
        acao(nome)
        response.status
      end

      expect(respostas).to eq([404, 404, 404])
      expect(card.reload.status).to eq('open')
    end

    it 'o seguro de outra conta responde 404, e nada muda nele nem no card dele' do
      outra = conta_com_carteira
      dona = create(:user, account: outra, role: :administrator)

      respostas = acoes.map do |nome|
        post "/api/v1/accounts/#{outra.id}/relacionamentos/seguros/#{seguro.id}/#{nome}", headers: cabecalhos(dona), as: :json
        response.status
      end

      expect(respostas).to eq([404, 404, 404])
      expect([card.reload.status, passos]).to eq(['open', ['card_nasceu']])
    end
  end
end
