# #1755: a leitura de memória do CRM (`Crm::Memoria::Leitor`, #1601) nos specs dos agentes, no formato combinado com o
# Multifunnel (objeto imutável com antes, agora_do_sistema, agora_fatos, ids e vazio?; cada Linha com id, chave,
# rotulo, valor, origem, em, message_id, card_id e status). O Leitor de verdade tem os próprios specs no lado do CRM.
module MemoriaIaHelper
  LinhaDaMemoria = Data.define(:id, :chave, :rotulo, :valor, :origem, :em, :message_id, :card_id, :status)
  LeituraDaMemoria = Data.define(:antes, :agora_do_sistema, :agora_fatos, :ids) do
    def vazio?
      [antes, agora_do_sistema, agora_fatos].all?(&:empty?)
    end
  end

  # Um fato do cliente por padrão (origem :cliente_informou, vigente, de 14/10/2026 13:02 UTC); os campos dados trocam.
  def linha_da_memoria(**campos)
    padrao = { id: nil, chave: 'fato', rotulo: 'fato', valor: '', origem: :cliente_informou,
               em: Time.zone.parse('2026-10-14 13:02 UTC'), message_id: nil, card_id: nil, status: :vigente }
    LinhaDaMemoria.new(**padrao, **campos)
  end

  def leitura_da_memoria(antes: [], agora_do_sistema: [], agora_fatos: [], ids: nil)
    LeituraDaMemoria.new(antes: antes, agora_do_sistema: agora_do_sistema, agora_fatos: agora_fatos,
                         ids: ids || (antes + agora_fatos).filter_map(&:id))
  end

  # O ponto único da flag (`Crm::Memoria.ligada?`) e o Leitor devolvendo `leitura`; `chamadas` guarda os argumentos.
  def memoria_do_crm(leitura, ligada: true, chamadas: [])
    stub_const('Crm::Memoria', Module.new { def self.ligada?(_account) = false })
    allow(Crm::Memoria).to receive(:ligada?).and_return(ligada)
    leitor = Class.new { def self.para(**) = nil }
    stub_const('Crm::Memoria::Leitor', leitor)
    allow(leitor).to receive(:para) do |**kwargs|
      chamadas << kwargs
      leitura
    end
    chamadas
  end
end

RSpec.configure { |config| config.include MemoriaIaHelper }
