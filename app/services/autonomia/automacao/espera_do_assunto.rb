# G71 (#2883, decisão 20 do Rodrigo, 10/11): o "extrair" que grava no card da conversa espera a IA de assunto decidir.
# Na automação que começa numa mensagem recebida, o extrair roda na hora, e a IA de assunto, que abre o card do pedido
# novo, só decide depois da espera dela (Crm::Subjects::DEBOUNCE, 15 s; DEBOUNCE_ORDEM, 3 s, na ordem do turno). Sem
# esperar, o extrair não acha o card e marca os campos como ausentes, sem erro em lugar nenhum.
#
# Espera só com a IA de assunto ligada na caixa da conversa (Crm::Subjects.ligado?) e enquanto o marco "assunto decidido"
# (Crm::Subjects::Marco, que o IdentifyJob grava em TODA saída) não alcança a última mensagem do cliente. O teto conta da
# mensagem: passado TETO, o extrair segue como hoje (sem card, o campo fica ausente). Sem a IA de assunto, nada muda.
#
# O aviso da decisão (Crm::Subjects::IdentifyJob::EVENTO, assinado em config/initializers/autonomia_automacao_assunto.rb)
# acorda a execução que espera no extrair da conversa, com a mesma reserva da Escuta. Sem o aviso (erro, fila atrasada),
# a varredura a acorda no teto.
module Autonomia::Automacao::EsperaDoAssunto
  module_function

  # Cobre a espera da IA de assunto, a fila e a ida ao modelo maior. Fica bem abaixo da validade do marco (10 min).
  TETO = 2.minutes

  # Até quando o extrair espera o assunto desta conversa; nil quando não espera.
  def ate(conversa)
    return unless conversa.is_a?(::Conversation) && ::Crm::Subjects.ligado?(conversa)

    mensagem = conversa.messages.incoming.reorder(id: :desc).first
    return if mensagem.nil? || ::Crm::Subjects::Marco.decidido_ate?(conversa.id, mensagem.id)

    limite = mensagem.created_at + TETO
    limite if limite.future?
  end

  # O resultado do extrair que espera (`:esperar` até o `ate`): o executor guarda o passo e o roda de novo quando a IA
  # de assunto decide, ou no teto. nil quando não espera.
  def resultado(conversa)
    limite = ate(conversa)
    ::Autonomia::Automacao::PassoDeAcao::Resultado.new(tipo: :esperar, motivo: nil, dados: { 'ate' => limite }) if limite
  end

  # O aviso da decisão: a execução que espera no extrair desta conversa confere agora, em vez de no teto. O erro vai para
  # o log, e a espera segue pelo relógio.
  def decidido(conversation_id)
    conversa = ::Conversation.find_by(id: conversation_id)
    return unless conversa && ::Autonomia::Automacao::Motor.ligado?(conversa.account)

    ::Autonomia::Automacao::Execucao.where(account_id: conversa.account_id, alvo_type: 'Conversation', alvo_id: conversa.id, estado: 'esperando')
                                    .includes(:versao).find_each { |execucao| acordar(execucao) }
  rescue StandardError => e
    ::Autonomia::Automacao::Escuta.registrar_erro("não acordou pelo assunto conversa=#{conversation_id}", e)
  end

  # Só a que espera no extrair, sem nova tentativa marcada: a do erro passageiro da IA segue o relógio, como na Escuta.
  def acordar(execucao)
    passo = ::Autonomia::Automacao::Roteiro.new(execucao.versao.receita).passo(execucao.cursor)
    ::Autonomia::Automacao::Escuta.reservar(execucao) if passo&.fetch('tipo', nil) == 'extrair' && execucao.tentativas.zero?
  rescue StandardError => e
    ::Autonomia::Automacao::Despertador.nao_acordou(execucao, e)
  end
end
