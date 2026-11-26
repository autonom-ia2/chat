require 'rails_helper'

# #3258 (flag `agente_le_no_meio_do_turno`): o cliente escreveu no meio da fala, depois do 1º pedaço (teste C3, 26/11).
# Com a entrega inteira, o texto da fala termina; o comparativo do Seguro Viagem dela fica SEGURADO na âncora (o último
# pedaço) até o fim do turno seguinte. O turno seguinte que cotou de novo descarta o segurado (o PDF dele é o que vale);
# o que não cotou o solta, e ele sai uma vez, depois da resposta. Sem a flag, ou sem mensagem nova, como antes.
RSpec.describe Autonomia::Agents::Operate::ChunkedDeliveryJob, :um_turno do
  include_context 'with crm responsible agent'

  let(:fala) { Autonomia::Agents::Operate::FalaEmCurso }
  let(:segurado) { Autonomia::Agents::Operate::ComparativoSegurado }
  let(:entrega) { Autonomia::Agents::Tools::Native::SeguroViagem::EntregaDoComparativo }
  let(:cartoes_job) { 'Autonomia::Agents::Operate::EnviarCartoesJob' }
  let!(:pergunta) { cliente_escreve('quero seguro pra Itália de 05/05/2027 a 20/05/2027, só eu, 40 anos') }
  # Horário estritamente maior que o da pergunta: com horário empatado a ordem das duas não é garantida.
  let!(:no_meio) do
    travel 1.second
    cliente_escreve('ah, e minha esposa vai junto, 38 anos')
  end
  let!(:primeira_cotacao) { cotacao!([40]) }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run }
  end

  before do
    account.enable_features!(Autonomia::Agents::Operate::LeituraNoTurno::FLAG)
    contrato!
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    clear_enqueued_jobs
    limpar_a_fala!
    # O cliente escreveu depois do 1º pedaço: a marca do debounce aponta para a mensagem nova.
    pendente!(no_meio)
  end

  after { limpar_a_fala! }

  def limpar_a_fala!
    Redis::Alfred.delete(fala.chave_ocupada(conversation.id))
    Redis::Alfred.delete(fala.chave_do_fim(conversation.id))
  end

  def pendente!(mensagem)
    conversation.update!(additional_attributes: { 'autonomia_debounce' => { 'pending_message_id' => mensagem.id } })
  end

  def cotacao!(idades)
    Autonomia::Agents::CotacaoDeViagem.create!(
      account: account, conversation: conversation, agent: agente_da_porta, id_cotacao: '0',
      pedido: { 'destinos' => ['IT'], 'destinos_nomes' => ['Itália'], 'data_saida' => '2027-05-05',
                'data_retorno' => '2027-05-20', 'idades' => idades, 'motivo' => nil, 'universal' => {} },
      planos: [{ 'codigo' => 'P1', 'nome' => 'Exemplo Master', 'preco_total' => '489.37', 'max_parcelas' => 12,
                 'idade_minima' => 0, 'idade_maxima' => 85, 'faixas' => [{ 'de' => 0, 'ate' => 85, 'valor' => '489.37' }],
                 'coberturas' => [{ 'id_beneficio' => 2899, 'nome' => 'Despesas Médicas', 'valor' => '$40.000', 'moeda' => 'USD' }] }]
    )
  end

  def token(mensagem, cotacao)
    "mensagem:#{mensagem.id}:cartao:comparativo_viagem:#{cotacao.id}"
  end

  # A referência que o Responder põe na marca do último pedaço (`com_os_cartoes_no_ultimo`).
  def com_o_comparativo(pedaco, mensagem, cotacao)
    referencia = { 'tipo' => entrega::TIPO_DO_CARTAO, 'chave' => cotacao.id.to_s, 'token' => token(mensagem, cotacao) }
    pedaco.merge('marca' => { 'autonomia_cartoes' => [referencia] })
  end

  def fala_velha
    [{ 'text' => 'Cotação para a Itália, para você, de 40 anos:', 'type' => 'text', 'delay_ms' => 900 },
     com_o_comparativo({ 'text' => 'No PDF estão as outras opções. Com qual plano você quer seguir?', 'type' => 'text',
                         'delay_ms' => 900 }, pergunta, primeira_cotacao)]
  end

  # A cadeia da fala velha já começou: o último pedaço (índice 1) é o que leva o comparativo.
  def ultimo_pedaco_da_fala_velha!
    described_class.perform_now(conversation.id, vinculo_da_porta.id, pergunta.id, fala_velha, 1, {})
  end

  # O turno seguinte, numa mensagem só (um pedaço), com o comparativo dele ou sem.
  def turno_seguinte!(texto, cotacao = nil)
    pedaco = { 'text' => texto, 'type' => 'text', 'delay_ms' => 900 }
    pedaco = com_o_comparativo(pedaco, no_meio, cotacao) if cotacao
    described_class.perform_now(conversation.id, vinculo_da_porta.id, no_meio.id, [pedaco], 0, {})
  end

  def ancora
    respostas.where("content_attributes::text LIKE '%autonomia_cartoes%'").order(:id).first
  end

  def estado_na_ancora
    ancora.reload.content_attributes[segurado::CHAVE]
  end

  def pdfs
    respostas.order(:id).select { |mensagem| mensagem.content_attributes.key?(entrega::CHAVE) }
  end

  def rodar_cartoes!
    rodar_turno!(cartoes_job)
  end

  # Pega o C3: o PDF da cotação velha saindo depois que o cliente já tinha mudado o pedido.
  it 'fala começada e mensagem nova antes do último pedaço: o texto sai inteiro e o comparativo fica segurado',
     :aggregate_failures do
    linhas = linhas_do_log { ultimo_pedaco_da_fala_velha! }

    expect(respostas.pluck(:content)).to eq(['No PDF estão as outras opções. Com qual plano você quer seguir?'])
    expect(jobs_de(cartoes_job)).to be_empty
    expect(estado_na_ancora).to eq(token(pergunta, primeira_cotacao) => { 'estado' => 'segurado' })
    expect(linhas.join).to include('comparativo_segurado', 'acao=segurou', "ancora=#{ancora.id}", "cotacao=#{primeira_cotacao.id}")
  end

  # Pega: o retry do Sidekiq do pedaço segurado mandar o comparativo (ou esquecer que ele estava segurado).
  it 'retry do último pedaço segurado: não enfileira o comparativo e o segurado fica', :aggregate_failures do
    ultimo_pedaco_da_fala_velha!
    ultimo_pedaco_da_fala_velha! # ja_postado

    expect(respostas.count).to eq(1)
    expect(jobs_de(cartoes_job)).to be_empty
    expect(estado_na_ancora.values).to eq([{ 'estado' => 'segurado' }])
  end

  # Pega o C3 inteiro: dois PDFs, o primeiro errado.
  it 'turno seguinte com cotação nova: o segurado é descartado com o motivo e só o PDF novo sai', :aggregate_failures do
    ultimo_pedaco_da_fala_velha!
    nova = cotacao!([40, 38])
    linhas = linhas_do_log { turno_seguinte!('Incluí sua esposa. Os valores são para vocês dois.', nova) }
    rodar_cartoes!

    expect(estado_na_ancora.values).to eq([{ 'estado' => 'descartado' }])
    expect(pdfs.map { |pdf| pdf.content_attributes[entrega::CHAVE] }).to eq([nova.id])
    expect(linhas.join).to include('cartao_descartado', 'motivo=substituido_no_turno_seguinte', "msg=#{pergunta.id}")
    expect(linhas.join).to include('comparativo_segurado', 'acao=descartou', "cotacao=#{primeira_cotacao.id}")
  end

  # Pega: o cliente ficar sem o PDF da cotação que vale quando o turno seguinte não cotou ("obrigado").
  it 'turno seguinte sem cotação nova: o segurado sai uma vez, depois da resposta', :aggregate_failures do
    ultimo_pedaco_da_fala_velha!
    linhas = linhas_do_log { turno_seguinte!('Combinado, a sua esposa entra quando você escolher o plano.') }
    resposta = respostas.order(:id).last
    rodar_cartoes!
    turno_seguinte!('Combinado, a sua esposa entra quando você escolher o plano.') # retry do último pedaço do turno seguinte
    rodar_cartoes!

    expect(pdfs.map { |pdf| pdf.content_attributes[entrega::CHAVE] }).to eq([primeira_cotacao.id])
    expect(pdfs.sole.content_attributes['autonomia_cartao_token']).to eq(token(pergunta, primeira_cotacao))
    expect(pdfs.sole.id).to be > resposta.id
    expect(estado_na_ancora.values).to eq([{ 'estado' => 'solto', 'depois_de' => resposta.id }])
    expect(linhas.join).to include('comparativo_segurado', 'acao=soltou')
  end

  # Pega: o turno seguinte que calou (sinal de silêncio) deixar o comparativo segurado para sempre.
  it 'turno seguinte em silêncio: o segurado sai sem esperar resposta', :aggregate_failures do
    ultimo_pedaco_da_fala_velha!
    ia_responde!(texto: Autonomia::Agents::Operate::Responder::SILENCE_TOKEN)
    resultado = Autonomia::Agents::Operate::Responder.new(conversation: conversation, agent_inbox: vinculo_da_porta,
                                                          reply_to_message_id: no_meio.id).perform
    rodar_cartoes!

    expect(resultado.status).to eq(:silenced)
    expect(estado_na_ancora.values).to eq([{ 'estado' => 'solto', 'depois_de' => nil }])
    expect(pdfs.map { |pdf| pdf.content_attributes[entrega::CHAVE] }).to eq([primeira_cotacao.id])
  end

  # Pega: o segurado de outro agente, ou de um turno mais novo, ser decidido pelo fim deste.
  it 'o fim do turno da própria fala não solta o segurado dela' do
    ultimo_pedaco_da_fala_velha!
    segurado.no_fim_do_turno(conversation, agente_da_porta, pergunta.id)

    expect(estado_na_ancora.values).to eq([{ 'estado' => 'segurado' }])
  end

  it 'flag desligada: o comparativo sai como hoje', :aggregate_failures do
    account.disable_features!(Autonomia::Agents::Operate::LeituraNoTurno::FLAG)
    ultimo_pedaco_da_fala_velha!
    rodar_cartoes!

    expect(ancora.reload.content_attributes).not_to have_key(segurado::CHAVE)
    expect(pdfs.map { |pdf| pdf.content_attributes[entrega::CHAVE] }).to eq([primeira_cotacao.id])
  end

  it 'sem mensagem nova: o comparativo sai como hoje', :aggregate_failures do
    pendente!(pergunta)
    ultimo_pedaco_da_fala_velha!
    rodar_cartoes!

    expect(ancora.reload.content_attributes).not_to have_key(segurado::CHAVE)
    expect(pdfs.map { |pdf| pdf.content_attributes[entrega::CHAVE] }).to eq([primeira_cotacao.id])
  end
end
