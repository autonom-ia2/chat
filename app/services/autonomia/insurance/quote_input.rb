# A ENTRADA DE UMA COTAÇÃO, montada a partir do que o agente informou.
#
# Existe separada da ferramenta porque são dois trabalhos: orquestrar a cotação (validar, submeter,
# consultar, entregar) e traduzir o que o modelo escreveu para o formato que o adapter espera. A
# ferramenta ficava com os dois e passava de 175 linhas — e, mais do que o número, misturar os dois
# faz cada mudança de campo mexer no arquivo que também decide o que vai para o cliente.
#
# DUAS FORMAS, e é a única coisa que auto tem de diferente:
#   auto  -> `insured` / `address` / `vehicle`, porque o adapter resolve placa e FIPE antes de
#            montar o corpo, e enriquece o segurado por CPF;
#   demais -> `segurado` + `configuracoes`, que é onde `contratoCapturado` e `contratoGenerico` leem
#            os campos do ramo. Escrevê-los no topo do objeto não chega ao portal.
class Autonomia::Insurance::QuoteInput
  AUTO = 'auto'.freeze

  def initialize(produto:, params:, dados:, commission_percent:)
    @produto = produto
    @params = params
    @dados = dados
    @commission_percent = commission_percent
  end

  def to_h
    (auto? ? de_auto : de_ramo).merge('commissionPercent' => @commission_percent)
  end

  # Tudo o que muda quando o cliente já tem seguro mora aqui — inclusive as armadilhas do bônus.
  def renewal
    @renewal ||= ::Autonomia::Insurance::AutoRenewal.new(@params)
  end

  def auto?
    @produto == AUTO
  end

  private

  # OS GRUPOS DO ADAPTER, na forma em que o adapter os lê. Entrega 2: o modelo escreve o bloco
  # (`vehicle: { plate: ..., garageAtHome: ... }`) e o bloco vai como veio — sem tradução, sem lista
  # de nomes que envelheça. `nil` e vazio saem (o modelo manda `null` no que não sabe; o adapter
  # aplica os padrões dele); `false` e `0` ficam, porque são resposta.
  #
  # Os parâmetros comuns (`cpf`, `nome`, `cep`, `numero`) continuam valendo em auto como ATALHO —
  # o modelo pode escrever o CPF em qualquer dos dois lugares — e o bloco aninhado vence quando os
  # dois vêm.
  GRUPOS_DE_AUTO = %w[insured address vehicle driver truck coverage quotation].freeze

  def de_auto
    grupos = GRUPOS_DE_AUTO.index_with { |grupo| sem_vazios(@params[grupo]) }
    grupos['insured'] = segurado_de_auto.merge(grupos['insured'])
    grupos['address'] = endereco_de_auto.merge(grupos['address'])
    grupos.reject { |_, valor| valor.blank? }
  end

  def segurado_de_auto
    { 'document' => digitos('cpf').presence }.merge(nome_do_segurado).compact
  end

  def endereco_de_auto
    { 'zipCode' => digitos('cep').presence, 'number' => texto('numero') }.compact
  end

  # Só o que o modelo informou: `nil` e `''` são "não sei"; `false` e `0` são resposta.
  def sem_vazios(valor)
    return {} unless valor.is_a?(Hash)

    valor.each_with_object({}) do |(chave, item), saida|
      limpo = item.is_a?(Hash) ? sem_vazios(item) : item
      saida[chave.to_s] = limpo unless vazio?(limpo)
    end
  end

  def vazio?(valor)
    valor.nil? || valor == '' || (valor.is_a?(Hash) && valor.empty?)
  end

  # VAZIO NUNCA SOBRESCREVE. O JSON vence o parâmetro quando traz valor — é o mais específico, e o
  # modelo o escreveu de propósito —, mas `{"segurado":{"cpfCnpj":""}}` apagaria o CPF que veio no
  # parâmetro, e o portal recusaria uma cotação que tinha tudo. `compact_blank` é o que separa
  # "informou outro valor" de "mandou a chave vazia".
  def de_ramo
    base = @dados.to_h
    informado = segurado_dos_parametros.merge(base['segurado'].to_h.compact_blank)
    informado.any? ? base.merge('segurado' => informado) : base
  end

  # Os nomes que `SeguradoDaCotacao` usa no adapter — `cpfCnpj`, e não `document`.
  def segurado_dos_parametros
    { 'cpfCnpj' => digitos('cpf').presence, 'nome' => texto('nome'),
      'cep' => digitos('cep').presence, 'numero' => texto('numero') }.compact
  end

  def nome_do_segurado
    nome = texto('nome')
    nome ? { 'name' => nome } : {}
  end

  def digitos(campo)
    @params[campo].to_s.gsub(/\D/, '')
  end

  def texto(campo)
    @params[campo].to_s.presence
  end
end
