require 'rails_helper'

# Painel de desempenho no servidor (#2251), com uma loja inventada. O teste-ouro (painel_ouro_spec) compara com o
# protótipo aprovado; aqui ficam as regras que precisam valer em qualquer conta.
RSpec.describe Autonomia::Desempenho::Painel do
  let(:account) { create(:account) }
  let(:robo) { create(:agent_bot, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox) }
  let(:outra_conversa) { create(:conversation, account: account, inbox: inbox) }
  let(:painel) { described_class.new(account: account, sujeito_type: 'robo', sujeito_id: robo.id) }
  let(:fuso) { ActiveSupport::TimeZone['America/Sao_Paulo'] }

  def mensagem(conversa, tipo, quando, remetente: nil, privada: false)
    create(:message, conversation: conversa, account: account, inbox: inbox, message_type: tipo, private: privada,
                     sender: remetente, created_at: fuso.parse(quando))
  end

  before do
    ficha_da_loja!(account, sujeito_id: robo.id)
    procura_da_loja!(conversa, sujeito_id: robo.id, inicio: '2026-10-20 10:00', marcos: %w[orcamento_enviado pagou], resultado_id: 'comprou')
    procura_da_loja!(conversa, sujeito_id: robo.id, inicio: '2026-10-21 20:00', ordem: 2, pedido_id: 'duvida', tema_id: 'troca',
                               resultado_id: 'duvida_resolvida', precisava_pessoa: true, teve_pessoa: false)
    procura_da_loja!(outra_conversa, sujeito_id: robo.id, inicio: '2026-10-22 11:00', marcos: ['orcamento_enviado'],
                                     motivo_ids: ['sem_estoque'], perda_evitavel: true, regra_ids: ['R-PRAZO'], qualidade_id: 'erro_grave')
    leitura_da_loja!(conversa, sujeito_id: robo.id, ate: '2026-10-22 18:00')
    leitura_da_loja!(outra_conversa, sujeito_id: robo.id, ate: '2026-10-22 18:30')
  end

  it 'devolve nil quando o agente ainda não tem ficha' do
    expect(described_class.new(account: account, sujeito_type: 'robo', sujeito_id: robo.id + 1).call('30')).to be_nil
  end

  it 'monta o contrato v2 do período a partir das procuras, com o número da caixa como conversa' do
    resultado = painel.call('7')

    expect { Autonomia::Desempenho::Exportacao::Contrato.validar!(resultado) }.not_to raise_error
    expect(resultado['meta']).to include('fonte' => 'api', 'dados_ate' => '2026-10-22T18:30',
                                         'periodo' => include('chave' => '7', 'inicio' => '2026-10-20', 'fim' => '2026-10-22'))
    kpis = resultado['kpis'].to_h { |kpi| [kpi['id'], kpi['valor']] }
    expect(kpis).to include('procuras' => 3, 'conversas' => 2, 'compra' => 2, 'fecharam' => 1, 'duvidas_resolvidas' => 1,
                            'sem_pessoa' => 1, 'perdas_evitaveis' => 1)
    expect(resultado['funil']['etapas'].pluck('procuras')).to eq([2, 2, 1])
    expect(resultado['procuras'].pluck('conversa')).to eq([conversa.display_id, conversa.display_id, outra_conversa.display_id])
    expect(resultado['perdas']['lista'].first).to include('conversa' => outra_conversa.display_id, 'motivo_ids' => ['sem_estoque'])
    expect(resultado['qualidade']['regras'].first).to include('id' => 'R-PRAZO', 'procuras' => 1, 'pct' => 33.3)
  end

  it 'conta as mensagens e o tempo de resposta ao vivo, e a resposta da equipe zera a espera' do
    agente = robo
    equipe = create(:user, account: account)
    mensagem(conversa, :incoming, '2026-10-20 10:00:00')
    mensagem(conversa, :outgoing, '2026-10-20 10:00:30', remetente: agente)
    mensagem(conversa, :incoming, '2026-10-20 11:00:00')
    mensagem(conversa, :outgoing, '2026-10-20 11:05:00', remetente: equipe)
    mensagem(conversa, :outgoing, '2026-10-20 11:06:00', remetente: agente)
    mensagem(conversa, :outgoing, '2026-10-20 11:07:00', remetente: equipe, privada: true)

    resultado = painel.call('7')

    expect(resultado['meta']['base']['mensagens']).to eq('contato' => 2, 'agente' => 2, 'equipe' => 1, 'notas' => 1)
    expect(resultado['qualidade']['tempo_resposta']).to include('medidas' => 1, 'mediana_seg' => 30, 'acima_5_min' => 0)
    expect(resultado['kpis'].find { |kpi| kpi['id'] == 'tempo_resposta' }['valor']).to eq(30)
  end

  it 'usa a sugestão guardada só quando ela é do mesmo período e da mesma ficha' do
    base = { account: account, sujeito_type: 'robo', sujeito_id: robo.id, versao_ficha: 1, lote: 'spec', gerada_em: Time.current }
    Autonomia::Desempenho::Recomendacao.create!(base.merge(periodo: '7', inicio: Date.new(2026, 10, 20), fim: Date.new(2026, 10, 22),
                                                           cartoes: [{ 'id' => 'r1', 'titulo' => 'Dizer o prazo' }]))
    Autonomia::Desempenho::Recomendacao.create!(base.merge(periodo: '30', inicio: Date.new(2026, 9, 1), fim: Date.new(2026, 9, 30),
                                                           cartoes: [{ 'id' => 'r1' }]))

    expect(painel.call('7')['recomendacoes']).to eq([{ 'id' => 'r1', 'titulo' => 'Dizer o prazo' }])
    expect(painel.call('30')['recomendacoes']).to eq([])
    expect(painel.call('30')['meta']['recomendacoes_de']).to be_nil
  end

  it 'com leitura automática, a sugestão de outras datas do mesmo período vai com as datas dela (#2301)' do
    base = { account: account, sujeito_type: 'robo', sujeito_id: robo.id, versao_ficha: 1, lote: 'spec', gerada_em: Time.current }
    Autonomia::Desempenho::Recomendacao.create!(base.merge(periodo: '30', inicio: Date.new(2026, 9, 1), fim: Date.new(2026, 9, 30),
                                                           cartoes: [{ 'id' => 'r1' }]))
    Autonomia::Desempenho::Rodada.create!(account: account, sujeito_type: 'robo', sujeito_id: robo.id, corte_em: Time.current,
                                          piso_em: 1.day.ago, iniciada_em: Time.current, status: 'ok', lote: 'spec')
    Autonomia::Desempenho::Ficha.do_sujeito(account, 'robo', robo.id).update_all(chave_de_leitura: 'Leia.') # rubocop:disable Rails/SkipsModelValidations

    with_modified_env(AUTONOMIA_DESEMPENHO_LEITURA_AUTOMATICA: 'true') do
      expect(painel.call('30')['recomendacoes']).to eq([{ 'id' => 'r1' }])
      expect(painel.call('30')['meta']['recomendacoes_de']).to eq('inicio' => '2026-09-01', 'fim' => '2026-09-30')
      Autonomia::Desempenho::Recomendacao.find_by(periodo: '30').update!(versao_ficha: 2)
      expect(painel.call('30')['recomendacoes']).to eq([])
    end
  end

  it 'conta só as conversas que a pessoa vê, procuras e mensagens, sem sugestões da conta inteira' do
    Autonomia::Desempenho::Recomendacao.create!(account: account, sujeito_type: 'robo', sujeito_id: robo.id, periodo: '7',
                                                inicio: Date.new(2026, 10, 20), fim: Date.new(2026, 10, 22), versao_ficha: 1,
                                                cartoes: [{ 'id' => 'r1' }], gerada_em: Time.current, lote: 'spec')
    mensagem(conversa, :incoming, '2026-10-20 10:00:00')
    mensagem(outra_conversa, :incoming, '2026-10-22 11:00:00')
    visiveis = Conversation.where(id: conversa.id)

    resultado = described_class.new(account: account, sujeito_type: 'robo', sujeito_id: robo.id, visiveis: visiveis).call('7')

    expect(resultado['procuras'].pluck('conversa')).to eq([conversa.display_id, conversa.display_id])
    expect(resultado['meta']['base']['procuras']).to eq(2)
    expect(resultado['perdas']['lista']).to be_empty
    expect(resultado['meta']['base']['mensagens']).to include('contato' => 1)
    expect(resultado['recomendacoes']).to eq([])
    expect(resultado['meta']['periodo']).to include('inicio' => '2026-10-20', 'fim' => '2026-10-22')
    expect(resultado['meta']['visibilidade']).to include('escopo' => 'caixas', 'ocultas' => 1)
  end

  it 'devolve o painel vazio quando a pessoa não vê nenhuma das conversas lidas' do
    resultado = described_class.new(account: account, sujeito_type: 'robo', sujeito_id: robo.id, visiveis: Conversation.none).call('7')

    expect(resultado).to include('vazio' => true, 'meta' => include('situacao' => 'sem_conversas'))
    expect(resultado.dig('meta', 'visibilidade', 'ocultas')).to eq(3)
  end

  it 'tira o dinheiro de quem não vê valor de venda e mantém as contagens' do
    Autonomia::Desempenho::Ficha.last.update!(referencias: { 'ticket' => { 'com_valor' => 3, 'mediano' => 90.0, 'moeda' => 'BRL' },
                                                             'confianca' => nil, 'exemplos' => {} })

    resultado = described_class.new(account: account, sujeito_type: 'robo', sujeito_id: robo.id, ve_valores: false).call('7')

    expect(resultado['ticket']).to be_nil
    expect(resultado['kpis'].find { |kpi| kpi['id'] == 'procuras' }['valor']).to eq(3)
  end

  it 'não mistura a leitura de outra conta' do
    outra_conta = create(:account)
    ficha_da_loja!(outra_conta, sujeito_id: robo.id)
    estranha = create(:conversation, account: outra_conta)
    procura_da_loja!(estranha, sujeito_id: robo.id, inicio: '2026-10-22 09:00')

    expect(painel.call('7')['meta']['base']['procuras']).to eq(3)
  end

  it 'usa a ficha de maior versão' do
    ficha_da_loja!(account, sujeito_id: robo.id, versao: 2).update!(catalogo: AutonomiaDesempenhoHelpers::CATALOGO_DA_LOJA.merge(
      'temas' => { 'entrega' => 'Entrega', 'troca' => 'Troca' }
    ))

    expect(painel.call('7')['catalogo']['temas']['entrega']).to eq('Entrega')
  end

  it 'lê do banco só o período e o anterior, e conta conversa nova pela primeira procura do histórico' do
    antiga = procura_da_loja!(outra_conversa, sujeito_id: robo.id, inicio: '2026-09-01 10:00', ordem: 9)

    resultado = painel.call('7')

    expect(resultado['procuras'].pluck('procura')).not_to include(antiga.ordem)
    expect(resultado['evolucao']['pontos'].sum { |ponto| ponto['conversas_novas'] }).to eq(1)
  end

  it 'mostra só as procuras mais recentes acima do teto da lista e diz quantas são' do
    stub_const("#{described_class}::LIMITE_DA_LISTA", 2)

    resultado = painel.call('7')

    expect(resultado['procuras'].size).to eq(2)
    expect(resultado['meta']['lista']).to eq('total' => 3, 'mostradas' => 2)
    expect(resultado['meta']['base']['procuras']).to eq(3)
  end

  it 'conta a equipe por mês no histórico, fora da janela do período' do
    equipe = create(:user, account: account)
    mensagem(conversa, :outgoing, '2026-08-10 10:00:00', remetente: equipe)
    mensagem(conversa, :outgoing, '2026-10-20 10:00:00', remetente: equipe)

    expect(painel.call('7')['pessoa']['equipe_por_mes']).to include({ 'mes' => '2026-08', 'n' => 1 }, { 'mes' => '2026-10', 'n' => 1 })
  end

  describe '.fuso_de' do
    let(:ficha) { Autonomia::Desempenho::Ficha.vigente(account, 'robo', robo.id) }

    it 'usa o fuso da conta, o da ficha como reserva e nunca um nome inválido' do
      expect(described_class.fuso_de(account, ficha)).to eq('America/Sao_Paulo')
      account.update!(reporting_timezone: 'Europe/Lisbon')
      expect(described_class.fuso_de(account.reload, ficha)).to eq('Europe/Lisbon')
      account.update!(reporting_timezone: nil)
      ficha.configuracao['meta']['fuso'] = 'Lugar/Nenhum'
      expect(described_class.fuso_de(account.reload, ficha)).to eq(ActiveSupport::TimeZone[Crm::Timezone::Resolver.default_timezone].tzinfo.name)
    end
  end

  describe '.intervalo' do
    it 'corta no começo dos dados e só traz o período anterior quando ele cabe inteiro' do
      inicio_dos_dados = Date.new(2026, 10, 1)
      fim = Date.new(2026, 10, 26)

      expect(described_class.intervalo('7', fim, inicio_dos_dados))
        .to eq([Date.new(2026, 10, 20), fim, [Date.new(2026, 10, 13), Date.new(2026, 10, 19)]])
      expect(described_class.intervalo('30', fim, inicio_dos_dados)).to eq([inicio_dos_dados, fim, nil])
      expect(described_class.intervalo('tudo', fim, inicio_dos_dados)).to eq([inicio_dos_dados, fim, nil])
    end
  end
end
