# A limpeza diária das leituras de PDF da carteira (E6, #2899; config/schedule.yml). Os itens guardam dado de cliente (o
# que foi lido e o PDF) e saem quando a guarda vence (Carteira::Leitura::DIAS_DE_GUARDA_DOS_ITENS):
# - do lote de Trazer por PDFs saem só os itens. O lote fica, sem dado de cliente (só contagens), porque é por ele que
#   as apólices que ele criou se ligam e o Desfazer as acha;
# - a leitura do anexar que ninguém terminou e o lote que ficou no Conferir sem ser trazido saem inteiros: não criaram
#   nada.
# Sempre com `destroy`, em lote pequeno, para o PDF de cada item sair junto (a cascata do banco não apaga arquivo).
# Rodar de novo é seguro: o que saiu não existe mais.
class Carteira::LimpezaDasLeiturasJob < ApplicationJob
  queue_as :scheduled_jobs
  BLOCO = 100
  # O lote que nunca saiu do Conferir.
  NAO_TRAZIDO = %w[lendo lida].freeze

  def perform
    agora = Time.current
    Carteira::LeituraItem.vencidos(agora).find_each(batch_size: BLOCO, &:destroy!)
    trazidos = Carteira::Leitura.do_trazer.where.not(estado: NAO_TRAZIDO)
    Carteira::Leitura.com_a_guarda_vencida(agora).where(origem: 'pdf').where.not(id: trazidos.select(:id))
                     .find_each(batch_size: BLOCO, &:destroy!)
  end
end
