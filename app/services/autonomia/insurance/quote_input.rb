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

  def de_auto
    {
      'insured' => { 'document' => digitos('cpf') }.merge(nome_do_segurado),
      'address' => { 'zipCode' => digitos('cep'), 'number' => texto('numero') }.compact,
      'vehicle' => { 'plate' => @params['placa'].to_s }
    }.merge(renewal.to_input)
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
