class LlmFormatter::ContactLlmFormatter < LlmFormatter::DefaultLlmFormatter
  def format(*)
    sections = []
    sections << "Contact ID: ##{@record.id}"
    sections << 'Contact Attributes:'
    sections << build_attributes
    sections << 'Contact Notes:'
    sections << if @record.notes.any?
                  build_notes
                else
                  'No notes for this contact'
                end

    sections.join("\n")
  end

  private

  def build_notes
    @record.notes.all.map { |note| " - #{note.content}" }.join("\n")
  end

  def build_attributes
    attributes = []
    attributes << "Name: #{@record.name}"
    attributes << "Email: #{@record.email}"
    attributes << "Phone: #{@record.phone_number}"
    attributes << "Location: #{@record.location}"
    attributes << "Country Code: #{@record.country_code}"
    @record.account.custom_attribute_definitions.with_attribute_model('contact_attribute').each do |attribute|
      attributes << "#{rotulo(attribute)}: #{@record.custom_attributes[attribute.attribute_key]}"
    end
    attributes.join("\n")
  end

  # #3082: o nome do campo e, quando a conta escreveu, o "Para que serve", que a tela avisa que a IA lê.
  def rotulo(attribute)
    proposito = attribute.attribute_description.to_s.squish.first(300)
    proposito.present? ? "#{attribute.attribute_display_name} (#{proposito})" : attribute.attribute_display_name
  end
end
