# Jev's answer on the country of the phone column (#1246, customer_base reading). The ninth digit is
# added to a 10-digit number without country code only when, for the very column used as phone, Jev
# said "brazil" with confidence and found the table's contact columns (schema_probability). With
# "other", "unknown", no answer, low confidence or another column the number is refused as before.
# After a manual column choice the answer comes from the reading Jev did before (previous resolution),
# and still counts only if the person kept the column Jev judged.
class CampaignImports::PhoneCountry
  MIN_CONFIDENCE = TypesafeAi::ImportSchemaResolver::MIN_MAPPING_CONFIDENCE
  SCHEMA_ACCEPTANCE_THRESHOLD = TypesafeAi::ImportSchemaResolver::SCHEMA_ACCEPTANCE_THRESHOLD

  def self.from(resolution, previous_resolution, phone_index)
    jev = resolution['method'] == 'manual' ? previous_resolution['jev'] : resolution['jev']
    new(jev.to_h, phone_index)
  end

  def initialize(jev, phone_index)
    @jev = jev
    @answer = jev['phone_country'].to_h
    @phone_index = phone_index
  end

  def brazil?
    @answer['value'] == 'brazil' && @answer['confidence'].to_f >= MIN_CONFIDENCE &&
      @jev['schema_probability'].to_f > SCHEMA_ACCEPTANCE_THRESHOLD && !@phone_index.nil? && @answer['column'] == @phone_index
  end

  # row_results: every row the validator read (CampaignImports::AudienceRowContacts fields included).
  def summary(row_results)
    {
      phone_country: @answer['value'] || 'not_answered',
      ninth_digit_added: row_results.count { |row| row[:errors].blank? && row[:ninth_digit_added] },
      legacy_mobiles_refused: row_results.count { |row| row[:legacy_mobile_refused] }
    }
  end
end
