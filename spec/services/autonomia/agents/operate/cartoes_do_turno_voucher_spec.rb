require 'rails_helper'

# #3246: o voucher é um cartão do turno, como o comparativo: sai depois da âncora, com o token e os descartes de sempre,
# e é baixado fora do lock da conversa. PDF e respostas fictícios.
RSpec.describe Autonomia::Agents::Operate::CartoesDoTurno do
  let(:base) { 'https://api-br.universal-assistance.com' }
  let(:url_do_pdf) { 'https://intravel.universal-assistance.com/PrintVoucher/?numeroCarrinho=dGV4dG8tZmljdGljaW8=&idioma=portugues' }
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:contratado) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'sdr', instruction: 'retrato',
                                     config: { 'contratado' => { 'modelo' => 'seguro_viagem_universal' } })
  end
  let(:cotacao) do
    Autonomia::Agents::CotacaoDeViagem.create!(account: account, conversation: conversa, agent: contratado, id_cotacao: 'c-1',
                                               planos: [], pedido: { 'idades' => [45] }, proposta: { 'codigo_carrinho' => 987_654 })
  end
  let(:entrega) { Autonomia::Agents::Tools::Native::SeguroViagem::EntregaDoVoucher }
  let(:cartao) { entrega.cartao(cotacao).merge('token' => described_class.token('mensagem:1', entrega.cartao(cotacao))) }
  let(:ancora) do
    create(:message, account: account, inbox: inbox, conversation: conversa, message_type: :outgoing, sender: agent_bot,
                     content: 'Pagamento confirmado! O voucher vai aqui embaixo.',
                     content_attributes: { 'autonomia_agent_id' => contratado.id, described_class::NA_ANCORA => [cartao] })
  end
  let(:cartoes) { described_class.new(ancora) }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  before do
    enable_test_encryption!
    Autonomia::Agents::AcessoDaSeguradora.create!(account: account, agent: contratado, login: 'corretor.teste',
                                                  senha: 's3nha-teste', estado: 'ok')
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('intravel.universal-assistance.com').and_return(['93.184.216.34'])
    stub_request(:get, "#{base}/v1/Voucher/imprimir/987654").with(query: hash_including({}))
                                                            .to_return(status: 200, body: { 'url' => url_do_pdf }.to_json)
  end

  def pdf_responde(corpo, tipo: 'application/pdf')
    stub_request(:get, url_do_pdf).to_return(status: 200, body: corpo, headers: { 'Content-Type' => tipo })
  end

  def publicas
    conversa.messages.reload.outgoing.where(private: false).where.not(id: ancora.id)
  end

  it 'posta o PDF anexado com o token do turno, e o mesmo cartão não sai duas vezes' do
    pdf_responde("%PDF-1.6\n%%EOF\n")

    expect(cartoes.postar!(cartao)).to be_nil
    expect(cartoes.postar!(cartao)).to be_nil

    voucher = publicas.sole
    expect(voucher.attachments.sole.file.content_type).to eq('application/pdf')
    expect(voucher.content_attributes).to include(described_class::TOKEN => cartao['token'], entrega::CHAVE => cotacao.id,
                                                  'autonomia_agent_id' => contratado.id)
    expect(a_request(:get, url_do_pdf)).to have_been_made.once
    expect(cotacao.reload.proposta['voucher_enviado_em']).to be_present
  end

  it 'JSON no lugar do PDF: nenhuma mensagem ao cliente, nota privada à equipe e o motivo voucher_nao_saiu' do
    pdf_responde({ 'mensagem' => 'O Pagamento do Pix ainda não foi realizado.', 'erro' => 0 }.to_json, tipo: 'application/json')

    expect(cartoes.postar!(cartao)).to eq('voucher_nao_saiu')
    expect(publicas).to be_empty
    expect(conversa.messages.reload.where(private: true).count).to eq(1)
    expect(cotacao.reload.proposta).not_to have_key('voucher_enviado_em')
  end

  it 'com responsável humano na conversa, o voucher vira nota privada e não conta como enviado' do
    conversa.update!(assignee: create(:user, account: account))
    pdf_responde("%PDF-1.6\n%%EOF\n")
    cartoes.postar!(cartao)
    expect(conversa.messages.reload.where(private: true).sole.attachments.size).to eq(1)
    expect(cotacao.reload.proposta).not_to have_key('voucher_enviado_em')
  end

  # Dois turnos viram "pago" antes de o primeiro voucher sair: cada âncora tem o seu cartão da mesma cotação. Só um
  # voucher sai, e o segundo cartão não baixa nada.
  it 'duas âncoras com o voucher da mesma cotação: sai um só' do
    pdf_responde("%PDF-1.6\n%%EOF\n")
    ancora # o primeiro turno
    outro = entrega.cartao(cotacao).merge('token' => described_class.token('mensagem:2', entrega.cartao(cotacao)))
    segunda = create(:message, account: account, inbox: inbox, conversation: conversa, message_type: :outgoing, sender: agent_bot,
                               content: 'Caiu, sim! O voucher vai aqui.',
                               content_attributes: { 'autonomia_agent_id' => contratado.id, described_class::NA_ANCORA => [outro] })

    expect(described_class.new(segunda).postar!(outro)).to be_nil
    expect(cartoes.postar!(cartao)).to eq('voucher_ja_saiu')

    expect(publicas.where.not(id: segunda.id).count).to eq(1)
    expect(a_request(:get, url_do_pdf)).to have_been_made.once
  end

  it 'segunda via num turno seguinte (âncora mais nova que o voucher anterior) sai de novo' do
    pdf_responde("%PDF-1.6\n%%EOF\n")
    cartoes.postar!(cartao)
    seguinte = entrega.cartao(cotacao).merge('token' => described_class.token('mensagem:3', entrega.cartao(cotacao)))
    nova = create(:message, account: account, inbox: inbox, conversation: conversa, message_type: :outgoing, sender: agent_bot,
                            content: 'Mando de novo.',
                            content_attributes: { 'autonomia_agent_id' => contratado.id, described_class::NA_ANCORA => [seguinte] })

    expect(described_class.new(nova).postar!(seguinte)).to be_nil
    expect(a_request(:get, url_do_pdf)).to have_been_made.twice
  end

  it 'pessoa da equipe respondeu depois da âncora: não baixa nem posta' do
    allow(Autonomia::Agents::Operate::PessoaDaEquipe).to receive(:respondeu_depois?).and_return(true)
    expect(cartoes.postar!(cartao)).to eq('pessoa_respondeu')
    expect(a_request(:get, url_do_pdf)).not_to have_been_made
  end

  it 'a guarda muda durante o download: não posta e o PDF baixado vai para a limpeza' do
    pdf_responde("%PDF-1.6\n%%EOF\n")
    allow(Autonomia::Agents::Operate::PessoaDaEquipe).to receive(:respondeu_depois?).and_return(false, true)
    allow(Autonomia::Agents::Tools::EntregaDeArquivo).to receive(:agendar_limpeza)

    expect(cartoes.postar!(cartao)).to eq('pessoa_respondeu')
    expect(publicas).to be_empty
    expect(Autonomia::Agents::Tools::EntregaDeArquivo).to have_received(:agendar_limpeza)
      .with(an_instance_of(ActiveStorage::Blob), contexto: 'voucher')
  end

  it 'cotação apagada: cotacao_sumiu, sem baixar' do
    cartao
    cotacao.destroy!
    expect(cartoes.postar!(cartao)).to eq('cotacao_sumiu')
    expect(a_request(:get, "#{base}/v1/Voucher/imprimir/987654").with(query: hash_including({}))).not_to have_been_made
  end

  it 'nos pedaços, a referência do voucher resolve pela cotação, sem formato' do
    referencia = cartao.slice('tipo', 'chave', 'token')
    expect(described_class.resolver([referencia], contratado)).to eq([[referencia.merge('rich_message' => nil)], 0])
  end
end
