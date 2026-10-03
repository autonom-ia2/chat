# O que a plataforma respondeu a uma ação, lido com o formato dela (#900). As
# duas saídas são para o modelo, nunca para a tela da pessoa.
class Autonomia::Guide::Formatos::Retorno
  def initialize(acao, resposta)
    @acao = acao.to_s
    @formato = ::Autonomia::Guide::Formatos.para(@acao)
    @dados = ler(resposta)
  end

  # Na recusa: o que o formato sabe de cada campo recusado. O 422 de validação
  # traz `attributes`, e o de parâmetro ausente traz o nome no fim do `error`
  # ("...: custom_role"). "Permissions is not included in the list" sozinho não
  # diz qual lista; com isto, diz.
  def dica
    return unless @formato && @dados.is_a?(Hash)

    resumo = ::Autonomia::Guide::Formatos::Resumo.new(@acao, @formato)
    linhas = recusados.filter_map do |nome|
      nome == @formato['envelope'] ? "os campos vão dentro de \"#{nome}\"" : resumo.campo(nome)
    end
    "O formato diz: #{linhas.join(' | ')}" if linhas.any?
  end

  # No sucesso: no formato parcial a chave desconhecida passa (pode existir sem
  # o gerador ter visto). Se ela não voltou no registro, a plataforma
  # provavelmente a descartou calada — e o modelo precisa saber antes de dizer
  # que fez.
  def descartadas(conferencia)
    return if conferencia.completo? || conferencia.desconhecidas.empty?

    faltam = conferencia.desconhecidas - chaves(@dados)
    return if faltam.empty?

    "não voltaram no registro: #{faltam.join(', ')}. Esta ação não lista esses campos; a plataforma " \
      'provavelmente os descartou. Não diga que gravou.'
  end

  private

  def ler(resposta)
    JSON.parse(resposta.corpo.to_s)
  rescue JSON::ParserError
    nil
  end

  # `channel.webhook_url` vira `channel`: o formato descreve o primeiro nível.
  def recusados
    nomes = Array(@dados['attributes']).map { |nome| nome.to_s.split('.').first }
    erro = @dados['error']
    nomes << erro.split(': ').last.to_s.lines.first.to_s.strip if erro.is_a?(String) && erro.include?(': ')
    nomes.uniq
  end

  def chaves(valor)
    case valor
    when Hash then valor.keys + valor.values.flat_map { |item| chaves(item) }
    when Array then valor.flat_map { |item| chaves(item) }
    else []
    end
  end
end
