require 'rails_helper'

# #3258 (flag `agente_le_no_meio_do_turno`): o cliente escreveu no meio da fala, depois do 1º pedaço (teste C3, 26/11).
# Com a entrega inteira, o texto da fala termina; o comparativo do Seguro Viagem dela fica SEGURADO na âncora (o último
# pedaço) até o fim do turno seguinte, quando um job próprio decide: o turno seguinte que ENTREGA um comparativo descarta
# o segurado; o que não entrega o solta, e ele sai uma vez, depois da resposta. Sem a flag, ou sem mensagem nova, como
# antes.
RSpec.describe Autonomia::Agents::Operate::ChunkedDeliveryJob, :um_turno do
  include_context 'with crm responsible agent'

  let(:fala) { Autonomia::Agents::Operate::FalaEmCurso }
  let(:segurado) { Autonomia::Agents::Operate::ComparativoSegurado }
  let(:entrega) { Autonomia::Agents::Tools::Native::SeguroViagem::EntregaDoComparativo }
  let(:cartoes_job) { 'Autonomia::Agents::Operate::EnviarCartoesJob' }
  let(:decisao_job) { 'Autonomia::Agents::Operate::DecidirComparativoSeguradoJob' }
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

  def referencia(mensagem, cotacao)
    { 'tipo' => entrega::TIPO_DO_CARTAO, 'chave' => cotacao.id.to_s, 'token' => token(mensagem, cotacao) }
  end

  # As referências que o Responder põe na marca do último pedaço (`com_os_cartoes_no_ultimo`).
  def com_cartoes(pedaco, *referencias)
    pedaco.merge('marca' => { 'autonomia_cartoes' => referencias })
  end

  def pedaco(texto)
    { 'text' => texto, 'type' => 'text', 'delay_ms' => 900 }
  end

  def fala_velha(*referencias)
    referencias = [referencia(pergunta, primeira_cotacao)] if referencias.empty?
    [pedaco('Cotação para a Itália, para você, de 40 anos:'),
     com_cartoes(pedaco('No PDF estão as outras opções. Com qual plano você quer seguir?'), *referencias)]
  end

  # A cadeia da fala velha já começou: o último pedaço (índice 1) é o que leva o comparativo.
  def ultimo_pedaco_da_fala_velha!(*referencias)
    described_class.perform_now(conversation.id, vinculo_da_porta.id, pergunta.id, fala_velha(*referencias), 1, {})
  end

  # O turno seguinte, numa mensagem só (um pedaço), com o comparativo dele ou sem.
  def turno_seguinte!(texto, cotacao = nil, mensagem: no_meio)
    unico = pedaco(texto)
    unico = com_cartoes(unico, referencia(mensagem, cotacao)) if cotacao
    described_class.perform_now(conversation.id, vinculo_da_porta.id, mensagem.id, [unico], 0, {})
  end

  def ancora
    respostas.where("content_attributes::text LIKE '%autonomia_cartoes%'").order(:id).first
  end

  def estado_na_ancora(mensagem = ancora)
    mensagem.reload.content_attributes[segurado::CHAVE]
  end

  def pdfs
    respostas.order(:id).select { |mensagem| mensagem.content_attributes.key?(entrega::CHAVE) }
  end

  def cotacoes_dos_pdfs
    pdfs.map { |pdf| pdf.content_attributes[entrega::CHAVE] }
  end

  def decidir!
    rodar_turno!(decisao_job)
  end

  def enviar_cartoes!
    rodar_turno!(cartoes_job)
  end

  describe 'segurar' do
    # Pega o C3: o PDF da cotação velha saindo depois que o cliente já tinha mudado o pedido.
    it 'fala começada e mensagem nova antes do último pedaço: o texto sai inteiro e o comparativo fica segurado',
       :aggregate_failures do
      linhas = linhas_do_log { ultimo_pedaco_da_fala_velha! }

      expect(respostas.pluck(:content)).to eq(['No PDF estão as outras opções. Com qual plano você quer seguir?'])
      expect(jobs_de(cartoes_job)).to be_empty
      expect(estado_na_ancora).to eq(token(pergunta, primeira_cotacao) => { 'estado' => 'segurado' })
      expect(linhas.join).to include('comparativo_segurado', 'acao=segurou', "ancora=#{ancora.id}", "cotacao=#{primeira_cotacao.id}")
    end

    # Pega: o voucher, o mapa ou o contato da mesma fala ficarem presos junto com o comparativo.
    it 'âncora com comparativo e cartão de contato: só o comparativo fica segurado, o contato sai', :aggregate_failures do
      account.enable_features!('agentes_enviar_local_e_contato')
      nativo = Autonomia::Agents::Tools::Native::CartaoDaPagina
      allow(nativo).to receive(:pagina).and_return({})
      allow(nativo).to receive(:contato_do_agente).and_return('type' => 'contact', 'name' => 'Corretora', 'phone' => '+551140000473')
      contato = { 'tipo' => 'contact', 'chave' => nativo::CHAVE_DO_CONTATO, 'token' => "mensagem:#{pergunta.id}:cartao:contact:pagina" }

      ultimo_pedaco_da_fala_velha!(referencia(pergunta, primeira_cotacao), contato)
      enviar_cartoes!

      expect(estado_na_ancora.keys).to eq([token(pergunta, primeira_cotacao)])
      expect(respostas.filter_map { |mensagem| mensagem.content_attributes['autonomia_cartao_token'] }).to eq([contato['token']])
      expect(pdfs).to be_empty
    end

    # Pega: o retry do Sidekiq do pedaço segurado mandar o comparativo (ou esquecer que ele estava segurado).
    it 'retry do último pedaço segurado: não enfileira o comparativo e o segurado fica', :aggregate_failures do
      ultimo_pedaco_da_fala_velha!
      ultimo_pedaco_da_fala_velha! # ja_postado

      expect(respostas.count).to eq(1)
      expect(jobs_de(cartoes_job)).to be_empty
      expect(estado_na_ancora.values).to eq([{ 'estado' => 'segurado' }])
    end

    # Pega: a Lia mudar de comportamento (regra da casa).
    it 'a Lia, com a entrega inteira ligada: não segura nem decide', :aggregate_failures do
      config = agente_da_porta.config.to_h.merge('conversa_entrega_inteira' => true, 'conversa_em_fila' => true)
      agente_da_porta.update_columns(agent_type: 'insurance_quote', config: config) # rubocop:disable Rails/SkipsModelValidations
      ultimo_pedaco_da_fala_velha!

      expect(ancora.reload.content_attributes).not_to have_key(segurado::CHAVE)
      expect(jobs_de(cartoes_job).size).to eq(1)
      turno_seguinte!('Incluí sua esposa.')
      expect(jobs_de(decisao_job)).to be_empty
    end

    it 'flag desligada: o comparativo sai como hoje', :aggregate_failures do
      account.disable_features!(Autonomia::Agents::Operate::LeituraNoTurno::FLAG)
      ultimo_pedaco_da_fala_velha!
      enviar_cartoes!

      expect(ancora.reload.content_attributes).not_to have_key(segurado::CHAVE)
      expect(cotacoes_dos_pdfs).to eq([primeira_cotacao.id])
    end

    it 'sem mensagem nova: o comparativo sai como hoje', :aggregate_failures do
      pendente!(pergunta)
      ultimo_pedaco_da_fala_velha!
      enviar_cartoes!

      expect(ancora.reload.content_attributes).not_to have_key(segurado::CHAVE)
      expect(cotacoes_dos_pdfs).to eq([primeira_cotacao.id])
    end
  end

  describe 'decidir no fim do turno seguinte' do
    before { ultimo_pedaco_da_fala_velha! }

    # Pega o C3 inteiro: dois PDFs, o primeiro errado. E a decisão rodando dentro do turno.
    it 'turno seguinte entrega comparativo novo: o segurado é descartado com o motivo e só o PDF novo sai',
       :aggregate_failures do
      nova = cotacao!([40, 38])
      turno_seguinte!('Incluí sua esposa. Os valores são para vocês dois.', nova)
      expect(estado_na_ancora.values).to eq([{ 'estado' => 'segurado' }]) # a decisão é do job, não do pedaço

      linhas = linhas_do_log { decidir! }
      enviar_cartoes!

      expect(estado_na_ancora.values).to eq([{ 'estado' => 'descartado', 'motivo' => 'substituido_no_turno_seguinte' }])
      expect(cotacoes_dos_pdfs).to eq([nova.id])
      expect(linhas.join).to include('cartao_descartado', 'motivo=substituido_no_turno_seguinte', "msg=#{pergunta.id}")
      expect(linhas.join).to include('comparativo_segurado', 'acao=descartou', "cotacao=#{primeira_cotacao.id}")
    end

    # Pega: o cliente ficar sem nenhum PDF quando o turno seguinte cotou de novo mas não mandou o comparativo.
    it 'turno seguinte cotou e não entregou comparativo: o segurado sai', :aggregate_failures do
      cotacao!([40, 38])
      turno_seguinte!('Vou incluir a sua esposa: me confirma a data de nascimento dela?')
      decidir!
      enviar_cartoes!

      expect(estado_na_ancora.values.sole['estado']).to eq('solto')
      expect(cotacoes_dos_pdfs).to eq([primeira_cotacao.id])
    end

    # Pega: o segurado da fala 1 sair junto com o da fala 2 quando o cliente escreveu de novo no meio da fala 2.
    it 'turno seguinte com o próprio comparativo segurado: o da fala anterior é descartado', :aggregate_failures do
      nova = cotacao!([40, 38])
      travel 1.second
      de_novo = cliente_escreve('e o meu filho também')
      pendente!(de_novo)
      fala_do_turno_seguinte = [pedaco('Incluí sua esposa.'), com_cartoes(pedaco('No PDF, para vocês dois.'), referencia(no_meio, nova))]
      described_class.perform_now(conversation.id, vinculo_da_porta.id, no_meio.id, fala_do_turno_seguinte, 1, {})
      decidir!

      expect(estado_na_ancora.values).to eq([{ 'estado' => 'descartado', 'motivo' => 'substituido_no_turno_seguinte' }])
      expect(estado_na_ancora(respostas.order(:id).last).values).to eq([{ 'estado' => 'segurado' }])
      expect(jobs_de(cartoes_job)).to be_empty
    end

    # Pega: o PDF sair antes da resposta do turno seguinte (ordem no canal) e sair duas vezes no retry.
    it 'turno seguinte sem comparativo: o segurado espera a resposta sair e sai uma vez', :aggregate_failures do
      saida = Autonomia::Agents::Operate::SaidaDaMensagem
      linhas = linhas_do_log { turno_seguinte!('Combinado, a sua esposa entra quando você escolher o plano.') }
      resposta = respostas.order(:id).last
      linhas += linhas_do_log { decidir! }
      allow(saida).to receive(:estado).and_call_original
      allow(saida).to receive(:estado).with(resposta).and_return(:pendente)

      expect(rodar_rodada!(cartoes_job)).to eq(1)
      expect(pdfs).to be_empty
      expect(jobs_de(cartoes_job).size).to eq(1) # reagendado: espera a resposta sair

      allow(saida).to receive(:estado).with(resposta).and_call_original
      enviar_cartoes!
      turno_seguinte!('Combinado, a sua esposa entra quando você escolher o plano.') # retry do último pedaço do turno seguinte
      decidir!
      enviar_cartoes!

      expect(cotacoes_dos_pdfs).to eq([primeira_cotacao.id])
      expect(pdfs.sole.content_attributes['autonomia_cartao_token']).to eq(token(pergunta, primeira_cotacao))
      expect(estado_na_ancora.values).to eq([{ 'estado' => 'solto', 'depois_de' => resposta.id }])
      expect(linhas.join).to include('comparativo_segurado', 'acao=soltou')
    end

    # Pega: o solto que ainda não saiu mandar o PDF velho depois que um turno mais novo mandou o comparativo dele.
    it 'solto que ainda não saiu e foi superado por um comparativo novo: vira descartado', :aggregate_failures do
      turno_seguinte!('Combinado.')
      decidir!
      clear_enqueued_jobs # o job dos cartões do solto ainda não rodou
      travel 1.second
      terceira = cliente_escreve('fechou, com a minha esposa')
      pendente!(terceira)
      nova = cotacao!([40, 38])
      turno_seguinte!('Incluí sua esposa.', nova, mensagem: terceira)
      decidir!
      enviar_cartoes!
      Autonomia::Agents::Operate::EnviarCartoesJob.perform_now(ancora.id) # o job antigo, atrasado

      expect(estado_na_ancora.values.sole).to include('estado' => 'descartado', 'motivo' => 'substituido_no_turno_seguinte')
      expect(cotacoes_dos_pdfs).to eq([nova.id])
    end

    # Pega: a decisão descartar o comparativo depois que o job dos cartões montou a lista, e o PDF sair assim mesmo.
    it 'postar! confere de novo, sob o lock, que o comparativo não foi descartado' do
      turno_seguinte!('Combinado.')
      decidir!
      cartoes = Autonomia::Agents::Operate::CartoesDoTurno.new(ancora.reload)
      cartao = cartoes.cartoes.sole
      descartado = estado_na_ancora.transform_values { { 'estado' => 'descartado' } }
      ancora.update_column(:content_attributes, ancora.content_attributes.merge(segurado::CHAVE => descartado)) # rubocop:disable Rails/SkipsModelValidations

      expect(cartoes.postar!(cartao)).to be_nil
      expect(pdfs).to be_empty
    end

    # Pega: soltar o comparativo de uma âncora que o job dos cartões já abandonou.
    it 'âncora encerrada: o segurado é descartado com motivo próprio e cartao_nao_enviado', :aggregate_failures do
      Autonomia::Agents::Operate::CartoesDoTurno.new(ancora).encerrar!('pessoa_respondeu')
      turno_seguinte!('Combinado.')
      linhas = linhas_do_log { decidir! }
      enviar_cartoes!

      expect(estado_na_ancora.values).to eq([{ 'estado' => 'descartado', 'motivo' => 'ancora_encerrada' }])
      expect(linhas.join).to include('cartao_nao_enviado', 'motivo=ancora_encerrada', "msg=#{ancora.id}")
      expect(pdfs).to be_empty
    end

    # Pega: o turno seguinte que calou (sinal de silêncio) deixar o comparativo segurado para sempre.
    it 'turno seguinte em silêncio: o segurado sai sem esperar resposta', :aggregate_failures do
      ia_responde!(texto: Autonomia::Agents::Operate::Responder::SILENCE_TOKEN)
      resultado = Autonomia::Agents::Operate::Responder.new(conversation: conversation, agent_inbox: vinculo_da_porta,
                                                            reply_to_message_id: no_meio.id).perform
      decidir!
      enviar_cartoes!

      expect(resultado.status).to eq(:silenced)
      expect(estado_na_ancora.values).to eq([{ 'estado' => 'solto', 'depois_de' => nil }])
      expect(cotacoes_dos_pdfs).to eq([primeira_cotacao.id])
    end

    # Pega: a resposta inteira (sem pedaços) do turno seguinte não disparar a decisão.
    it 'turno seguinte pelo caminho clássico: a decisão é enfileirada e o segurado sai depois da resposta',
       :aggregate_failures do
      ia_responde!(texto: 'Combinado, a sua esposa entra quando você escolher o plano.')
      resultado = with_modified_env(AI_HUMANIZE_DELIVERY: 'false') do
        Autonomia::Agents::Operate::Responder.new(conversation: conversation, agent_inbox: vinculo_da_porta,
                                                  reply_to_message_id: no_meio.id).perform
      end
      expect(jobs_de(decisao_job).size).to eq(1)
      decidir!
      enviar_cartoes!

      expect(resultado.message).to be_present
      expect(estado_na_ancora.values).to eq([{ 'estado' => 'solto', 'depois_de' => resultado.message.id }])
      expect(cotacoes_dos_pdfs).to eq([primeira_cotacao.id])
      expect(pdfs.sole.id).to be > resultado.message.id
    end

    # Pega: o segurado ser decidido pelo fim de um turno que não é o seguinte, ou de outro agente.
    it 'o fim do turno da própria fala, ou de outro agente, não decide o segurado', :aggregate_failures do
      outro = criar_agente('Outro agente')
      segurado.no_fim_do_turno(conversation, agente_da_porta, pergunta.id)
      segurado.no_fim_do_turno(conversation, outro, no_meio.id)

      expect(outro.id).not_to eq(agente_da_porta.id)
      expect(estado_na_ancora.values).to eq([{ 'estado' => 'segurado' }])
    end
  end
end
