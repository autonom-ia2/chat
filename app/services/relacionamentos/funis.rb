# Os funis ativos com as etapas, na ordem do quadro, para o "Criar cards" da Lista nova de Relacionamentos (#2894): tudo
# numa leitura só (o CRM entrega o funil numa chamada e as etapas de cada um em outra). Recebe os funis que a pessoa
# enxerga.
class Relacionamentos::Funis
  def initialize(funis)
    @funis = funis
  end

  def call
    @funis.active.order(:position, :id).preload(:stages).map do |funil|
      { id: funil.id, nome: funil.name, etapas: etapas(funil) }
    end
  end

  private

  def etapas(funil)
    funil.stages.sort_by { |etapa| [etapa.position, etapa.id] }.map { |etapa| { id: etapa.id, nome: etapa.name } }
  end
end
