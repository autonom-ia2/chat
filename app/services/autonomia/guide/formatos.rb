# O formato de cada ação de escrita do Guia, gerado do código (#900).
#
# O Guia opera a conta chamando a API como a pessoa, mas não sabia o que cada
# ação aceita: chutava nome de campo, e em produção a chave que o `permit` não
# conhece é descartada em silêncio — a resposta é 200 e nada muda. A recusa de
# validação também não ajuda: "Permissions is not included in the list" não
# diz qual lista.
#
# O formato sai do próprio código — strong params, `wrap_parameters` e
# validações do modelo — por um gerador no build (`Gerador`), e fica
# versionado em `lib/operator_guide/formatos-das-acoes.json`, revisável no PR.
# Em execução o Guia só LÊ esse arquivo: nada de Prism nem de instanciar
# controller numa requisição.
#
# Mexeu em controller, strong params ou validação de um recurso que o Guia
# alcança? `bundle exec rails autonomia:guia:formatos` e envie o resultado; o
# spec do formato falha no CI quando o versionado fica fora de dia.
module Autonomia::Guide::Formatos
  ARQUIVO = Rails.root.join('lib/operator_guide/formatos-das-acoes.json')
  RELATORIO = Rails.root.join('lib/operator_guide/formatos-das-acoes-cobertura.md')

  module_function

  # O formato de uma ação do catálogo ('POST custom_roles'), ou nil.
  def para(acao)
    todos[acao.to_s]
  end

  # O formato em texto curto, para o modelo montar o corpo certo de primeira.
  def resumo_para_o_modelo(acao)
    formato = para(acao)
    formato && Resumo.new(acao.to_s, formato).texto
  end

  def todos
    @todos ||= JSON.parse(ARQUIVO.read).freeze
  end

  # O que o código diz agora, nos dois arquivos versionados.
  def gerados
    formatos = Gerador.new.formatos
    { ARQUIVO => json(formatos), RELATORIO => Relatorio.new(formatos).texto }
  end

  def escrever!
    gerados.each { |arquivo, conteudo| File.write(arquivo, conteudo) }
    @todos = nil
  end

  # Os arquivos versionados que não batem com o código.
  def fora_de_dia
    gerados.reject { |arquivo, conteudo| File.exist?(arquivo) && File.read(arquivo) == conteudo }.keys
  end

  def json(formatos)
    "#{JSON.pretty_generate(ordenado(formatos))}\n"
  end

  # Chaves sempre em ordem: a mesma entrada gera o mesmo arquivo, e o diff do
  # PR mostra só o que mudou de verdade.
  def ordenado(valor)
    case valor
    when Hash then valor.sort_by { |chave, _| chave.to_s }.to_h { |chave, item| [chave.to_s, ordenado(item)] }
    when Array then valor.map { |item| ordenado(item) }
    else valor
    end
  end
end
