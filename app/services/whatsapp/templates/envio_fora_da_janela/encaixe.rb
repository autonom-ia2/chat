# Follow-up livre que a pessoa agenda para mais de 24 h (`auto_send_message`): decisão do Rodrigo de 15/10/2026, "IA
# encaixa num tipo". O Jev lê o texto que a pessoa escreveu e escolhe o tipo mais próximo (`Tipos`); se nenhum servir,
# nil, e o Followup avisa a equipe. Sem regex nem lista de palavras: quem decide é o modelo.
#
#   Whatsapp::Templates::EnvioForaDaJanela::Encaixe.call(account:, texto: 'Perguntar se a apólice chegou')  # => 'andamento'
#
# Depois, `EnvioForaDaJanela.planejar(tipo:)` dá o modelo reaproveitável do tipo, e `previa` o texto como vai sair, para
# a pessoa ver antes. O texto da pessoa vai ao Jev como dado e nunca para o log.
#
# Chamada paga que pode vir da requisição do painel: a resposta fica no cache por 24 h, por conta e pelo SHA-256 do texto
# (sem os espaços das pontas), também quando é "nenhum". Jev sem chave ou fora do ar não entra no cache.
class Whatsapp::Templates::EnvioForaDaJanela::Encaixe
  Pergunta = Whatsapp::Templates::EnvioForaDaJanela::Pergunta
  Tipos = Whatsapp::Templates::EnvioForaDaJanela::Tipos
  MAX_TEXTO = 2_000
  CACHE_TTL = 24.hours
  CACHE_VERSAO = 'v1'.freeze
  PERGUNTA = 'A person wrote what an automatic WhatsApp message should say when it goes out later. Which kind of message is ' \
             'closest to what the person wants to send?'.freeze
  INSTRUCOES = 'Choose the kind whose purpose matches what the person wants to tell or ask the customer. Choose "nenhum" when ' \
               'no kind fits, or when the text only fits by stretching it: the team then writes the message by hand.'.freeze
  NENHUM_DESCRICAO = 'None of the kinds above: the message is about something else.'.freeze

  def self.call(account:, texto:)
    texto = texto.to_s.strip.first(MAX_TEXTO)
    return if texto.empty?

    chave = chave_do_cache(account, texto)
    resposta = Rails.cache.read(chave) || perguntar(account, texto, chave)
    resposta if Tipos::CATALOGO.key?(resposta)
  end

  # Guarda o tipo ou "nenhum" (sentinela); o Decisor já recusa chave fora da lista, e a conferência aqui garante que
  # nunca sai nem fica guardado um tipo que `Tipos` não conhece.
  def self.perguntar(account, texto, chave)
    respostas = Tipos.todos.to_h { |tipo| [tipo.chave, tipo.proposito] }.merge(Pergunta::NENHUM => NENHUM_DESCRICAO)
    resposta = Pergunta.decidir(account: account, pergunta: PERGUNTA, instrucoes: INSTRUCOES, respostas: respostas,
                                dados: { text: texto })
    return if resposta.nil?

    guardada = Tipos::CATALOGO.key?(resposta) ? resposta : Pergunta::NENHUM
    Rails.cache.write(chave, guardada, expires_in: CACHE_TTL)
    guardada
  end

  def self.chave_do_cache(account, texto)
    ['whatsapp_fora_da_janela', 'encaixe', CACHE_VERSAO, account.id, Digest::SHA256.hexdigest(texto)].join(':')
  end
  private_class_method :perguntar, :chave_do_cache
end
