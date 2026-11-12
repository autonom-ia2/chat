# O que a gaveta "Mais filtros" da Lista nova de Relacionamentos oferece (#2894): só etiquetas e cidades que existem nas
# pessoas da conta, e as empresas (do Enterprise). Sem paginação, no formato { value, label } da tela.
class Relacionamentos::OpcoesDeFiltro
  CIDADE = Arel.sql("contacts.additional_attributes->>'city'")

  def initialize(account)
    @account = account
  end

  def call
    { empresas: empresas, etiquetas: como_opcoes(etiquetas), cidades: como_opcoes(cidades) }
  end

  private

  def pessoas
    Relacionamentos::ConsultaDePessoas.base(@account)
  end

  def etiquetas
    das_pessoas = { taggable_type: 'Contact', context: 'labels', tagger_id: nil, taggable_id: pessoas.select(:id) }
    ActsAsTaggableOn::Tag.joins(:taggings).where(taggings: das_pessoas).distinct.pluck(:name)
  end

  def cidades
    pessoas.where("#{CIDADE} <> ''").distinct.pluck(CIDADE)
  end

  def empresas
    []
  end

  # Na ordem em que a tela ordena estas duas listas (a do texto puro), que não depende da collation do banco.
  def como_opcoes(valores)
    valores.sort.map { |valor| { value: valor, label: valor } }
  end
end

Relacionamentos::OpcoesDeFiltro.prepend_mod_with('Relacionamentos::OpcoesDeFiltro')
