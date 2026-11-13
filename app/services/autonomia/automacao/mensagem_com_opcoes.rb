# A pergunta ao cliente com opções (#2935 os 3 horários, #2936 as notas de 0 a 10): o passo "mensagem" inteiro (o
# contato que não recebe, a janela de 24 h com o modelo no lugar, o robô do outro lado, o número novo), com as opções
# em botões quando o canal tem botão, e em números (1, 2, 3) no próprio texto quando não tem.
#
# Botão só onde a plataforma manda de verdade: o chat do site e o WhatsApp oficial (Cloud API) que não é caixa
# híbrida, e no WhatsApp até 10 opções (o limite da lista da Meta). Nos outros canais (e na conversa ainda por abrir) o
# texto leva as opções numeradas. A resposta, botão ou texto, quem entende é a IA (RespostaDoCliente).
class Autonomia::Automacao::MensagemComOpcoes < Autonomia::Automacao::PassoDeMensagem
  LIMITE_DO_WHATSAPP = 10

  # `texto`: o convite ou a pergunta, já pronto. `opcoes`: os rótulos, na ordem. `numerar`: escrever as opções no texto
  # quando não houver botão (a pesquisa já diz "de 0 a 10" na pergunta).
  def initialize(execucao:, passo:, alvo:, texto:, opcoes:, numerar: true) # rubocop:disable Metrics/ParameterLists -- o passo e a pergunta
    super(execucao: execucao, passo: passo, alvo: alvo)
    @texto = texto
    @opcoes = opcoes
    @numerar = numerar
  end

  # Com botões: a conversa existe e o canal manda.
  def self.botoes?(conversa, quantas)
    canal = conversa&.inbox&.channel
    return true if canal.is_a?(::Channel::WebWidget)
    return false unless canal.is_a?(::Channel::Whatsapp) && canal.provider == 'whatsapp_cloud'

    quantas <= LIMITE_DO_WHATSAPP && !::WhatsappHybrid::Config.hybrid_inbox?(conversa.inbox_id)
  end

  # O texto sem botão: as opções numeradas embaixo, uma por linha.
  def self.numerado(texto, opcoes) = [texto, *opcoes.each_with_index.map { |opcao, i| "#{i + 1}. #{opcao}" }].join("\n")

  def parametros_da_mensagem(texto)
    return super unless botoes?

    itens = @opcoes.map { |opcao| { title: opcao, value: opcao } }
    { content: texto, private: false, content_type: 'input_select', content_attributes: marca.merge(items: itens) }
  end

  private

  def botoes? = self.class.botoes?(@conversa, @opcoes.size)

  def texto_pronto = botoes? || !@numerar ? @texto : self.class.numerado(@texto, @opcoes)
end
