# frozen_string_literal: true

# O artigo publicado da Central com o texto da variante do pacote da conta (#1802). Só leitura: título, texto e
# descrição saem da variante; o resto (capítulo, posição, rota do "Me leve até lá") é o do artigo publicado. Fica
# sem vídeo, e o `meta.central.pacote` diz de qual camada veio.
class Autonomia::CentralDeAjuda::ArtigoDoPacote < SimpleDelegator
  def initialize(artigo, variante)
    super(artigo)
    @variante = variante
  end

  def title = @variante.fonte.titulo
  def content = @variante.fonte.conteudo
  def description = @variante.fonte.descricao

  def meta
    publicado = __getobj__.meta.to_h
    publicado.merge('central' => publicado.fetch('central', {}).merge('pacote' => @variante.camada, 'video' => nil))
  end
end
