require 'rails_helper'

# R19 DA RECEITA DE RAMO: NENHUM TEXTO FIXO AO CLIENTE (regra do Rodrigo: mínimo de texto pronto, IA humanizada).
#
# O cliente só lê o que o modelo escreveu. Texto nosso vai para a equipe, em nota privada; arquivo vai sem legenda.
# Esta guarda varre, por AST (`VarreduraDaReceita::Mensagem`), todo lugar do módulo que cria mensagem numa conversa
# (`Messages::MessageBuilder.new`, `messages.create/new/build`, `Message.create`, `create_message`) e exige que cada
# um esteja classificado abaixo. Ponto novo sem classificação reprova.
#
# A CLASSIFICAÇÃO É CONFERIDA NO CÓDIGO, e não só declarada:
#   nota_privada     a chamada escreve `private: true`;
#   anexo_sem_texto  a chamada escreve `content: nil` ou `content: ''`;
#   fala_do_modelo   `content:` não é texto literal e `private: false` está escrito;
#   outro            o motivo explica por que não é nenhum dos três.
# E o anexo e a nota têm prova de comportamento no fim do arquivo: a mensagem que o código cria.
module TextoAoCliente
  RAIZES = %w[app/services/autonomia app/jobs/autonomia].freeze

  PONTOS = {
    'app/jobs/autonomia/agents/operate/chunked_delivery_job.rb::Autonomia::Agents::Operate::ChunkedDeliveryJob#build_message!' =>
      { tipo: :fala_do_modelo, motivo: 'cada pedaço da resposta do modelo, fatiada para o WhatsApp' },
    'app/services/autonomia/agents/nota_do_encaminhamento.rb::Autonomia::Agents::NotaDoEncaminhamento#criar' =>
      { tipo: :nota_privada, motivo: 'o que a IA não conseguiu antes de encaminhar, para a equipe' },
    'app/services/autonomia/agents/operate/aviso_ao_atendente.rb::Autonomia::Agents::Operate::AvisoAoAtendente#postar_nota' =>
      { tipo: :nota_privada, motivo: 'o evento da cotação de que a IA não falou, para quem atende' },
    'app/services/autonomia/agents/operate/reaction_materializer.rb::Autonomia::Agents::Operate::ReactionMaterializer#call' =>
      { tipo: :outro, motivo: 'mensagem de ENTRADA (incoming) que registra a reação do cliente para o modelo ler; ' \
                              'não sai para o canal' },
    'app/services/autonomia/agents/operate/responder.rb::Autonomia::Agents::Operate::Responder#post_audio_reply!' =>
      { tipo: :anexo_sem_texto, motivo: 'o áudio sintetizado da resposta do modelo, sem texto junto' },
    'app/services/autonomia/agents/operate/responder.rb::Autonomia::Agents::Operate::Responder#post_reply!' =>
      { tipo: :fala_do_modelo, motivo: 'a resposta do modelo no turno' },
    'app/services/autonomia/agents/operate/responder_ao_evento.rb::Autonomia::Agents::Operate::ResponderAoEvento#post_reply!' =>
      { tipo: :fala_do_modelo, motivo: 'a resposta do modelo no turno acionado por um evento da cotação' },
    'app/services/autonomia/agents/tools/async_publisher.rb::Autonomia::Agents::Tools::AsyncPublisher#build_message!' =>
      { tipo: :anexo_sem_texto, motivo: 'o arquivo da ferramenta (comparativo, proposta), sem legenda; privado com humano atribuído' },
    'app/services/autonomia/agents/tools/nota_interna.rb::Autonomia::Agents::Tools::NotaInterna#criar' =>
      { tipo: :nota_privada, motivo: 'a nota da equipe no fecho da cotação' }
  }.freeze

  TIPOS = %i[nota_privada anexo_sem_texto fala_do_modelo outro].freeze

  module_function

  def pontos
    VarreduraDaReceita::Mensagem.pontos(VarreduraDaReceita.arquivos(RAIZES))
  end

  # -> o que falta na chamada para ela ser do tipo declarado, ou nil.
  def problema(ponto, tipo)
    case tipo
    when :nota_privada then 'sem private: true' unless ponto.private.is_a?(Prism::TrueNode)
    when :anexo_sem_texto then 'com content que não é nil nem vazio' unless sem_texto?(ponto.content)
    when :fala_do_modelo then fala_do_modelo(ponto)
    end
  end

  def sem_texto?(content)
    content.is_a?(Prism::NilNode) || (content.is_a?(Prism::StringNode) && content.unescaped.empty?)
  end

  def fala_do_modelo(ponto)
    return 'com content de texto literal' if ponto.content.nil? || literal?(ponto.content)

    'sem private: false' unless ponto.private.is_a?(Prism::FalseNode)
  end

  def literal?(nodo)
    nodo.is_a?(Prism::StringNode) || nodo.is_a?(Prism::InterpolatedStringNode) || nodo.is_a?(Prism::XStringNode)
  end
end

RSpec.describe 'R19: nenhum texto fixo ao cliente' do # rubocop:disable RSpec/DescribeClass
  let(:pontos) { TextoAoCliente.pontos }

  describe 'a varredura' do
    it 'todo ponto que cria mensagem está classificado' do
      soltos = pontos.reject { |ponto| TextoAoCliente::PONTOS.key?(ponto.chave) }

      expect(soltos).to be_empty, <<~MSG
        Ponto novo que cria mensagem numa conversa, sem classificação. Ao cliente só vai o que o modelo escreveu: texto
        nosso é nota privada à equipe, arquivo sai sem legenda. Classifique em TextoAoCliente::PONTOS:
        #{soltos.join("\n")}
      MSG
    end

    it 'toda classificação aponta para um ponto que existe' do
      expect(TextoAoCliente::PONTOS.keys - pontos.map(&:chave)).to be_empty
    end

    it 'a chamada é do tipo que a classificação diz' do
      errados = pontos.filter_map do |ponto|
        declarado = TextoAoCliente::PONTOS.fetch(ponto.chave, {})
        problema = TextoAoCliente.problema(ponto, declarado[:tipo])
        "#{ponto}: #{declarado[:tipo]} #{problema}" if problema
      end

      expect(errados).to be_empty
    end

    it 'cada classificação é de um tipo conhecido, com motivo' do
      TextoAoCliente::PONTOS.each_value do |declarado|
        expect(TextoAoCliente::TIPOS).to include(declarado[:tipo])
        expect(declarado[:motivo].to_s.strip).not_to be_empty
      end
    end

    # AUTOTESTE: a varredura enxerga as três formas de criar mensagem que existem hoje.
    it 'enxerga o MessageBuilder, messages.create! e messages.new' do
      chaves = pontos.map(&:chave)

      expect(pontos.size).to be >= TextoAoCliente::PONTOS.size
      expect(chaves).to include(end_with('NotaInterna#criar'), end_with('ReactionMaterializer#call'),
                                end_with('Responder#post_audio_reply!'))
    end
  end

  # PROVA DE COMPORTAMENTO do anexo e da nota: a mensagem que o código cria de verdade.
  describe 'o que o código cria' do
    let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
    let(:agent_bot) { create(:agent_bot, account: account) }
    let(:agent) do
      Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'custom', status: :active, enabled: true,
                                       instruction: 'Atenda.')
    end
    let(:agent_inbox) { Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot) }
    let(:run) do
      Autonomia::Agents::ToolRun.open!(agent: agent, slug: 'consultar_cotacao', arguments: {},
                                       scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
    end

    around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

    def publicas = conversation.messages.reload.where(private: false, message_type: :outgoing)
    def privadas = conversation.messages.reload.where(private: true)

    it 'o anexo: a mensagem pública tem o arquivo e content nil' do
      stub_arquivo
      run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 3.minutes.from_now)

      resultado = Autonomia::Agents::Tools::AsyncPublisher.new(run: run).publish(arquivo_de_teste)

      mensagem = publicas.sole
      expect(resultado).to be_published
      expect(mensagem.content).to be_nil
      expect(mensagem.attachments.size).to eq(1)
    end

    it 'a nota: o texto nosso vai só em mensagem privada, e nenhuma pública nasce' do
      Autonomia::Agents::Tools::NotaInterna.postar(run, 'Seguradoras sem proposta: texto para a equipe.')

      expect(privadas.sole.content).to eq('Seguradoras sem proposta: texto para a equipe.')
      expect(publicas).to be_empty
    end
  end
end
