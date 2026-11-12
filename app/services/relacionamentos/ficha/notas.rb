# As notas da ficha da pessoa de Relacionamentos (#2895) no formato da tela, das mais novas para trás: quem escreveu,
# quando e o texto. Nota de quem já saiu da plataforma vem sem autor.
class Relacionamentos::Ficha::Notas
  def initialize(pessoa)
    @pessoa = pessoa
  end

  def call
    @pessoa.notes.latest.order(id: :desc).preload(:user).map do |nota|
      { id: nota.id, autor: nota.user&.name, quando: nota.created_at.to_i, texto: nota.content }
    end
  end
end
