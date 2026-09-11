require 'rails_helper'

# A PENDÊNCIA DE ENVIO (rodada 8 da entrega 11, P2 do Codex): a marca na própria mensagem que diz "o
# `SendReplyJob` desta mensagem não entrou na fila". O que estes exemplos travam é a ESCRITA no banco:
# uma só, atômica, que mescla sem apagar o resto do `content_attributes`, e que respeita a forma com
# que o `store ... coder: JSON` da `Message` grava a coluna (uma STRING JSON, não o objeto) — nas
# quatro formas em que a coluna pode estar (rodada 9). E a LEITURA pelo varredor (`marcadas`), que não
# pode tropeçar numa linha que não seja objeto JSON.
RSpec.describe Autonomia::Agents::Tools::PendenciaDeEnvio do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:mensagem) { mensagem_do_bot(content_attributes: { 'autonomia_async_token' => 'abc:1', 'autonomia_async_sequence' => 0 }) }

  def mensagem_do_bot(**atributos)
    create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: agent_bot, **atributos)
  end

  def tipo_no_banco(alvo = mensagem)
    ActiveRecord::Base.connection.select_value(
      ActiveRecord::Base.sanitize_sql_array(['SELECT json_typeof(content_attributes) FROM messages WHERE id = ?', alvo.id])
    )
  end

  # Escreve a coluna POR SQL, fora do coder da `Message`: é o único jeito de pôr NULL, a string vazia,
  # o objeto direto ou texto que não é JSON — as formas que o coder nunca escreve mas o banco aceita.
  def escrever_coluna(alvo, valor_sql)
    Message.where(id: alvo.id).update_all("content_attributes = #{valor_sql}") # rubocop:disable Rails/SkipsModelValidations
    alvo
  end

  it 'marca mesclando, na forma que a Message le de volta, sem apagar o resto do content_attributes' do
    # Act
    described_class.marcar(mensagem, run_id: 7, contexto: 'run=7')

    # Assert — a coluna continua uma string JSON (a forma do coder da Message), lida pelo Rails
    expect(tipo_no_banco).to eq('string')
    expect(mensagem.reload.content_attributes).to include('autonomia_envio_pendente' => true, 'autonomia_tool_run_id' => 7,
                                                          'autonomia_async_token' => 'abc:1', 'autonomia_async_sequence' => 0)
    expect(described_class).to be_pendente(mensagem)
    expect(described_class.execucao_id(mensagem)).to eq(7)
  end

  it 'limpa so a marca e a execucao dela' do
    # Arrange
    described_class.marcar(mensagem, run_id: 7, contexto: 'run=7')

    # Act
    described_class.limpar(mensagem, contexto: 'run=7')

    # Assert
    expect(tipo_no_banco).to eq('string')
    expect(mensagem.reload.content_attributes.keys).not_to include('autonomia_envio_pendente', 'autonomia_tool_run_id')
    expect(mensagem.content_attributes).to include('autonomia_async_token' => 'abc:1', 'autonomia_async_sequence' => 0)
    expect(described_class).not_to be_pendente(mensagem)
  end

  # A MATRIZ DA FORMA (rodada 9, P3 do Codex): a coluna `json` pode guardar a string JSON com o objeto
  # (o coder da Message), NULL, o objeto direto (um escritor que não passe pelo coder) ou a string JSON
  # VAZIA — `""`, cujo `#>> '{}'` dá `''`, que `::jsonb` recusava: a marca não entrava e o log dizia
  # `marca_nao_gravada`. Nas quatro, a marca entra e a Message lê de volta.
  it 'marca sobre as quatro formas da coluna: string com objeto, NULL, objeto direto e string vazia' do
    # Arrange
    alvos = {
      'string com objeto' => mensagem,
      'NULL' => escrever_coluna(mensagem_do_bot, 'NULL'),
      'objeto direto' => escrever_coluna(mensagem_do_bot, %q('{"autonomia_async_token":"abc:1"}'::json)),
      'string vazia' => escrever_coluna(mensagem_do_bot, %q('""'::json))
    }
    allow(Rails.logger).to receive(:warn).and_call_original

    # Act
    alvos.each_value { |alvo| described_class.marcar(alvo, run_id: 7, contexto: 'run=7') }

    # Assert
    expect(alvos.values.map { |alvo| tipo_no_banco(alvo) }).to all(eq('string'))
    expect(alvos.values.map { |alvo| alvo.reload.content_attributes })
      .to all(include('autonomia_envio_pendente' => true, 'autonomia_tool_run_id' => 7))
    expect(alvos.values_at('string com objeto', 'objeto direto').map(&:content_attributes)).to all(include('autonomia_async_token' => 'abc:1'))
    expect(Rails.logger).not_to have_received(:warn).with(a_string_matching(/marca_nao_gravada/))
  end

  # A marca não é pendência quando o canal já confirmou (`source_id`) nem na nota privada (não vai ao canal).
  it 'nao e pendencia com o canal confirmado, na nota privada, nem sem a marca' do
    described_class.marcar(mensagem, run_id: 7, contexto: 'run=7')
    mensagem.reload

    expect(described_class).not_to be_pendente(build(:message, content_attributes: {}))
    expect(described_class).not_to be_pendente(mensagem.tap { |m| m.source_id = 'wamid.1' })
    expect(described_class).not_to be_pendente(mensagem.tap { |m| m.source_id = nil }.tap { |m| m.private = true })
  end

  # A pendência que não vai ser enviada: a marca (e a execução dela) sai, e o motivo fechado vai ao log.
  it 'abandona limpando a marca e registrando o motivo' do
    described_class.marcar(mensagem, run_id: 7, contexto: 'run=7')
    allow(Rails.logger).to receive(:warn).and_call_original

    described_class.abandonar(mensagem, motivo: 'execucao_morta', contexto: 'run=7')

    expect(mensagem.reload.content_attributes.keys).not_to include('autonomia_envio_pendente', 'autonomia_tool_run_id')
    expect(Rails.logger).to have_received(:warn)
      .with(a_string_matching(/envio pendente abandonado run=7 message=#{mensagem.id} motivo=execucao_morta/))
  end

  # A falha da escrita (banco) é registrada com código fechado e não levanta: quem chama decide o
  # resultado pela fila, não pela marca.
  it 'registra e nao levanta quando o banco nao grava a marca' do
    allow(Message).to receive(:where).and_raise(ActiveRecord::StatementInvalid, 'banco fora')
    allow(Rails.logger).to receive(:warn).and_call_original

    expect { described_class.marcar(mensagem, run_id: 7, contexto: 'run=1') }.not_to raise_error
    expect { described_class.limpar(mensagem, contexto: 'run=1') }.not_to raise_error
    nao_gravada = /pendencia de envio nao gravada run=1 message=#{mensagem.id} motivo=marca_nao_gravada causa=ActiveRecord::StatementInvalid/
    nao_limpa = /pendencia de envio nao gravada run=1 message=#{mensagem.id} motivo=marca_nao_limpa causa=ActiveRecord::StatementInvalid/
    expect(Rails.logger).to have_received(:warn).with(a_string_matching(nao_gravada))
    expect(Rails.logger).to have_received(:warn).with(a_string_matching(nao_limpa))
  end

  # A LEITURA PELO VARREDOR (rodada 9): as mensagens do bot com a marca, dentro da janela, até o limite.
  describe '.marcadas' do
    def marcada(alvo = mensagem_do_bot)
      described_class.marcar(alvo, run_id: 7, contexto: 'run=7')
      alvo
    end

    it 'acha so as mensagens do bot com a marca, dentro da janela, as mais antigas primeiro, ate o limite' do
      # Arrange — duas nossas; uma sem marca; uma marcada mas velha; uma marcada de pessoa
      primeira = marcada
      segunda = marcada
      mensagem_do_bot
      marcada.update_columns(created_at: 3.days.ago) # rubocop:disable Rails/SkipsModelValidations
      marcada(create(:message, account: account, conversation: conversation, message_type: :outgoing))

      # Act / Assert
      expect(described_class.marcadas(desde: 2.days.ago, limite: 10)).to eq([primeira, segunda])
      expect(described_class.marcadas(desde: 2.days.ago, limite: 1)).to eq([primeira])
    end

    # O cast é PROTEGIDO: a coluna que não é objeto JSON (NULL, `""`, uma string que não é JSON) não
    # derruba a varredura — e o objeto direto, que o coder não escreve mas o banco aceita, é lido.
    it 'nao tropeca na coluna que nao e objeto JSON, e le o objeto direto' do
      # Arrange
      nossa = marcada
      escrever_coluna(mensagem_do_bot, 'NULL')
      escrever_coluna(mensagem_do_bot, %q('""'::json))
      escrever_coluna(mensagem_do_bot, %q('"nao e json"'::json))
      direta = escrever_coluna(mensagem_do_bot, %q('{"autonomia_envio_pendente": true}'::json))

      # Act
      achadas = described_class.marcadas(desde: 2.days.ago, limite: 10).to_a

      # Assert
      expect(achadas).to contain_exactly(nossa, direta)
    end
  end
end
