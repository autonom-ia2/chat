require 'rails_helper'

# #3246: o voucher em PDF baixado da Universal e anexado na conversa. Respostas e PDF fictícios: nenhum voucher real.
RSpec.describe Autonomia::Agents::Tools::Native::SeguroViagem::EntregaDoVoucher do
  let(:base) { 'https://api-br.universal-assistance.com' }
  let(:url_do_pdf) { 'https://voucher.exemplo.test/PrintVoucher/?numeroCarrinho=dGV4dG8tZmljdGljaW8=&idioma=portugues' }
  let(:pdf) { "%PDF-1.6\n1 0 obj\n<<>>\nendobj\n%%EOF\n" }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:atendente) { create(:user, account: account) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:contratado) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'sdr', instruction: 'retrato',
                                     config: { 'contratado' => { 'modelo' => 'seguro_viagem_universal' } })
  end
  let(:cotacao) do
    Autonomia::Agents::CotacaoDeViagem.create!(account: account, conversation: conversa, agent: contratado, id_cotacao: 'c-1',
                                               planos: [], pedido: { 'idades' => [45] },
                                               proposta: { 'codigo_carrinho' => 987_654, 'pago_em' => '2026-11-26T11:47:40' })
  end
  let(:atributos) { { 'autonomia_agent_id' => contratado.id, 'autonomia_cartao_token' => 'mensagem:1:cartao:voucher_viagem:1' } }
  let(:entrega) { described_class.new(conversation: conversa, cotacao: cotacao, sender_id: agent_bot.id, atributos: atributos) }

  before do
    enable_test_encryption!
    Autonomia::Agents::AcessoDaSeguradora.create!(account: account, agent: contratado, login: 'corretor.teste',
                                                  senha: 's3nha-teste', estado: 'ok')
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('voucher.exemplo.test').and_return(['93.184.216.34'])
  end

  def universal_devolve(url)
    stub_request(:get, "#{base}/v1/Voucher/imprimir/987654").with(query: hash_including({}))
                                                            .to_return(status: 200, body: { 'url' => url }.to_json)
  end

  def pdf_responde(corpo, tipo: 'application/pdf')
    stub_request(:get, url_do_pdf).to_return(status: 200, body: corpo, headers: { 'Content-Type' => tipo })
  end

  def notas
    conversa.messages.where(private: true)
  end

  it 'o cartão do turno: o tipo e o id da cotação, sem formato, e a cotação só desta conversa' do
    cartao = described_class.cartao(cotacao)
    expect(cartao).to eq('tipo' => 'voucher_viagem', 'chave' => cotacao.id.to_s, 'rich_message' => nil)
    expect(described_class.cartao?(cartao)).to be(true)
    expect(described_class.cotacao_do(cartao, conversa)).to eq(cotacao)
    expect(described_class.cotacao_do(cartao, create(:conversation, account: account, inbox: inbox))).to be_nil
  end

  it 'baixa o PDF e anexa sem texto, com o nome do voucher, e grava voucher_enviado_em' do
    universal_devolve(url_do_pdf)
    pdf_responde(pdf)

    mensagem = entrega.criar(entrega.baixar)

    expect(mensagem.content).to be_nil
    expect(mensagem.private).to be(false)
    expect(mensagem.sender).to eq(agent_bot)
    anexo = mensagem.attachments.sole.file
    expect([anexo.content_type, anexo.filename.to_s]).to eq(['application/pdf', 'voucher-seguro-viagem.pdf'])
    expect(mensagem.content_attributes).to include(atributos.merge(described_class::CHAVE => cotacao.id))
    expect(cotacao.reload.proposta).to include('voucher_enviado_em', 'pago_em' => '2026-11-26T11:47:40', 'codigo_carrinho' => 987_654)
  end

  it 'com responsável na conversa vira nota privada' do
    conversa.update!(assignee: atendente)
    universal_devolve(url_do_pdf)
    pdf_responde(pdf)
    expect(entrega.criar(entrega.baixar).private).to be(true)
  end

  it 'a URL responde JSON no lugar do PDF (pagamento não realizado): nota privada à equipe, nada ao cliente' do
    universal_devolve(url_do_pdf)
    pdf_responde({ 'mensagem' => 'O Pagamento do Pix ainda não foi realizado.', 'erro' => 0 }.to_json, tipo: 'application/json')

    expect(entrega.baixar).to be_nil
    expect(notas.sole.content).to eq(I18n.t(described_class::NOTA))
    expect(conversa.messages.where(private: false)).to be_empty
    expect(ActiveStorage::Blob.count).to eq(0)
  end

  it 'bytes que não são PDF, mesmo com o tipo certo: nota privada' do
    universal_devolve(url_do_pdf)
    pdf_responde('{"erro":1}')
    expect(entrega.baixar).to be_nil
    expect(notas.count).to eq(1)
  end

  it 'voucher não encontrado na Universal (400): nota privada' do
    stub_request(:get, "#{base}/v1/Voucher/imprimir/987654").with(query: hash_including({}))
                                                            .to_return(status: 400, body: '"Voucher não encontrado."')
    expect(entrega.baixar).to be_nil
    expect(notas.count).to eq(1)
  end

  it 'URL sem https: não baixa, nota privada' do
    universal_devolve('http://voucher.exemplo.test/PrintVoucher/')
    expect(entrega.baixar).to be_nil
    expect(a_request(:get, 'http://voucher.exemplo.test/PrintVoucher/')).not_to have_been_made
    expect(notas.count).to eq(1)
  end

  it 'redirecionamento não é seguido: nota privada' do
    universal_devolve(url_do_pdf)
    stub_request(:get, url_do_pdf).to_return(status: 302, headers: { 'Location' => 'https://outro.exemplo.test/x.pdf' })
    expect(entrega.baixar).to be_nil
    expect(notas.count).to eq(1)
  end

  it 'acesso à seguradora que não está ok: nem chama a Universal, nota privada' do
    contratado.acesso_da_seguradora.update!(estado: 'recusado')
    expect(entrega.baixar).to be_nil
    expect(a_request(:get, "#{base}/v1/Voucher/imprimir/987654").with(query: hash_including({}))).not_to have_been_made
    expect(notas.count).to eq(1)
  end

  it 'o log da falha leva só ids e o código, nunca a URL do voucher' do
    saida = StringIO.new
    allow(Rails).to receive(:logger).and_return(ActiveSupport::Logger.new(saida))
    universal_devolve(url_do_pdf)
    pdf_responde('{}', tipo: 'application/json')
    entrega.baixar
    expect(saida.string).to include("voucher_nao_saiu conv=#{conversa.id} cotacao=#{cotacao.id} falha=tipo_invalido")
    expect(saida.string).not_to include('dGV4dG8tZmljdGljaW8', 'voucher.exemplo.test')
  end
end
