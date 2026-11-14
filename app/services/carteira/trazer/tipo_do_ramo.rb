# "Trazer minha lista" com seguros (E4, #2897): o tipo de cada ramo escrito na planilha. A pessoa não mapeia nada: o
# tipo já aparece pronto na conferência e ela corrige depois, na gaveta do seguro, se quiser.
#
# Na leitura da planilha (`resolver`, fora da trava da importação, porque pode chamar o modelo), cada ramo distinto é
# resolvido nesta ordem, e o que já tem resposta não é perguntado de novo:
# 1. o que esta importação já resolveu numa leitura anterior;
# 2. o que a CONTA já tem: as apólices guardadas com o mesmo ramo (`ramo_original`) dizem o tipo, o mais frequente. A
#    correção feita à mão conta, porque é o que a corretora quer. `outro` não conta: pode ter vindo de uma falha do
#    modelo, e a pergunta é refeita;
# 3. o modelo (Carteira::Trazer::PerguntaDoRamo), com os que sobraram.
#
# O resultado fica em `options['trazer']['tipos_do_ramo']` como { chave => tipo }. A `chave` é o resumo do ramo com um
# segredo e o id da importação (o mesmo desenho de ContactImports::Trazer::Cliente): o texto da célula nunca fica nas
# opções da importação. O ramo sem resposta (o modelo falhou) não é guardado e é `outro` até a próxima leitura.
#
# Só texto com cara de ramo vai ao modelo. Se a pessoa apontou a coluna errada (nomes, telefones, e-mails), nada sai
# daqui: coluna com valores distintos demais não é perguntada, nem valor comprido, com muitos dígitos ou com "@".
class Carteira::Trazer::TipoDoRamo
  CHAVE = 'tipos_do_ramo'.freeze
  OUTRO = 'outro'.freeze
  SAL = 'carteira/trazer/tipo_do_ramo'.freeze
  SEPARADOR = "\0".freeze
  # Uma corretora trabalha com poucas dezenas de ramos. Mais do que isso não é coluna de ramo.
  RAMOS_DISTINTOS = 80
  # "0531 - Automóvel" tem quatro dígitos; telefone, documento e apólice têm mais.
  DIGITOS = 4
  TAMANHO = 60
  ARROBA = '@'.freeze

  class << self
    # Sem espaço sobrando e sem diferença de maiúscula: "AUTOMÓVEL " e "Automóvel" são o mesmo ramo.
    def agrupado(texto)
      ContactImports::Trazer::Cliente.agrupado(texto)
    end

    def chave(importacao_id, texto)
      OpenSSL::HMAC.hexdigest('SHA256', segredo, [Integer(importacao_id), agrupado(texto)].join(SEPARADOR))
    end

    def segredo
      @segredo ||= Rails.application.key_generator.generate_key(SAL, 32)
    end
  end

  def initialize(importacao, pergunta: nil)
    @importacao = importacao
    @pergunta = pergunta
  end

  # O tipo com que o seguro deste ramo é gravado e mostrado.
  def de(texto)
    return OUTRO if texto.blank?

    guardados.fetch(self.class.chave(@importacao.id, texto), OUTRO)
  end

  # textos: o que as linhas trazem na coluna do ramo. Devolve { chave => tipo } para guardar: o que já estava e o novo.
  def resolver(textos)
    faltam = distintos(textos).reject { |ramo| guardados.key?(self.class.chave(@importacao.id, ramo)) }
    return guardados if faltam.empty?

    da_conta = tipos_da_conta.slice(*faltam)
    novos = da_conta.merge(pergunta.call(perguntaveis(faltam - da_conta.keys)))
    guardados.merge(novos.transform_keys { |ramo| self.class.chave(@importacao.id, ramo) })
  end

  private

  def distintos(textos)
    textos.filter_map { |texto| self.class.agrupado(texto).presence }.uniq
  end

  def perguntaveis(ramos)
    return [] if ramos.size > RAMOS_DISTINTOS

    ramos.select { |ramo| ramo.length <= TAMANHO && ramo.count('0-9') <= DIGITOS && ramo.exclude?(ARROBA) }
  end

  # { ramo agrupado => o tipo mais frequente nas apólices da conta }. No empate, o primeiro em ordem alfabética.
  def tipos_da_conta
    contagem = Carteira::Apolice.where(account_id: @importacao.account_id).where.not(ramo_original: nil).where.not(tipo: OUTRO)
                                .group(:ramo_original, :tipo).count
    por_ramo = contagem.group_by { |(ramo, _tipo), _quantas| self.class.agrupado(ramo) }
    por_ramo.transform_values { |pares| mais_frequente(pares) }
  end

  def mais_frequente(pares)
    somas = pares.each_with_object(Hash.new(0)) { |((_ramo, tipo), quantas), soma| soma[tipo] += quantas }
    somas.min_by { |tipo, quantas| [-quantas, tipo] }.first
  end

  def guardados
    @guardados ||= @importacao.options.to_h.dig(ContactImports::Trazer::Conferencia::CHAVE, CHAVE).to_h
  end

  def pergunta
    @pergunta ||= Carteira::Trazer::PerguntaDoRamo.new(account: @importacao.account)
  end
end
