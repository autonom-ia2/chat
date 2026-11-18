require 'rails_helper'

# E9 (#2902): a medição de uso da carteira de seguros. Só contagens, por conta, no mês da conta (no fuso dela). Os dados
# são fictícios.
RSpec.describe Carteira::Medida do
  let(:account) { conta_com_carteira }
  let(:pessoa) { create(:contact, account: account, name: 'Ana Albuquerino', phone_number: '+5511910310001') }
  let(:agora) { Time.zone.parse('2026-11-18 12:00:00') }
  let(:mes_passado) { Time.zone.parse('2026-10-15 12:00:00') }

  around { |example| travel_to(agora) { example.run } }

  def seguro(dono = pessoa, **campos)
    criar_apolice(dono, **campos)
  end

  def passo(apolice, tipo, quando: agora, **valores)
    apolice.eventos.create!(tipo: tipo, quando: quando, valores: valores)
  end

  def medida(pedido = described_class::ESTE_MES)
    described_class.new(account, pedido).call
  end

  def em_renovacao(apolice)
    funil, etapa = create_crm_pipeline(account: account, user: create(:user, account: account), name: 'Renovação')
    card = account.crm_cards.create!(pipeline: funil, stage: etapa, contact: apolice.contact, title: 'Renovação')
    apolice.update!(crm_card_id: card.id)
  end

  # Todas as folhas do resultado, para provar que nada além de número, sim/não, data e código nosso sai daqui.
  def folhas(valor)
    case valor
    when Hash then valor.flat_map { |chave, filho| [chave, *folhas(filho)] }
    when Array then valor.flat_map { |item| folhas(item) }
    else [valor]
    end
  end

  it 'conta os seguros na carteira por origem, com os de outra corretora e os cancelados à parte' do
    2.times { seguro(origem: 'planilha') }
    seguro(origem: 'manual')
    seguro(origem: 'pdf')
    seguro(origem: 'conector')
    seguro(origem: 'pdf', de_fora: true)
    seguro(origem: 'planilha', cancelado_em: agora)
    seguro(origem: 'planilha', renovado_em: agora)

    expect(medida[:seguros]).to eq(
      por_origem: { 'planilha' => 2, 'manual' => 1, 'pdf' => 1, 'conector' => 1 }, de_fora: 1, cancelados: 1
    )
  end

  it 'conta as renovações em aberto agora e as fechadas no mês, com o motivo agrupado' do
    em_renovacao(seguro(fim_vigencia: agora.to_date + 20))
    em_renovacao(seguro(fim_vigencia: agora.to_date + 30, cancelado_em: agora))
    seguro(renovado_em: agora - 2.days)
    seguro(renovado_em: mes_passado)
    seguro(nao_renovou_em: agora - 1.day, motivo_nao_renovou: 'achou_caro')
    seguro(nao_renovou_em: agora - 3.days, motivo_nao_renovou: 'achou_caro')
    seguro(nao_renovou_em: agora - 1.day, motivo_nao_renovou: 'outra_corretora')
    seguro(nao_renovou_em: agora - 1.day)
    seguro(nao_renovou_em: mes_passado, motivo_nao_renovou: 'cancelou')

    expect(medida[:renovacoes]).to eq(
      em_aberto: 1, renovadas: 1, nao_renovadas: 4,
      nao_renovadas_por_motivo: { 'achou_caro' => 2, 'outra_corretora' => 1, 'sem_motivo' => 1 }
    )
  end

  it 'conta os passos da cotação da renovação no mês e o "não saiu" por motivo' do
    apolice = seguro
    %w[cotacao_pedida proposta_pedida proposta_pronta proposta_enviada proposta_enviada_sozinha].each { |tipo| passo(apolice, tipo) }
    2.times { passo(apolice, 'proposta_nao_saiu', motivo: 'conferencia_caiu') }
    passo(apolice, 'proposta_nao_saiu')
    passo(apolice, 'proposta_pedida', quando: mes_passado)
    passo(apolice, 'renovou')

    expect(medida[:cotacao]).to eq(
      passos: { 'cotacao_pedida' => 1, 'proposta_pedida' => 1, 'proposta_pronta' => 1, 'proposta_enviada' => 1,
                'proposta_enviada_sozinha' => 1, 'proposta_nao_saiu' => 3 },
      nao_saiu_por_motivo: { 'conferencia_caiu' => 2, 'sem_motivo' => 1 }
    )
  end

  it 'conta os lotes de leitura por origem e os passos de PDF no mês' do
    apolice = seguro(origem: 'pdf')
    create(:carteira_leitura, account: account, origem: 'pdf')
    create(:carteira_leitura, account: account, origem: 'pdf')
    create(:carteira_leitura, account: account, origem: 'conector')
    create(:carteira_leitura, account: account, origem: 'pdf', created_at: mes_passado)
    passo(apolice, 'chegou_pdf')
    passo(apolice, 'dados_lidos_pdf', vigencia: apolice.fim_vigencia.iso8601)
    passo(apolice, 'chegou_pdf', quando: mes_passado)

    expect(medida[:leitura]).to eq(lotes: { 'pdf' => 2, 'conector' => 1 },
                                   passos: { 'chegou_pdf' => 1, 'dados_lidos_pdf' => 1 })
  end

  it 'mês passado conta só o mês anterior' do
    apolice = seguro
    passo(apolice, 'proposta_pedida')
    passo(apolice, 'proposta_pedida', quando: mes_passado)
    passo(apolice, 'proposta_pedida', quando: mes_passado)
    seguro(renovado_em: mes_passado)

    linha = medida(described_class::MES_PASSADO)

    expect([linha[:inicio], linha[:fim], linha[:cotacao][:passos]['proposta_pedida'], linha[:renovacoes][:renovadas]])
      .to eq([Date.new(2026, 10, 1), Date.new(2026, 10, 31), 2, 1])
  end

  it 'lê o mês no fuso da conta: 23h30 de 31/10 em São Paulo é outubro, mesmo já sendo novembro na instalação' do
    account.update!(reporting_timezone: 'America/Sao_Paulo')
    apolice = seguro
    passo(apolice, 'proposta_pedida', quando: ActiveSupport::TimeZone['America/Sao_Paulo'].parse('2026-10-31 23:30'))

    expect([medida[:cotacao][:passos]['proposta_pedida'], medida(described_class::MES_PASSADO)[:cotacao][:passos]['proposta_pedida'],
            medida[:fuso]]).to eq([0, 1, 'America/Sao_Paulo'])
  end

  it 'não mistura as contas' do
    outra = conta_com_carteira
    de_outra = seguro(create(:contact, account: outra), origem: 'manual', nao_renovou_em: agora, motivo_nao_renovou: 'achou_caro')
    passo(de_outra, 'proposta_pedida')
    passo(de_outra, 'chegou_pdf')
    create(:carteira_leitura, account: outra, origem: 'pdf')

    linha = medida

    expect([linha[:seguros][:por_origem].values.sum, linha[:renovacoes][:nao_renovadas], linha[:cotacao][:passos].values.sum,
            linha[:leitura][:lotes].values.sum, linha[:leitura][:passos].values.sum, linha[:chaves][:tem_seguro]])
      .to eq([0, 0, 0, 0, 0, false])
  end

  it 'devolve só números, sim ou não, datas e códigos nossos: nada de pessoa, apólice ou dinheiro' do
    apolice = seguro(numero: 'EX-998877', bem: 'Carro de exemplo prata', valor_centavos: 123_456,
                     nao_renovou_em: agora, motivo_nao_renovou: 'outro', motivo_escrito: 'Motivo escrito de exemplo')
    passo(apolice, 'proposta_nao_saiu', motivo: 'faltou_dado', faltam: ['insured.birthdate'])

    resultado = described_class.por_conta(described_class::ESTE_MES)
    textos = folhas(resultado).map(&:to_s)

    expect(textos).not_to include('Ana Albuquerino', '+5511910310001', 'EX-998877', 'Carro de exemplo prata', '123456',
                                  'Motivo escrito de exemplo', 'insured.birthdate')
    tipos = [Integer, Symbol, String, Date, TrueClass, FalseClass]
    expect(folhas(resultado)).to all(satisfy { |folha| tipos.any? { |tipo| folha.is_a?(tipo) } })
  end

  it 'lista as contas que usam a carteira, soma o total e conta quem tem seguro e cada chave' do
    seguro(origem: 'planilha')
    Carteira::Leitor::Liberado.ligar!(account)
    so_com_a_cotacao = create(:account)
    Carteira::Cotacao::Liberada.ligar!(so_com_a_cotacao)
    outra = conta_com_carteira
    seguro(create(:contact, account: outra), origem: 'manual')
    create(:account)

    resultado = described_class.por_conta(described_class::ESTE_MES)

    expect(resultado[:linhas].pluck(:conta_id)).to eq([account.id, so_com_a_cotacao.id, outra.id].sort)
    expect(resultado[:total][:seguros][:por_origem]).to eq('planilha' => 1, 'manual' => 1, 'pdf' => 0, 'conector' => 0)
    expect(resultado[:total][:contas]).to eq(tem_seguro: 2, leitura: 1, cotacao: 1)
  end

  it 'sem conta nenhuma usando a carteira, não tem linha nem total' do
    create(:account)

    expect(described_class.por_conta(described_class::ESTE_MES)).to eq(linhas: [], total: nil)
  end

  it 'aceita só os dois períodos; o resto vira o mês corrente' do
    expect(['este_mes', 'mes_passado', 'qualquer', nil].map { |pedido| described_class.periodo(pedido) })
      .to eq(%w[este_mes mes_passado este_mes este_mes])
  end
end
