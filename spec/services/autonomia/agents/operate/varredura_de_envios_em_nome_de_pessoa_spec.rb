require 'rails_helper'
require 'prism'

# GUARDA DE ARQUITETURA (#1669): o `PessoaDaEquipe.da_pessoa?` decide quem é PESSOA pelo remetente User, e tira os
# envios automáticos gravados em nome dela pela MARCA que cada um grava (MARCAS_DE_ENVIO_AUTOMATICO e as de campanha).
# Um envio automático novo em nome de pessoa, sem marca, faria a IA ler o robô como pessoa (moldura) e calar à toa. Esta
# varredura acha, por AST (Prism), cada criação de mensagem com remetente em app/services e app/jobs, e cobra a marca.
#
# O que conta como envio com remetente:
#   (A) `Messages::MessageBuilder.new(remetente, ...)` / `Autonomia::LiteralMessageBuilder.new(remetente, ...)` com o
#       1º argumento diferente de `nil` (o robô passa `nil` e `sender_type: 'AgentBot'` nos parâmetros);
#   (B) `create`/`create!`/`new`/`build` com `sender:` não-nil e `message_type:` presentes no mesmo hash.
# A marca vale se aparecer como CHAVE de hash literal no método do envio, ou num método do mesmo arquivo chamado por ele
# sem receptor (um nível: `session_content_attributes`). Limite conhecido: o tipo do remetente não é estático. Por isso
# os envios em que o remetente é a própria pessoa no painel, ou o contato (canais de entrada), ficam em REVISADOS, cada
# um com o motivo; um envio novo fora da lista e sem marca reprova.
module VarreduraDeEnviosEmNomeDePessoa
  RAIZES = %w[app/services app/jobs].freeze
  BUILDERS = %w[Messages::MessageBuilder Autonomia::LiteralMessageBuilder].freeze
  CRIADORES = %i[create create! new build].freeze

  # arquivo#método => por que não precisa de marca.
  REVISADOS = {
    'app/services/macros/execution_service.rb#add_private_note' => 'macro: a pessoa executa no painel; nota privada',
    'app/services/macros/execution_service.rb#send_message' => 'macro: a pessoa executa no painel (MacrosExecutionJob)',
    'app/services/macros/execution_service.rb#send_attachment' => 'macro: a pessoa executa no painel (MacrosExecutionJob)',
    'app/services/whatsapp/contact_info_request_service.rb#perform' => 'pedido de dados: botão do painel (Current.user)',
    'app/services/autonomia/agents/operate/reaction_materializer.rb#call' => 'remetente é o contato (incoming)',
    'app/services/line/incoming_message_service.rb#message_created?' => 'remetente é o contato (incoming)',
    'app/services/sms/incoming_message_service.rb#perform' => 'remetente é o contato (incoming)',
    'app/services/telegram/incoming_message_service.rb#perform' => 'remetente é o contato do Telegram',
    'app/services/twilio/incoming_message_service.rb#perform' => 'remetente é o contato (incoming)',
    'app/services/twitter/direct_message_parser_service.rb#perform' => 'remetente é o contato do Twitter',
    'app/services/twitter/tweet_parser_service.rb#create_message' => 'remetente é o contato do Twitter',
    'app/services/whatsapp/history_message_service.rb#import_message' => 'saída importada vai sem remetente (nil)',
    'app/services/whatsapp/incoming_message_base_service.rb#create_message' => 'eco vai sem remetente; entrada, o contato'
  }.freeze

  Envio = Struct.new(:arquivo, :linha, :metodo) do
    def id
      "#{arquivo}##{metodo}"
    end
  end

  module_function

  def marcas
    ::Autonomia::Agents::Operate::PessoaDaEquipe::MARCAS_DE_ENVIO_AUTOMATICO + %w[campaign_id whatsapp_api_campaign_id]
  end

  def arquivos
    RAIZES.flat_map { |raiz| Dir[Rails.root.join(raiz, '**', '*.rb').to_s] }
          .map { |caminho| Pathname(caminho).relative_path_from(Rails.root).to_s }.sort
  end

  def cada_no(nodo, metodo = nil, &)
    return if nodo.nil?

    metodo = nodo.name if nodo.is_a?(Prism::DefNode)
    yield(nodo, metodo)
    nodo.compact_child_nodes.each { |filho| cada_no(filho, metodo, &) }
  end

  def argumentos(nodo)
    nodo.respond_to?(:arguments) ? Array(nodo.arguments&.arguments) : []
  end

  def chave(elemento)
    return unless elemento.is_a?(Prism::AssocNode)

    elemento.key.unescaped if elemento.key.is_a?(Prism::SymbolNode) || elemento.key.is_a?(Prism::StringNode)
  end

  def pares(nodo)
    argumentos(nodo).select { |arg| arg.is_a?(Prism::KeywordHashNode) || arg.is_a?(Prism::HashNode) }
                    .flat_map(&:elements)
  end

  def com_remetente_no_builder?(nodo)
    nodo.name == :new && nodo.receiver && BUILDERS.include?(nodo.receiver.slice.delete_prefix('::')) &&
      !argumentos(nodo).first.is_a?(Prism::NilNode)
  end

  def com_remetente_no_hash?(nodo)
    return false unless CRIADORES.include?(nodo.name)

    elementos = pares(nodo)
    remetente = elementos.find { |elemento| chave(elemento) == 'sender' }
    remetente && !remetente.value.is_a?(Prism::NilNode) && elementos.any? { |elemento| chave(elemento) == 'message_type' }
  end

  def envio?(nodo)
    nodo.is_a?(Prism::CallNode) && (com_remetente_no_builder?(nodo) || com_remetente_no_hash?(nodo))
  end

  def envios
    arquivos.flat_map do |arquivo|
      lista = []
      cada_no(Prism.parse_file(Rails.root.join(arquivo).to_s).value) do |nodo, metodo|
        lista << Envio.new(arquivo, nodo.location.start_line, metodo) if envio?(nodo)
      end
      lista
    end
  end

  # { nome_do_método => DefNode } do arquivo.
  def metodos(arquivo)
    defs = {}
    cada_no(Prism.parse_file(Rails.root.join(arquivo).to_s).value) do |nodo, _metodo|
      defs[nodo.name] = nodo if nodo.is_a?(Prism::DefNode)
    end
    defs
  end

  def chaves_em(nodo)
    achadas = []
    cada_no(nodo) { |filho, _metodo| achadas << chave(filho) if filho.is_a?(Prism::AssocNode) }
    achadas.compact
  end

  def chamados_sem_receptor(nodo)
    nomes = []
    cada_no(nodo) { |filho, _metodo| nomes << filho.name if filho.is_a?(Prism::CallNode) && filho.receiver.nil? }
    nomes
  end

  # A marca no método do envio ou num método do arquivo chamado por ele (um nível).
  def marcado?(envio)
    defs = metodos(envio.arquivo)
    corpo = defs[envio.metodo]
    return false if corpo.nil?

    vizinhos = chamados_sem_receptor(corpo).filter_map { |nome| defs[nome] }
    ([corpo] + vizinhos).flat_map { |nodo| chaves_em(nodo) }.intersect?(marcas)
  end
end

RSpec.describe VarreduraDeEnviosEmNomeDePessoa do
  let(:envios) { described_class.envios }

  it 'acha os envios em nome de pessoa que já conhecemos (senão a varredura não está olhando)' do
    ids = envios.map(&:id)

    expect(ids).to include('app/services/crm/follow_ups/message_sender.rb#create_session_message',
                           'app/services/crm/booking_v2/notices/delivery.rb#build',
                           'app/services/whatsapp_api_campaigns/conversation_recorder.rb#create_message!')
  end

  it 'todo envio com remetente tem a marca de envio automático, ou está revisado com motivo' do
    sem_marca = envios.reject { |envio| described_class.marcado?(envio) || described_class::REVISADOS.key?(envio.id) }

    aviso = 'envio com remetente sem marca: grave uma marca de MARCAS_DE_ENVIO_AUTOMATICO ou revise em REVISADOS'
    expect(sem_marca.map { |envio| "#{envio.arquivo}:#{envio.linha} #{envio.id}" }).to be_empty, aviso
  end

  it 'a lista de revisados não guarda envio que sumiu' do
    expect(described_class::REVISADOS.keys - envios.map(&:id)).to be_empty
  end

  it 'reprova um envio novo sem marca' do
    codigo = <<~RUBY
      class Lembrete
        def enviar(user, conversa)
          Messages::MessageBuilder.new(user, conversa, ActionController::Parameters.new(content: 'oi')).perform
        end
      end
    RUBY
    arvore = Prism.parse(codigo).value
    achados = []
    described_class.cada_no(arvore) { |nodo, metodo| achados << metodo if described_class.envio?(nodo) }

    expect(achados).to eq([:enviar])
    expect(described_class.chaves_em(arvore) & described_class.marcas).to be_empty
  end
end
