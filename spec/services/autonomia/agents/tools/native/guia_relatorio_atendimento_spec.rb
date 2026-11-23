require 'rails_helper'

# A ferramenta `relatorio_de_atendimento` (#3158, B8a): os números da tela Relatórios para o Guia.
#
# O critério é o do aceite: o número que o Guia diz é o número que a tela mostra. Por isso cada pergunta-padrão
# compara a saída da ferramenta com o builder v2 chamado direto, com os mesmos parâmetros que a tela manda.
RSpec.describe Autonomia::Agents::Tools::Native::GuiaRelatorioAtendimento do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }
  let(:atendente) { create(:user, account: conta, name: 'Ana Souza') }
  let(:outra) { create(:user, account: conta, name: 'Bruno Lima') }
  let(:caixa) { create(:inbox, account: conta, name: 'WhatsApp') }
  let(:contexto) { Autonomia::Guide::Contexto.new(account: conta, user: admin) }
  let(:semana) { { 'de' => '2026-09-07', 'ate' => '2026-09-13' } }

  def chamar(params, quem: contexto)
    described_class.new(agent: nil, operador: quem, params: params).call
  end

  def relatorio(params, quem: contexto)
    JSON.parse(chamar(params, quem: quem))
  end

  # Os parâmetros que a tela Relatórios manda aos builders para a mesma semana, no fuso da conta.
  def params_da_tela(primeiro: '2026-09-07', ultimo: '2026-09-13')
    fuso = Filters::DateFilterHelper.fuso_da_conta(conta).tzinfo.name
    { since: Date.iso8601(primeiro).in_time_zone(fuso), until: Date.iso8601(ultimo).next_day.in_time_zone(fuso), business_hours: false,
      timezone: fuso, timezone_offset: ActiveSupport::TimeZone[fuso].now.utc_offset / 3600.0 }
  end

  def conversa(quando, **atributos)
    create(:conversation, account: conta, inbox: caixa, created_at: Time.zone.parse(quando), **atributos)
  end

  def resolvida(conversa, por:, quando:)
    create(:reporting_event, account: conta, inbox: caixa, conversation: conversa, user: por, name: 'conversation_resolved',
                             value: 3_600, created_at: Time.zone.parse(quando))
  end

  it 'está entre as ferramentas do Guia, e só nelas', :aggregate_failures do
    expect(Autonomia::Guide::Seed::FERRAMENTAS).to include('relatorio_de_atendimento')
    expect(Autonomia::Agents::Tools::Registry::DO_GUIA).to include(described_class)
    expect(Autonomia::Agents::Tools::Registry::DE_ATENDIMENTO).not_to include(described_class)
    expect(described_class.escreve?).to be(false)
  end

  it 'registra no diagnóstico só tipo, métrica, por e período' do
    args = { 'tipo' => 'ranking', 'metrica' => 'resolutions_count', 'por' => 'agente', 'id' => '7', 'grafico' => true, **semana }

    expect(described_class.args_para_registro(args).keys).to match_array(%w[tipo metrica por de ate])
  end

  # A descrição vai em toda pergunta ao Guia; os números só vêm quando o modelo chama.
  it 'tem descrição curta' do
    expect(described_class.description.length).to be <= 400
  end

  describe 'as cinco perguntas-padrão batem com os builders da tela' do
    it 'quem resolveu mais conversas: ranking de resolvidas por agente', :aggregate_failures do
      2.times { |vez| resolvida(conversa('2026-09-08 10:00', assignee: atendente), por: atendente, quando: "2026-09-0#{8 + vez} 12:00") }
      resolvida(conversa('2026-09-08 10:00', assignee: outra), por: outra, quando: '2026-09-10 12:00')

      saida = relatorio({ 'tipo' => 'ranking', 'metrica' => 'resolutions_count', 'por' => 'agente', **semana })
      da_tela = V2::Reports::AgentSummaryBuilder.new(account: conta, params: params_da_tela.merge(type: :agent)).build

      expect(saida['linhas'].pluck('id')).to eq([atendente.id, outra.id])
      saida['linhas'].each do |linha|
        expect(linha['valor']).to eq(da_tela.find { |item| item[:id] == linha['id'] }[:resolved_conversations_count])
      end
      expect(saida['linhas'].first).to include('nome' => 'Ana Souza', 'valor' => 2)
    end

    it 'tempo da primeira resposta: resumo da conta, em segundos e escrito', :aggregate_failures do
      [600, 1_800].each do |segundos|
        create(:reporting_event, account: conta, inbox: caixa, conversation: conversa('2026-09-08 10:00'), name: 'first_response',
                                 value: segundos, created_at: Time.zone.parse('2026-09-08 11:00'))
      end

      saida = relatorio({ 'tipo' => 'resumo', 'metrica' => 'avg_first_response_time', **semana })
      da_tela = V2::Reports::Conversations::ReportBuilder.new(
        conta, params_da_tela.merge(type: 'account', id: nil, metric: 'avg_first_response_time', group_by: 'day')
      ).aggregate_value

      expect(saida['media_segundos']).to eq(da_tela.to_f.round)
      expect(saida).to include('media_segundos' => 1_200, 'media' => '20 minutes', 'de_quem' => 'conta')
    end

    it 'conversas por caixa: ranking de conversas por caixa', :aggregate_failures do
      outra_caixa = create(:inbox, account: conta, name: 'E-mail')
      2.times { conversa('2026-09-08 10:00') }
      create(:conversation, account: conta, inbox: outra_caixa, created_at: Time.zone.parse('2026-09-09 10:00'))

      saida = relatorio({ 'tipo' => 'ranking', 'metrica' => 'conversations_count', 'por' => 'caixa', **semana })
      da_tela = V2::Reports::InboxSummaryBuilder.new(account: conta, params: params_da_tela.merge(type: :inbox)).build

      expect(saida['linhas'].map { |linha| linha.slice('nome', 'valor') })
        .to eq([{ 'nome' => 'WhatsApp', 'valor' => 2 }, { 'nome' => 'E-mail', 'valor' => 1 }])
      saida['linhas'].each do |linha|
        expect(linha['valor']).to eq(da_tela.find { |item| item[:id] == linha['id'] }[:conversations_count])
      end
    end

    it 'conversas por etiqueta: ranking de conversas por etiqueta, e a etiqueta parada é contada', :aggregate_failures do
      create(:label, account: conta, title: 'vip')
      create(:label, account: conta, title: 'parada')
      2.times { conversa('2026-09-08 10:00').update_labels(['vip']) }

      saida = relatorio({ 'tipo' => 'ranking', 'metrica' => 'conversations_count', 'por' => 'etiqueta', **semana })
      da_tela = V2::Reports::LabelSummaryBuilder.new(account: conta, params: params_da_tela.merge(type: :label)).build

      expect(saida['linhas']).to eq([{ 'nome' => 'vip', 'id' => conta.labels.find_by(title: 'vip').id, 'valor' => 2 }])
      expect(saida['linhas'].first['valor']).to eq(da_tela.find { |item| item[:name] == 'vip' }[:conversations_count])
      expect(saida['sem_atividade']).to eq(1)
    end

    it 'conversas por dia: série da conta, dia a dia, com o total da tela', :aggregate_failures do
      conversa('2026-09-08 10:00')
      2.times { conversa('2026-09-09 10:00') }

      saida = relatorio({ 'tipo' => 'serie', 'metrica' => 'conversations_count', 'agrupar' => 'dia', **semana })
      builder = V2::Reports::Conversations::ReportBuilder.new(
        conta, params_da_tela.merge(type: 'account', id: nil, metric: 'conversations_count', group_by: 'day')
      )

      expect(saida['pontos'].pluck('valor')).to eq(builder.timeseries.pluck(:value))
      expect(saida['pontos'].first(3)).to eq([{ 'periodo' => '2026-09-07', 'valor' => 0 }, { 'periodo' => '2026-09-08', 'valor' => 1 },
                                              { 'periodo' => '2026-09-09', 'valor' => 2 }])
      expect(saida['total']).to eq(builder.aggregate_value)
    end
  end

  describe 'permissão' do
    it 'quem não vê a tela Relatórios recebe a frase de sem acesso' do
      agente = Autonomia::Guide::Contexto.new(account: conta, user: atendente)

      expect(chamar({ 'tipo' => 'resumo', 'metrica' => 'conversations_count', **semana }, quem: agente))
        .to eq(described_class::SEM_PERMISSAO)
    end

    it 'a função com report_manage vê, como na tela', :aggregate_failures do
      conta.account_users.find_by(user: atendente).update!(custom_role: create(:custom_role, account: conta, permissions: ['report_manage']))
      com_funcao = Autonomia::Guide::Contexto.new(account: conta, user: atendente)

      expect(relatorio({ 'tipo' => 'resumo', 'metrica' => 'conversations_count', **semana }, quem: com_funcao)).to include('total' => 0)
    end

    it 'sem ninguém logado, recusa sem derrubar o turno' do
      expect(chamar({ 'tipo' => 'resumo', 'metrica' => 'conversations_count', **semana }, quem: nil))
        .to include('não sei quem está perguntando')
    end
  end

  describe 'pedido que não vira relatório' do
    it 'diz o que corrigir, em pt-BR', :aggregate_failures do
      expect(chamar({ 'tipo' => 'resumo', 'metrica' => 'conversations_count', 'de' => '07/09/2026', 'ate' => '2026-09-13' }))
        .to include('AAAA-MM-DD')
      expect(chamar({ 'tipo' => 'ranking', 'metrica' => 'conversations_count', **semana })).to include('ranking precisa de por')
      expect(chamar({ 'tipo' => 'serie', 'metrica' => 'conversations_count', 'por' => 'agente', 'id' => '999999', **semana }))
        .to include('Não achei agente 999999')
      expect(chamar({ 'tipo' => 'ranking', 'metrica' => 'bot_handoffs_count', 'por' => 'agente', **semana }))
        .to include('ranking só tem')
    end
  end

  describe 'série longa' do
    it 'acima de 31 dias agrupa por semana e diz isso', :aggregate_failures do
      conversa('2026-08-03 10:00')

      saida = relatorio({ 'tipo' => 'serie', 'metrica' => 'conversations_count', 'agrupar' => 'dia', 'grafico' => true,
                          'de' => '2026-08-01', 'ate' => '2026-09-30' })

      expect(saida['agrupado_por']).to eq('semana')
      expect(saida['nota']).to include('agrupado por semana')
      expect(saida['pontos'].size).to be <= Autonomia::Guide::Relatorio::Pedido::MAX_PONTOS
      expect(contexto.graficos.first['barras'].size).to eq(saida['pontos'].size)
    end
  end

  describe 'gráfico' do
    before do
      conversa('2026-09-08 10:00')
      2.times { conversa('2026-09-09 10:00') }
    end

    let(:serie) { { 'tipo' => 'serie', 'metrica' => 'conversations_count', 'grafico' => true, **semana } }

    it 'o modelo recebe o marcador; os números do desenho ficam no Contexto', :aggregate_failures do
      saida = relatorio(serie)

      expect(saida['grafico']).to eq('[grafico:1]')
      expect(saida).not_to have_key('grafico_dados')
      expect(contexto.graficos.first).to include('id' => '1', 'modo' => 'serie', 'de' => '2026-09-07', 'ate' => '2026-09-13',
                                                 'titulo' => 'Conversations by day')
      expect(contexto.graficos.first['barras'].first(3).pluck('valor')).to eq([0, 1, 2])
    end

    it 'ranking desenha barras deitadas na ordem do ranking' do
      2.times { resolvida(conversa('2026-09-08 10:00', assignee: atendente), por: atendente, quando: '2026-09-09 12:00') }

      relatorio({ 'tipo' => 'ranking', 'metrica' => 'resolutions_count', 'por' => 'agente', 'grafico' => true, **semana })

      expect(contexto.graficos.first).to include('modo' => 'ranking', 'barras' => [{ 'rotulo' => 'Ana Souza', 'valor' => 2 }])
    end

    it 'sem pedir gráfico, não desenha nada' do
      relatorio(serie.except('grafico'))

      expect(contexto.graficos).to be_empty
    end

    it 'no máximo 3 gráficos por turno; o quarto avisa o modelo', :aggregate_failures do
      3.times { relatorio(serie) }
      quarto = relatorio(serie)

      expect(contexto.graficos.size).to eq(3)
      expect(quarto).not_to have_key('grafico')
      expect(quarto['grafico_nota']).to include('3 gráficos')
    end

    it 'no máximo 60 barras por gráfico, as maiores no ranking e as mais recentes na série', :aggregate_failures do
      pedido = instance_double(Autonomia::Guide::Relatorio::Pedido, de: Date.new(2026, 9, 1), ate: Date.new(2026, 9, 30))
      barras = (1..70).map { |numero| { rotulo: "B#{numero}", valor: numero } }

      ranking = Autonomia::Guide::Grafico.montar(modo: 'ranking', titulo: 't', medida: 'm', pedido: pedido, barras: barras)
      serie = Autonomia::Guide::Grafico.montar(modo: 'serie', titulo: 't', medida: 'm', pedido: pedido, barras: barras)

      expect(ranking['barras'].size).to eq(Autonomia::Guide::Grafico::MAX_BARRAS)
      expect(ranking['barras'].first['rotulo']).to eq('B1')
      expect(serie['barras'].last['rotulo']).to eq('B70')
    end

    it 'sem nenhum valor acima de zero, não desenha e diz por quê' do
      saida = relatorio(serie.merge('de' => '2026-10-01', 'ate' => '2026-10-07'))

      expect(saida['grafico_nota']).to include('Nenhum valor')
    end
  end

  it 'cabe no teto de saída de uma ferramenta, mesmo com muita gente no ranking' do
    stub_const('Autonomia::Guide::Relatorio::Saida::TETO', 300)
    4.times { |vez| conversa('2026-09-08 10:00', assignee: create(:user, account: conta, name: "Pessoa #{vez}")) }

    saida = chamar({ 'tipo' => 'ranking', 'metrica' => 'conversations_count', 'por' => 'agente', **semana })

    expect(saida.length).to be <= 300
    expect(JSON.parse(saida)['cortado']).to include('Mostrando')
  end
end
