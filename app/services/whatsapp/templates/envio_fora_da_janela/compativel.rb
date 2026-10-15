# "Compatível" = decisão do Jev (#1587, sem regex nem lista de palavras): entram o propósito do tipo, os campos que ele
# usa e os aprovados da caixa que as regras deixam usar (`Candidatos`); sai o nome de um deles ou "nenhum".
#
# Barato para o pré-voo e o envio chamarem o mesmo plano: a resposta fica no cache por (caixa, tipo, propósito, campos) e pela
# lista exata de candidatos (nome, idioma, categoria, texto, campos). Modelo novo, editado ou recategorizado muda a
# chave e pergunta de novo. Jev fora do ar não entra no cache.
class Whatsapp::Templates::EnvioForaDaJanela::Compativel
  Pergunta = Whatsapp::Templates::EnvioForaDaJanela::Pergunta
  CACHE_TTL = 7.days
  CACHE_VERSAO = 'v1'.freeze
  PERGUNTA = 'Which approved WhatsApp template can be sent, exactly as it is, for the purpose in the state?'.freeze
  INSTRUCOES = 'A template fits only when its fixed text says what the purpose needs and nothing that would be false, ' \
               'off-topic or a sales pitch the purpose does not ask for. The [brackets] are filled with the customer data. ' \
               'Choose "nenhum" when no template fits, or when one only fits in part.'.freeze
  NENHUM_DESCRICAO = 'No template fits this purpose.'.freeze

  def initialize(inbox:, tipo:, candidatos:)
    @inbox = inbox
    @tipo = tipo
    @candidatos = candidatos
  end

  # -> Candidatos::Candidato ou nil
  def call
    return if @candidatos.empty?

    nome = Rails.cache.read(chave_do_cache) || perguntar
    return if nome.nil? || nome == Pergunta::NENHUM

    @candidatos.find { |candidato| candidato.nome == nome }
  end

  private

  def perguntar
    resposta = Pergunta.decidir(account: @inbox.account, pergunta: PERGUNTA, instrucoes: INSTRUCOES, respostas: respostas,
                                dados: { purpose: @tipo.proposito, purpose_category: @tipo.categoria })
    Rails.cache.write(chave_do_cache, resposta, expires_in: CACHE_TTL) if resposta
    resposta
  end

  # A chave de cada resposta é o nome do modelo (a-z, 0-9 e "_"); um modelo chamado "nenhum" não concorre.
  def respostas
    @candidatos.reject { |candidato| candidato.nome == Pergunta::NENHUM }
               .to_h { |candidato| [candidato.nome, descricao(candidato)] }
               .merge(Pergunta::NENHUM => NENHUM_DESCRICAO)
  end

  # O texto com o rótulo de cada campo no lugar do número: "Oi, [Primeiro nome do cliente]! ...".
  def descricao(candidato)
    texto = Ai::Redacao::Chaves.preencher(candidato.texto) do |posicao|
      "[#{TemplateFields::Catalog.label(candidato.campos[posicao], locale: :pt_BR)}]"
    end
    "Template (#{candidato.categoria.downcase}): \"#{texto}\""
  end

  def chave_do_cache
    @chave_do_cache ||= begin
      lista = @candidatos.map { |candidato| [candidato.nome, candidato.idioma, candidato.categoria, candidato.texto, candidato.campos] }
      digest = Digest::SHA256.hexdigest([@tipo.proposito, @tipo.categoria, @tipo.campos, lista].to_json)
      ['whatsapp_fora_da_janela', 'compativel', CACHE_VERSAO, @inbox.id, @tipo.chave, digest].join(':')
    end
  end
end
