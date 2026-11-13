# O que o cliente respondeu à pergunta da reunião (#2935) ou da pesquisa (#2936), entendido pela IA de decidir. Nunca
# por lista de palavras nem por expressão regular (regra do Rodrigo, 20/09/2026): o botão do WhatsApp chega como o texto
# do botão, e "pode ser a de quinta" ou "nota 8, mas demorou" também; quem entende é o modelo, preso a um schema.
#
# Lê só as mensagens do cliente depois do marco da pergunta (a régua do G31, Resposta.novas_desde), nas conversas que
# quem ligou vê, até o prazo. Sem mensagem nova, nem chama a IA. Vão à IA a pergunta que saiu, as opções oferecidas e o
# texto dessas mensagens (nada do contato, nada de outras conversas).
#
# Devolve [resposta conferida pelo schema, custo] ou nil sem mensagem nova; a falha da IA sobe como PassoDeIa::Falha.
class Autonomia::Automacao::RespostaDoCliente
  MODELO = ::Crm::Ai::Config::MODEL_CLASSIFY
  # Contra defeito, não contra uso: as últimas mensagens da janela bastam para entender a resposta.
  ULTIMAS = 10
  MAX_TEXTO = 1000

  # `quem`: quem ligou (as conversas que ele vê). `marco`: o da pergunta, ou o da última resposta ambígua.
  def initialize(conta:, contato:, quem:, marco:, ate:)
    @conta = conta
    @contato = contato
    @quem = quem
    @marco = marco
    @ate = ate
  end

  def novas? = novas.exists?

  # O marco de agora, para a próxima leitura partir dele quando esta resposta não disser nada.
  def marco_novo = ::Autonomia::Automacao::Resposta.marco(@contato, @quem)

  def entender(feature:, instrucoes:, pergunta:, schema:)
    textos = novas.reorder(:id).last(ULTIMAS).filter_map { |mensagem| mensagem.content.to_s.squish.first(MAX_TEXTO).presence }
    return if textos.empty?

    ia = ::Autonomia::Automacao::PassoDeIa.new(conta: @conta, feature: feature, modelo: MODELO)
    ia.perguntar(instrucoes: instrucoes, entrada: { pergunta: pergunta, respostas_do_cliente: textos }, schema: schema)
  end

  private

  def novas
    return ::Message.none if @marco.blank?

    recebidas = ::Autonomia::Automacao::Resposta.do_cliente(@contato, @quem)
    return ::Message.none if recebidas.nil?

    lidas = ::Autonomia::Automacao::Resposta.novas_desde(recebidas, @marco)
    @ate ? lidas.where('messages.created_at <= ?', @ate) : lidas
  end
end
