# O passo "Pesquisa de satisfação" (#2936): pergunta a nota de 0 a 10, espera a resposta e segue pelo galho da faixa
# (nota baixa, média ou alta, que a receita define), ou pelo "Se o cliente não responder" no prazo.
#
# - Não pergunta de novo à mesma pessoa antes de `intervalo_dias` desde a última pesquisa que ela recebeu, de qualquer
#   automação da conta: pula (`pesquisa_recente`) e segue para o passo seguinte, sem galho.
# - A pergunta é um passo "mensagem" com as notas em botões onde o canal tem (MensagemComOpcoes; no WhatsApp a lista da
#   Meta para em 10 opções, então lá a pergunta vai em texto, e ela já diz "de 0 a 10"). Quem não recebe pula; a janela
#   de 24 h fechada manda o modelo aprovado no lugar, ou nada e a execução para nesta conversa (decisão de 12/11).
# - A resposta, botão ou texto ("nota 8, mas demorou"), a IA entende (RespostaDoCliente) e devolve a nota e o comentário.
#   Sem nota clara: espera a próxima resposta, até o prazo.
# - A nota fica no contato (`additional_attributes.pesquisas.<automação>` e a última em `pesquisa_satisfacao`) e no card
#   (`metadata.pesquisa_satisfacao`), e entra no resumo da lista (ResumoDaPesquisa: média e quantas pessoas responderam).
class Autonomia::Automacao::PassoDePesquisa
  include ::Autonomia::Automacao::NaConversa

  Falha = ::Autonomia::Automacao::PassoDeIa::Falha
  NOTAS = (0..10).map(&:to_s).freeze
  ULTIMA = 'pesquisa_satisfacao'.freeze
  POR_AUTOMACAO = 'pesquisas'.freeze
  PERGUNTADA_EM = 'pesquisa_perguntada_em'.freeze
  MAX_COMENTARIO = 300
  INSTRUCOES = <<~TEXTO.freeze
    O cliente recebeu a pergunta de satisfação (em "pergunta") e respondeu (em "respostas_do_cliente"). Responda só com JSON no schema.
    "nota": o número inteiro de 0 a 10 que ele deu, ou null quando ele não deu nota ou não deixou claro qual. Nunca invente a nota.
    "comentario": o que mais ele disse sobre o atendimento, em uma frase curta, em português; vazio quando não disse nada além da nota.
  TEXTO
  SCHEMA = { name: 'automacao_pesquisa_nota',
             schema: { type: 'object', additionalProperties: false, required: %w[nota comentario],
                       properties: { nota: { type: %w[integer null], minimum: 0, maximum: 10 }, comentario: { type: 'string' } } } }.freeze

  # Perguntada há menos de `intervalo_dias`? O ensaio pergunta o mesmo.
  def self.recente?(contato, passo)
    em = contato&.additional_attributes.to_h[PERGUNTADA_EM]
    em.present? && Time.zone.parse(em.to_s) > passo['intervalo_dias'].to_i.days.ago
  rescue ArgumentError
    false
  end

  # A faixa da nota: até `baixa_ate` é baixa, desde `alta_desde` é alta, o resto é média.
  def self.faixa(passo, nota)
    return 'nota_baixa' if nota <= passo['baixa_ate']
    return 'nota_alta' if nota >= passo['alta_desde']

    'nota_media'
  end

  def initialize(execucao:, passo:, alvo:, acesso: nil)
    super(execucao: execucao, passo: passo, alvo: alvo)
    @acesso = acesso
  end

  def perguntar
    return sem_conversa if @conversa.nil?
    return Resultado.new(tipo: :pulado, motivo: 'pesquisa_recente', dados: {}) if self.class.recente?(contexto.contato, @passo)

    mandado = ::Autonomia::Automacao::MensagemComOpcoes.new(
      execucao: @execucao, passo: @passo, alvo: @alvo, texto: @passo['pergunta'], opcoes: NOTAS, numerar: false
    ).executar
    return mandado unless mandado.tipo == :ok

    marcar_perguntada
    Resultado.new(tipo: :esperar, dados: mandado.dados.merge('marco' => ::Autonomia::Automacao::Resposta.marco(contexto.contato, quem_ligou)))
  end

  def resposta(_pedido, marco:, ate:)
    leitor = ::Autonomia::Automacao::RespostaDoCliente.new(conta: conta, contato: contexto.contato, quem: quem_ligou, marco: marco, ate: ate)
    return Resultado.new(tipo: :esperar, dados: {}) unless leitor.novas?

    novo = leitor.marco_novo
    resposta, custo = leitor.entender(feature: 'automacao_pesquisa_nota', instrucoes: INSTRUCOES, pergunta: @passo['pergunta'], schema: SCHEMA)
    nota = resposta&.dig('nota')
    return Resultado.new(tipo: :esperar, dados: { 'marco' => novo }) unless nota.is_a?(Integer) && nota.between?(0, 10)

    respondida(nota, resposta['comentario'].to_s.squish.first(MAX_COMENTARIO), custo)
  rescue Falha => e
    Resultado.new(tipo: :passageiro, motivo: e.motivo, dados: {})
  end

  def depois_de_esperar(_registro) = nil

  def fechar(_pedido) = nil

  private

  def conta = @execucao.account

  def contexto = (@contexto ||= ::Autonomia::Automacao::Contexto.de(@alvo, execucao: @execucao))

  def quem_ligou = @execucao.automacao.ligada_por

  def respondida(nota, comentario, custo)
    resposta = { 'nota' => nota, 'comentario' => comentario.presence, 'em' => Time.current.iso8601 }.compact
    guardar_no_contato(resposta)
    guardar_no_card(resposta)
    Resultado.new(tipo: :ok, dados: { 'ramo' => self.class.faixa(@passo, nota), 'nota' => nota, 'comentario' => comentario.presence,
                                      'ia' => custo }.compact)
  end

  def marcar_perguntada
    contato = contexto.contato
    contato.reload.update!(additional_attributes: contato.additional_attributes.to_h.merge(PERGUNTADA_EM => Time.current.iso8601))
  end

  def guardar_no_contato(resposta)
    contato = contexto.contato.reload
    atributos = contato.additional_attributes.to_h
    por_automacao = atributos[POR_AUTOMACAO].to_h.merge(@execucao.automacao_id.to_s => resposta)
    contato.update!(additional_attributes: atributos.merge(POR_AUTOMACAO => por_automacao,
                                                           ULTIMA => resposta.merge('automacao_id' => @execucao.automacao_id)))
  end

  def guardar_no_card(resposta)
    card = contexto.card
    return unless card

    card.reload.update!(metadata: card.metadata.to_h.merge(ULTIMA => resposta.merge('automacao_id' => @execucao.automacao_id)))
  end
end
