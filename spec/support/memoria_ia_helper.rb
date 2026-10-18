# #1755: a leitura de memória do CRM (`Crm::Memoria::Leitor`, #1601) nos specs dos agentes, com as classes de verdade do
# contrato (Leitura e Linha). Só o `Leitor.para` é dublado; o Leitor tem os próprios specs no lado do CRM.
module MemoriaIaHelper
  # Um fato do cliente por padrão (origem :cliente_informou, vigente, de 14/10/2026 13:02 UTC); os campos dados trocam.
  def linha_da_memoria(**campos)
    padrao = { id: nil, chave: 'fato', rotulo: 'fato', valor: '', origem: :cliente_informou,
               em: Time.zone.parse('2026-10-14 13:02 UTC'), message_id: nil, card_id: nil, status: :vigente }
    Crm::Memoria::Leitor::Linha.new(**padrao, **campos)
  end

  def leitura_da_memoria(antes: [], agora_do_sistema: [], agora_fatos: [], ids: nil, card_em_foco_id: nil)
    Crm::Memoria::Leitor::Leitura.new(antes: antes, agora_do_sistema: agora_do_sistema, agora_fatos: agora_fatos,
                                      ids: ids || (antes + agora_fatos).filter_map(&:id), card_em_foco_id: card_em_foco_id)
  end

  # O Leitor devolvendo `leitura`; `chamadas` guarda os argumentos.
  def memoria_do_crm(leitura, chamadas: [])
    allow(Crm::Memoria::Leitor).to receive(:para) do |**kwargs|
      chamadas << kwargs
      leitura
    end
    chamadas
  end
end

RSpec.configure { |config| config.include MemoriaIaHelper }
