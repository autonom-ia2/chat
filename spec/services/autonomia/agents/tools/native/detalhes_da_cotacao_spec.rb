require 'rails_helper'

RSpec.describe Autonomia::Agents::Tools::Native::DetalhesDaCotacao do
  let(:base) { 'https://api-br.universal-assistance.com' }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox) }
  let(:contratado) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'sdr', instruction: 'retrato',
                                     config: { 'contratado' => { 'modelo' => 'seguro_viagem_universal' } })
  end
  let(:delivery) { Autonomia::Agents::Tools::Delivery.new(conversation: conversa, agent_inbox: nil) }
  let(:idades) { [47, 19, 12] }
  let(:resposta) { JSON.parse(file_fixture('../universal/cotacao.json').read) }

  before do
    Autonomia::Agents::CotacaoDeViagem.create!(
      account: account, conversation: conversa, agent: contratado, id_cotacao: 'COT-TESTE-1',
      planos: Autonomia::Agents::Tools::Native::SeguroViagem::Planos.de(resposta, idades: idades),
      pedido: { 'destinos' => ['PT'], 'idades' => idades }
    )
  end

  def ferramenta(argumentos, entrega: delivery)
    described_class.new(agent: contratado, params: argumentos, delivery: entrega)
  end

  it 'lê a cotação guardada, sem chamar a Universal' do
    saida = JSON.parse(ferramenta({ 'codigos_dos_planos' => ['P1'] }).call)
    expect(saida['planos'].pluck('codigo')).to eq(['P1'])
    expect(saida['planos'].first['coberturas'].first)
      .to eq('id_beneficio' => 2898, 'nome' => 'Despesas Médicas e Hospitalares (por evento)', 'descricao_completa' => '',
             'valor' => 'R$ 100.000', 'moeda' => 'BRL')
    expect(a_request(:post, "#{base}/v1/Cotacao")).not_to have_been_made
  end

  it 'preço total e por pessoa pela faixa de cada idade cotada' do
    p1, p2 = JSON.parse(ferramenta({ 'codigos_dos_planos' => [] }).call)['planos']
    expect(p1.slice('preco_total', 'preco_por_pessoa'))
      .to eq('preco_total' => 'R$ 360,00', 'preco_por_pessoa' => ['R$ 120,00', 'R$ 120,00', 'R$ 120,00'])
    expect(p2['preco_por_pessoa']).to eq(['R$ 70,00', 'R$ 70,00', 'R$ 70,00'])
  end

  it 'preço por dia e por pessoa: total ÷ dias da viagem (ida e volta inclusive) ÷ viajantes, para baixo (#3226)' do
    cotacao = Autonomia::Agents::CotacaoDeViagem.last
    cotacao.update!(pedido: cotacao.pedido.merge('data_saida' => '2027-02-02', 'data_retorno' => '2027-02-12'))
    p1, p2 = JSON.parse(ferramenta({ 'codigos_dos_planos' => [] }).call)['planos']
    # 11 dias e 3 viajantes: 360 ÷ 33 = 10,909... e 210 ÷ 33 = 6,363...
    expect([p1['por_dia_por_pessoa'], p2['por_dia_por_pessoa']]).to eq(['R$ 10,90', 'R$ 6,36'])
  end

  it 'cotação sem as datas da viagem: sem preço por dia' do
    expect(JSON.parse(ferramenta({ 'codigos_dos_planos' => ['P1'] }).call)['planos'].first['por_dia_por_pessoa']).to be_nil
  end

  it 'idade sem faixa fica nil no lugar' do
    cotacao = Autonomia::Agents::CotacaoDeViagem.last
    cotacao.update!(pedido: cotacao.pedido.merge('idades' => [47, 70]))
    p1 = JSON.parse(ferramenta({ 'codigos_dos_planos' => ['P1'] }).call)['planos'].first
    expect(p1['preco_por_pessoa']).to eq(['R$ 120,00', nil])
  end

  it 'devolve parcelas, câmbio, limites de idade e a regra de cancelamento como lista' do
    p1 = JSON.parse(ferramenta({ 'codigos_dos_planos' => ['P1'] }).call)['planos'].first
    expect(p1.slice('max_parcelas', 'cambio', 'moeda', 'idade_minima', 'idade_maxima'))
      .to eq('max_parcelas' => 12, 'cambio' => 5.9702, 'moeda' => 'R$', 'idade_minima' => 0, 'idade_maxima' => 65)
    expect(p1['regra_cancelamento']).to be_an(Array)
    expect(p1).to have_key('descricao_adicional')
  end

  it 'código desconhecido recusa com o campo' do
    expect(Autonomia::Agents::Tools::Recusa).to receive(:registrar)
      .with('plano_inexistente', hash_including(faltando: ['codigos_dos_planos']))
    ferramenta({ 'codigos_dos_planos' => ['P9'] }).call
  end

  it 'sem cotação na conversa recusa' do
    Autonomia::Agents::CotacaoDeViagem.delete_all
    expect(Autonomia::Agents::Tools::Recusa).to receive(:registrar).with('sem_cotacao', anything)
    ferramenta({ 'codigos_dos_planos' => [] }).call
  end

  it 'sem conversa não lê nada' do
    expect(ferramenta({ 'codigos_dos_planos' => [] }, entrega: nil).call).to include('cotacao_sem_conversa')
  end

  it 'sem campo interno' do
    expect(ferramenta({ 'codigos_dos_planos' => [] }).call).not_to include('comissao', 'markup', 'rank', 'id_produto')
  end
end
