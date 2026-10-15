# Follow-up livre que a pessoa agenda para mais de 24 h (`auto_send_message`): decisão do Rodrigo de 15/10/2026, "IA
# encaixa num tipo". O Jev lê o texto que a pessoa escreveu e escolhe o tipo mais próximo (`Tipos`); se nenhum servir,
# nil, e o Followup avisa a equipe. Sem regex nem lista de palavras: quem decide é o modelo.
#
#   Whatsapp::Templates::EnvioForaDaJanela::Encaixe.call(account:, texto: 'Perguntar se a apólice chegou')  # => 'andamento'
#
# Depois, `EnvioForaDaJanela.planejar(tipo:)` dá o modelo reaproveitável do tipo, e `previa` o texto como vai sair, para
# a pessoa ver antes. O texto da pessoa vai ao Jev como dado e nunca para o log.
class Whatsapp::Templates::EnvioForaDaJanela::Encaixe
  Pergunta = Whatsapp::Templates::EnvioForaDaJanela::Pergunta
  MAX_TEXTO = 2_000
  PERGUNTA = 'A person wrote what an automatic WhatsApp message should say when it goes out later. Which kind of message is ' \
             'closest to what the person wants to send?'.freeze
  INSTRUCOES = 'Choose the kind whose purpose matches what the person wants to tell or ask the customer. Choose "nenhum" when ' \
               'no kind fits, or when the text only fits by stretching it: the team then writes the message by hand.'.freeze
  NENHUM_DESCRICAO = 'None of the kinds above: the message is about something else.'.freeze

  def self.call(account:, texto:)
    texto = texto.to_s.strip.first(MAX_TEXTO)
    return if texto.empty?

    respostas = Whatsapp::Templates::EnvioForaDaJanela::Tipos.todos.to_h { |tipo| [tipo.chave, tipo.proposito] }
    resposta = Pergunta.decidir(account: account, pergunta: PERGUNTA, instrucoes: INSTRUCOES,
                                respostas: respostas.merge(Pergunta::NENHUM => NENHUM_DESCRICAO), dados: { text: texto })
    # O Decisor já recusa chave fora da lista; a conferência aqui garante que nunca sai um tipo que `Tipos` não conhece.
    resposta if Whatsapp::Templates::EnvioForaDaJanela::Tipos::CATALOGO.key?(resposta)
  end
end
