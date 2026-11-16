require 'rails_helper'

# E7 (#2900) — a busca dos seguros no conector, passo a passo, com o conector de mentira (Mock::CarteiraDaCorretora: duas
# páginas, um registro sem referência, um endosso da mesma apólice, um registro que o adapter não leu e os avisos do
# pedido). Desde a E7.5, a busca traz na hora o que o Agger já tem, sem esperar o robô. Tudo fictício; nenhuma chamada
# paga: o tipo de cada ramo vem de uma pergunta falsa.
RSpec.describe Carteira::Conector::Sincronizar, :aggregate_failures do
  include ActiveJob::TestHelper

  let(:account) { conta_com_carteira }
  let(:admin) { create(:user, account: account, role: :administrator) }

  before do
    enable_test_encryption!
    sem_pergunta_paga_do_ramo
  end

  def conectar!(conta = account)
    conectar_agger!(conta)
  end

  def andar_ate_o_fim(leitura, portal: nil)
    andar_a_busca(leitura, portal: portal)
  end

  describe 'a primeira busca' do
    before { conectar! }

    it 'pede os últimos 36 meses, põe o job na fila só com o id e devolve a mesma busca enquanto ela anda' do
      leitura = nil
      expect { leitura = described_class.primeira(account, user: admin) }.to have_enqueued_job(Carteira::Conector::BuscaJob).with(kind_of(Integer))

      pedido = Carteira::Conector::Pedido.new(leitura)
      hoje = Carteira::Selo.hoje(account)
      expect([pedido.desde, pedido.ate]).to eq([(hoje - 36.months).iso8601, hoje.iso8601])
      expect(leitura).to have_attributes(origem: 'conector', estado: 'lendo', user: admin)
      expect(described_class.primeira(account, user: admin)).to eq(leitura)
      # As factories põem na fila jobs de outros eventos (a conta criada, o agente adicionado): só os do conector contam.
      do_conector = enqueued_jobs.select { |job| job['job_class'].to_s.start_with?('Carteira::Conector::') }
      expect(do_conector).not_to be_empty
      expect(do_conector.pluck('arguments').flatten).to all(be_a(Integer))
    end

    it 'lê as duas páginas e termina no Conferir; a conta fecha: registros + ignorados = total do conector' do
      leitura = andar_ate_o_fim(described_class.primeira(account, user: admin))

      expect(leitura.estado).to eq('lida')
      itens = leitura.itens.where.not(estado: 'pedido')
      expect(itens.where(estado: 'lido').count).to eq(4)
      expect(itens.where(estado: 'falhou').count).to eq(1)
      totais = leitura.totais
      expect(totais.values_at('recebidos', 'repetidos', 'ignorados', 'total')).to eq([5, 0, 1, 6])
      expect(itens.count + totais['repetidos'] + totais['ignorados']).to eq(totais['total'])
      expect(itens.where(estado: 'lido').map { |item| item.campos['tipo'] }).to match_array(%w[auto residencial auto empresarial])
    end

    it 'o registro sem referência não dá para trazer, e os avisos do pedido ficam com nome e situação só' do
      leitura = andar_ate_o_fim(described_class.primeira(account, user: admin))

      expect(leitura.itens.find_by(estado: 'falhou').campos['ref']).to be_nil
      expect(Carteira::Conector::Pedido.new(leitura).por_seguradora).to eq(
        [{ 'nome' => 'Seguradora Sol (exemplo)', 'situacao' => 'pede_login' }, { 'nome' => nil, 'situacao' => 'sem_login' }]
      )
    end

    it 'o Conferir conta como os PDFs, e a conta fecha: entram + não deu + ignorados + repetidos = total' do
      leitura = andar_ate_o_fim(described_class.primeira(account, user: admin))

      conferir = Carteira::Conector::Conferir.new(leitura).call
      expect(conferir).to include(estado: 'lida', seguros: 3, pessoas: 3, pessoasNovas: 3, semTelefone: 3, naoDeuParaTrazer: 2, total: 6,
                                  ignorados: 1, repetidos: 1, jaNaCarteira: 0, porTipo: { 'auto' => 1, 'residencial' => 1, 'empresarial' => 1 },
                                  naoDeuPorque: { semDados: 1, semDocumento: 0, naoLeu: 1 })
      nao_deu = conferir[:naoDeuParaTrazer] - conferir[:ignorados]
      expect(conferir[:seguros] + nao_deu + conferir[:ignorados] + conferir[:repetidos]).to eq(conferir[:total])
      expect(conferir[:porSeguradora].size).to eq(2)
    end

    it 'os números do Conferir são calculados no job: a requisição só lê, sem procurar a pessoa de nenhum registro' do
      leitura = andar_ate_o_fim(described_class.primeira(account, user: admin))
      allow(Carteira::Conector::PessoaDoRegistro).to receive(:new).and_call_original

      expect(Carteira::Conector::Conferir.new(leitura).call).to include(seguros: 3)
      expect { Carteira::Conector::Trazer.new(leitura).call }.to have_enqueued_job(Carteira::Conector::GravarJob).with(leitura.id)
      expect(Carteira::Conector::PessoaDoRegistro).not_to have_received(:new)
      expect(leitura.reload.totais).to include('conferir_prontos' => 4, 'conferir_seguros' => 3)
    end

    it 'buscar de novo uma busca já lida pede o mesmo período e não repete registro' do
      leitura = andar_ate_o_fim(described_class.primeira(account, user: admin))

      expect { described_class.de_novo(leitura) }.to have_enqueued_job(Carteira::Conector::BuscaJob)
      leitura = andar_ate_o_fim(leitura)

      expect(leitura.estado).to eq('lida')
      expect(leitura.itens.where(estado: 'lido').count).to eq(4)
      expect(leitura.itens.where(estado: 'falhou').count).to eq(1)
      expect(leitura.totais.values_at('recebidos', 'repetidos', 'ja_lidos')).to eq([5, 0, 4])
      conferir = Carteira::Conector::Conferir.new(leitura).call
      expect(conferir.values_at(:seguros, :naoDeuParaTrazer, :repetidos, :total)).to eq([3, 2, 1, 6])
    end

    it 'buscar de novo não pergunta outra vez o tipo de ramo nenhum, nem o que o modelo respondeu "outro"' do
      pergunta = instance_double(Carteira::Trazer::PerguntaDoRamo)
      allow(pergunta).to receive(:call) { |ramos| ramos.index_with { |ramo| ramo == 'empresarial' ? 'outro' : 'auto' } }
      allow(Carteira::Trazer::PerguntaDoRamo).to receive(:new).and_return(pergunta)

      leitura = andar_ate_o_fim(described_class.primeira(account, user: admin))
      expect(pergunta).to have_received(:call).once
      described_class.de_novo(leitura)
      andar_ate_o_fim(leitura)
      andar_ate_o_fim(described_class.diaria(account))

      expect(pergunta).to have_received(:call).once
      expect(leitura.reload.itens.where(estado: 'lido').map { |item| item.campos['tipo'] }).to include('outro')
    end

    it 'o ramo que já está na carteira não vai ao modelo, nem quando está lá como outro' do
      pessoa = create(:contact, account: account)
      criar_apolice(pessoa, seguradora: 'Seguradora Exemplo', numero: 'EX-1', tipo: 'auto', ramo_original: 'AUTOMÓVEL',
                            fim_vigencia: Date.new(2027, 1, 1))
      criar_apolice(pessoa, seguradora: 'Seguradora Exemplo', numero: 'EX-2', tipo: 'outro', ramo_original: 'Residencial',
                            fim_vigencia: Date.new(2027, 1, 1))
      pergunta = instance_double(Carteira::Trazer::PerguntaDoRamo)
      allow(pergunta).to receive(:call) { |ramos| ramos.index_with { 'empresarial' } }
      allow(Carteira::Trazer::PerguntaDoRamo).to receive(:new).and_return(pergunta)

      andar_ate_o_fim(described_class.primeira(account, user: admin))

      expect(pergunta).to have_received(:call).once.with(['empresarial'])
    end
  end

  describe 'quando o conector recusa ou cai' do
    before { conectar! }

    # Um portal que deixa o conector de mentira responder, menos na operação escolhida.
    def portal_que_falha(leitura, kind, vezes: 99)
      portal = Carteira::Conector::Portal.new(leitura.account)
      falhas = 0
      allow(portal).to receive(:pedir).and_wrap_original do |original, **args|
        falhas += 1
        raise Autonomia::Insurance::Connector::Error.new(kind, 'falha de exemplo') if falhas <= vezes

        original.call(**args)
      end
      portal
    end

    it 'o login recusado para a busca com o motivo de entrar de novo; o Conferir diz o motivo' do
      leitura = described_class.primeira(account, user: admin)
      andar_ate_o_fim(leitura, portal: portal_que_falha(leitura, :auth_required))

      expect(leitura.reload.estado).to eq('parou')
      expect(Carteira::Conector::Conferir.new(leitura).call).to include(estado: 'parou', motivo: 'agger_pede_login')
      expect(Carteira::Conector.pede_login?(account)).to be(true)
    end

    it 'o Agger fora do ar é tentado de novo, e depois de 3 vezes a busca para com "não deu"' do
      leitura = described_class.primeira(account, user: admin)
      allow(Rails.logger).to receive(:warn)
      andar_ate_o_fim(leitura, portal: portal_que_falha(leitura, :unavailable))

      expect(leitura.reload.estado).to eq('parou')
      expect(Carteira::Conector::Conferir.new(leitura).call[:motivo]).to eq('agger_falhou')
      expect(Rails.logger).to have_received(:warn).with("[carteira][conector] leitura=#{leitura.id} erro=unavailable").exactly(3).times
    end

    it 'uma falha passageira não para a busca, e a busca parada continua pelo "buscar de novo"' do
      leitura = described_class.primeira(account, user: admin)
      allow(Rails.logger).to receive(:warn)
      expect(andar_ate_o_fim(leitura, portal: portal_que_falha(leitura, :timeout, vezes: 1)).estado).to eq('lida')

      outra = create(:carteira_leitura, account: account, origem: 'conector', estado: 'parou', totais: { 'primeira' => 1, 'parou' => 1 })
      Carteira::Conector::Pedido.criar!(outra, desde: Date.new(2026, 1, 1), ate: Date.new(2026, 2, 1))
      described_class.de_novo(outra)
      expect(outra.reload).to have_attributes(estado: 'lendo')
      expect(outra.totais.keys).to eq(['primeira'])
    end

    it 'a sessão recusada é renovada UMA vez por operação, nunca em laço' do
      leitura = described_class.primeira(account, user: admin)
      connector = Autonomia::Insurance::Connector::Mock.new
      allow(connector).to receive(:portfolio_sync_start).and_raise(Autonomia::Insurance::Connector::Error.new(:auth_required, 'sessão'))
      allow(connector).to receive(:open_session).and_call_original

      described_class.new(leitura, portal: Carteira::Conector::Portal.new(account, connector: connector)).passo

      expect(connector).to have_received(:portfolio_sync_start).twice
      expect(connector).to have_received(:open_session).once
      expect(leitura.reload.estado).to eq('parou')
    end
  end

  # E7.5 — a prova real: o robô do Agger não buscou nas seguradoras, e os seguros que o Agger já tinha não vinham. Agora
  # a busca lê a lista logo depois do pedido, sem perguntar pelo robô.
  describe 'traz na hora o que o Agger já tem, sem esperar o robô' do
    before { conectar! }

    def registro(ref, seguradora, documento)
      { 'ref' => ref, 'numero' => "N-#{ref}", 'seguradora' => seguradora, 'ramo' => 'Automóvel', 'inicio_vigencia' => '2026-03-10',
        'fim_vigencia' => '2027-03-10', 'emissao' => '2026-03-01', 'premio_centavos' => 150_000,
        'segurado' => { 'nome' => "Pessoa #{ref}", 'documento' => documento, 'email' => nil }, 'item' => nil, 'endosso' => nil,
        'parcelas' => nil, 'pdf_ref' => nil }
    end

    # O pedido volta como `pedido` manda, e a lista do Agger tem 3 registros: duas linhas iguais (a mesma apólice, sem
    # endosso) e uma de outra seguradora. O andamento não pode ser perguntado.
    def portal_sem_robo(leitura, pedido: { 'sync_id' => 'exemplo-1', 'status' => 'buscando' })
      portal = Carteira::Conector::Portal.new(leitura.account)
      allow(portal).to receive(:pedir).and_return(pedido)
      allow(portal).to receive(:andamento)
      itens = [registro('agora-ref-1', 'Seguradora Azul (exemplo)', '10020030088'),
               registro('agora-ref-1', 'Seguradora Azul (exemplo)', '10020030088'),
               registro('agora-ref-2', 'Seguradora Verde (exemplo)', '40050060007')]
      allow(portal).to receive(:apolices).and_return('itens' => itens, 'proximo_cursor' => nil, 'total' => 3, 'ignorados' => 0)
      portal
    end

    it 'lê a lista logo depois do pedido: os 3 registros chegam ao Conferir, a linha repetida conta uma vez, e a conta fecha' do
      inicio = described_class.primeira(account, user: admin)
      portal = portal_sem_robo(inicio)

      expect(described_class.new(inicio, portal: portal).passo).to eq(2.seconds)
      expect(described_class.new(inicio.reload, portal: portal).passo).to be_nil
      leitura = inicio.reload

      expect(portal).not_to have_received(:andamento)
      expect(leitura.estado).to eq('lida')
      expect(leitura.itens.where(estado: 'lido').count).to eq(2)
      expect(leitura.totais.values_at('recebidos', 'repetidos', 'ignorados', 'total')).to eq([3, 1, 0, 3])
      conferir = Carteira::Conector::Conferir.new(leitura).call
      expect(conferir).to include(seguros: 2, pessoas: 2, naoDeuParaTrazer: 0, ignorados: 0, repetidos: 1, total: 3, porSeguradora: [])
      entram = conferir[:seguros]
      nao_deu = conferir[:naoDeuParaTrazer] - conferir[:ignorados]
      expect(entram + nao_deu + conferir[:ignorados] + conferir[:repetidos]).to eq(conferir[:total])
    end

    it 'a de todo dia também: os seguros que já estavam no Agger vão para a gravação, sem perguntar pelo robô' do
      inicio = described_class.diaria(account)
      portal = portal_sem_robo(inicio)
      leitura = andar_ate_o_fim(inicio, portal: portal)

      expect(portal).not_to have_received(:andamento)
      expect(leitura.estado).to eq('trazendo')
      expect(leitura.totais['para_trazer']).to eq(2)
    end

    # E7.6 — a prova real: o Conferir prometia o seguro com as datas invertidas, e o gravador o recusava. Agora o Conferir
    # diz por que não deu, e os motivos fecham com o total do que não deu.
    it 'o Conferir abre o que não deu pelo motivo: falta dado do seguro, falta o CPF/CNPJ, o conector não leu' do
      inicio = described_class.primeira(account, user: admin)
      portal = Carteira::Conector::Portal.new(inicio.account)
      allow(portal).to receive(:pedir).and_return({ 'sync_id' => 'exemplo-3', 'status' => 'buscando' })
      allow(portal).to receive(:andamento)
      itens = [registro('porque-ref-1', 'Seguradora Azul (exemplo)', '10020030088'),
               registro('porque-ref-2', 'Seguradora Verde (exemplo)', '40050060007').merge('inicio_vigencia' => '2027-03-11'),
               registro('porque-ref-3', 'Seguradora Azul (exemplo)', nil)]
      allow(portal).to receive(:apolices).and_return('itens' => itens, 'proximo_cursor' => nil, 'total' => 4, 'ignorados' => 1)
      leitura = andar_ate_o_fim(inicio, portal: portal)

      conferir = Carteira::Conector::Conferir.new(leitura).call
      expect(conferir).to include(estado: 'lida', seguros: 1, naoDeuParaTrazer: 3, ignorados: 1, total: 4,
                                  naoDeuPorque: { semDados: 1, semDocumento: 1, naoLeu: 1 })
      expect(conferir[:naoDeuPorque].values.sum).to eq(conferir[:naoDeuParaTrazer])
      expect(Carteira::Conector::Conferir.new(leitura).prontos).to eq(1)
    end

    it 'a busca calculada antes dos motivos não traz o campo: a tela não mostra motivo nenhum' do
      inicio = described_class.primeira(account, user: admin)
      leitura = andar_ate_o_fim(inicio, portal: portal_sem_robo(inicio))
      leitura.update!(totais: leitura.totais.except('conferir_sem_dados', 'conferir_sem_documento'))

      conferir = Carteira::Conector::Conferir.new(leitura).call
      expect(conferir).to include(seguros: 2, naoDeuParaTrazer: 0)
      expect(conferir).not_to have_key(:naoDeuPorque)
    end

    it 'só a evidência vira aviso: a situação sem problema, a desconhecida e o pedido sem o campo não avisam nada' do
      pedido = { 'sync_id' => 'exemplo-2', 'status' => 'falhou',
                 'por_seguradora' => [{ 'codigo' => '1', 'nome' => 'Seguradora Lua (exemplo)', 'situacao' => 'sem_login' },
                                      { 'codigo' => '2', 'nome' => 'Seguradora Mar (exemplo)', 'situacao' => 'pronta' },
                                      { 'codigo' => '3', 'nome' => 'Seguradora Rio (exemplo)', 'situacao' => 'outra' }, 'fora do formato'] }
      com_aviso = described_class.primeira(account, user: admin)
      andar_ate_o_fim(com_aviso, portal: portal_sem_robo(com_aviso, pedido: pedido))
      expect(Carteira::Conector::Conferir.new(com_aviso.reload).call[:porSeguradora])
        .to eq([{ nome: 'Seguradora Lua (exemplo)', situacao: 'sem_login' }])

      sem_campo = described_class.diaria(account)
      andar_ate_o_fim(sem_campo, portal: portal_sem_robo(sem_campo))
      expect(Carteira::Conector::Conferir.new(sem_campo.reload).call[:porSeguradora]).to eq([])
    end
  end

  # E7.5 — a busca pedida antes desta regra (o pedido ainda `buscando`) segue perguntando pelo robô, mas com prazo: nada
  # fica preso esperando por ele.
  describe 'a busca pedida antes, que ainda espera o robô' do
    before { conectar! }

    def pedido_de_antes!(leitura)
      item = leitura.itens.find_by!(estado: 'pedido')
      item.update!(campos: item.campos.merge('sync_id' => "mock-carteira:#{Time.current.to_i}", 'status' => 'buscando',
                                             'pagina' => 0, 'desde_posicao' => 1))
    end

    def portal_com_robo(leitura, *status)
      portal = Carteira::Conector::Portal.new(leitura.account)
      allow(portal).to receive(:andamento).and_return(*status.map { |um| { 'status' => um, 'por_seguradora' => [] } })
      portal
    end

    it 'pergunta o andamento enquanto o robô busca e lê a lista quando ele termina; o andamento não vira aviso' do
      leitura = described_class.primeira(account, user: admin)
      pedido_de_antes!(leitura)
      portal = Carteira::Conector::Portal.new(account)
      allow(portal).to receive(:andamento).and_return({ 'status' => 'buscando', 'por_seguradora' => [] },
                                                      { 'status' => 'pronta', 'por_seguradora' => [{ 'nome' => nil, 'situacao' => 'sem_login' }] })

      expect(described_class.new(leitura, portal: portal).passo).to eq(1.minute)
      expect(described_class.new(leitura.reload, portal: portal).passo).to eq(0.seconds)
      leitura = andar_ate_o_fim(leitura, portal: portal)

      expect(portal).to have_received(:andamento).twice
      expect(leitura.estado).to eq('lida')
      expect(leitura.itens.where(estado: 'lido').count).to eq(4)
      expect(Carteira::Conector::Conferir.new(leitura).call[:porSeguradora]).to eq([])
    end

    it 'com o robô pendente depois do prazo (2 horas do começo da busca), para de perguntar, lê a lista e termina' do
      leitura = described_class.primeira(account, user: admin)
      pedido_de_antes!(leitura)
      portal = portal_com_robo(leitura, 'buscando')

      expect(described_class.new(leitura, portal: portal).passo).to eq(1.minute)
      travel(described_class::PRAZO_DO_ROBO + 1.minute)
      leitura = andar_ate_o_fim(leitura, portal: portal)

      expect(portal).to have_received(:andamento).once
      expect(leitura.estado).to eq('lida')
      expect(leitura.itens.where(estado: 'lido').count).to eq(4)
    end

    it 'cada pergunta ao robô conta como andamento: a busca não parece parada' do
      leitura = described_class.primeira(account, user: admin)
      pedido_de_antes!(leitura)
      portal = portal_com_robo(leitura, 'buscando')
      travel(5.minutes)

      expect { described_class.new(leitura.reload, portal: portal).passo }.to(change { leitura.reload.updated_at })
    end

    it 'a busca de antes já lida: o aviso guardado pelo andamento antigo não aparece, e buscar de novo pede do jeito novo' do
      leitura = described_class.primeira(account, user: admin)
      pedido_de_antes!(leitura)
      item = leitura.itens.find_by!(estado: 'pedido')
      item.update!(campos: item.campos.merge('status' => 'pronta', 'por_seguradora' => [{ 'nome' => nil, 'situacao' => 'sem_login' }]))
      leitura.update!(estado: 'lida')
      expect(Carteira::Conector::Conferir.new(leitura).call[:porSeguradora]).to eq([])

      described_class.de_novo(leitura)
      pedido = Carteira::Conector::Pedido.new(leitura.reload)
      expect([pedido.sync_id, pedido.status]).to eq([nil, nil])
      expect(andar_ate_o_fim(leitura).estado).to eq('lida')
    end
  end

  describe 'a busca de todo dia' do
    before { conectar! }

    it 'pede os últimos 30 dias e, no fim, vai sozinha para a gravação' do
      leitura = described_class.diaria(account)
      pedido = Carteira::Conector::Pedido.new(leitura)
      expect(Date.iso8601(pedido.ate) - Date.iso8601(pedido.desde)).to eq(30)

      expect { andar_ate_o_fim(leitura) }.to have_enqueued_job(Carteira::Conector::GravarJob).with(leitura.id)
      expect(leitura.reload).to have_attributes(estado: 'trazendo', user: nil)
      expect(leitura.totais['para_trazer']).to eq(4)
    end

    # Os 30 dias se sobrepõem de um dia para o outro de propósito (o que o robô trouxer depois entra): o mesmo registro
    # visto de novo não vira outro seguro nem outra pessoa.
    it 'a de amanhã vê os mesmos registros nos 30 dias, e não duplica seguro nem pessoa' do
      # No meio do mês: as datas do conector de mentira só mudam na virada dele.
      travel_to(Time.current.beginning_of_month + 9.days + 12.hours)
      gravar_a_busca(andar_ate_o_fim(described_class.diaria(account)))
      expect(Carteira::Apolice.where(account_id: account.id).count).to eq(3)
      travel(1.day)

      expect { gravar_a_busca(andar_ate_o_fim(described_class.diaria(account))) }
        .not_to(change { [Carteira::Apolice.where(account_id: account.id).count, account.contacts.count] })
      expect(Carteira::Leitura.do_conector.where(account_id: account.id).count).to eq(2)
    end

    it 'a rotina só busca nas contas com o interruptor ligado e o login aceito' do
      outra = conta_com_carteira
      conectar!(outra)
      Carteira::Conector::BuscaDiaria.new(account).mudar!(true)
      Carteira::Conector::BuscaDiaria.new(outra).mudar!(false)

      expect { Carteira::Conector::BuscaDiariaJob.perform_now }.to have_enqueued_job(Carteira::Conector::BuscaDiariaJob).exactly(:once)
      expect { perform_enqueued_jobs(only: Carteira::Conector::BuscaDiariaJob) }.to have_enqueued_job(Carteira::Conector::BuscaJob).exactly(:once)
      expect(Carteira::Leitura.do_conector.pluck(:account_id)).to eq([account.id])
    end

    it 'a rotina espaça as contas: um job por conta, só com o id, 20 segundos uma depois da outra' do
      outra = conta_com_carteira
      conectar!(outra)
      [account, outra].each { |conta| Carteira::Conector::BuscaDiaria.new(conta).mudar!(true) }

      freeze_time do
        expect { Carteira::Conector::BuscaDiariaJob.perform_now }
          .to have_enqueued_job(Carteira::Conector::BuscaDiariaJob).with(account.id).at(Time.current)
          .and have_enqueued_job(Carteira::Conector::BuscaDiariaJob).with(outra.id).at(20.seconds.from_now)
      end
    end

    it 'a primeira nunca devolve uma de todo dia, e a de todo dia retoma a que parou há mais de 10 minutos' do
      diaria = described_class.diaria(account)
      primeira = described_class.primeira(account, user: admin)
      expect(primeira).not_to eq(diaria)
      expect(primeira.totais).to have_key('primeira')
      expect(described_class.diaria(account)).to eq(diaria)
      expect { described_class.diaria(account) }.not_to have_enqueued_job(Carteira::Conector::BuscaJob)

      travel(11.minutes)
      expect { expect(described_class.diaria(account)).to eq(diaria) }.to have_enqueued_job(Carteira::Conector::BuscaJob).with(diaria.id)
    end

    it 'o login recusado: a rotina não busca, e o resumo diz que o Agger pediu para entrar de novo' do
      Carteira::Conector::BuscaDiaria.new(account).mudar!(true)
      Carteira::Conector.conexao(account).update!(status: 'auth_required')
      allow(Rails.logger).to receive(:info)

      expect { Carteira::Conector::BuscaDiariaJob.perform_now(account.id) }.not_to have_enqueued_job(Carteira::Conector::BuscaJob)
      expect(Rails.logger).to have_received(:info).with("[carteira][conector][diaria] account=#{account.id} pede_login")
      expect(Carteira::Resumo.new(account).call).to include(aggerLigado: false, aggerPedeLogin: true)
    end
  end

  it 'sem o login do Agger, recusa agger_desligado' do
    expect { described_class.primeira(account, user: admin) }.to raise_error(CustomExceptions::CarteiraRecusa) { |erro|
      expect(erro.codigo).to eq('agger_desligado')
    }
  end
end
