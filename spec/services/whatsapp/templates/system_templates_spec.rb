require 'rails_helper'

# Modelos que a plataforma usa (#1330): agendamento (nomes do Catalog), anúncios e satisfação; o resto é da pessoa.
RSpec.describe Whatsapp::Templates::SystemTemplates do
  it 'reconhece os avisos do agendamento pelos nomes do Catalog' do
    expect(Crm::BookingV2::NoticeTemplates::Catalog.names).to eq(
      Crm::BookingV2::NoticeTemplates::Catalog.kinds.map { |kind| Crm::BookingV2::NoticeTemplates::Catalog.name_for(kind) }
    )
    Crm::BookingV2::NoticeTemplates::Catalog.names.each { |name| expect(described_class.owner_for(name)).to eq('agendamento') }
  end

  it 'reconhece o resumo e o alerta de anúncios e a pesquisa de satisfação de qualquer caixa' do
    expect(described_class.owner_for('chat2you_resumo_anuncios')).to eq('anuncios')
    expect(described_class.owner_for('chat2you_alerta_anuncio')).to eq('anuncios')
    expect(described_class.owner_for(CsatTemplateNameService.csat_template_name(42, 3))).to eq('satisfacao')
  end

  it 'reconhece os prontos por finalidade que o Garantir cria (#1518)' do
    Whatsapp::Templates::Finalidades.prontos.each { |pronto| expect(described_class.owner_for(pronto.nome)).to eq(pronto.dono) }
  end

  # Motivo (#1524): os avisos v2 com botões ficam protegidos na tela de Modelos como do agendamento, como os v1.
  it 'reconhece os avisos v2 do agendamento' do
    %w[agendamento_ao_marcar_v2 agendamento_horario_mudou_v2 agendamento_1_dia_antes_v2 agendamento_1_hora_antes_v2].each do |name|
      expect(described_class.owner_for(name)).to eq('agendamento'), name
    end
  end

  it 'modelo da pessoa não é do sistema' do
    expect(described_class.system?('boas_vindas')).to be(false)
    expect(described_class.system?(nil)).to be(false)
  end
end
