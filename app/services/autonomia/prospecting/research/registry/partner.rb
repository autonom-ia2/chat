# Um membro do quadro de sócios (QSA), só com o que a pesquisa usa. Dos campos de pessoa física que as fontes mandam
# (CPF mascarado, faixa etária, país, representante legal e a qualificação dele), nenhum entra aqui: a faixa etária vira
# is_minor e é jogada fora.
#
# qualification é o rótulo da Research::Qualification; qualification_key, a forma normalizada que a regra do dono compara.
# person_type: 'PF', 'PJ' ou 'UNKNOWN' (estrangeiro ou tipo não documentado, nunca promovido a PF).
Autonomia::Prospecting::Research::Registry::Partner = Data.define(
  :name, :qualification, :qualification_key, :person_type, :is_minor, :entered_on
) do
  def self.build(name:, qualification:, person_type:, is_minor: false, entered_on: nil)
    new(name: name, qualification: Autonomia::Prospecting::Research::Qualification.label(qualification),
        qualification_key: Autonomia::Prospecting::Research::Qualification.key(qualification),
        person_type: person_type, is_minor: is_minor == true, entered_on: entered_on)
  end

  def natural_person? = person_type == 'PF'

  def company? = person_type == 'PJ'

  # Forma gravável. Pessoa (PF ou tipo desconhecido) passa pela lista fechada; empresa sócia leva o tipo junto.
  def storable
    entry = { 'name' => name, 'qualification' => qualification, 'entered_on' => entered_on&.iso8601 }
    return entry.merge('person_type' => 'PJ') if company?

    Autonomia::Prospecting::Research::PersonFields.storable!(entry)
  end
end
