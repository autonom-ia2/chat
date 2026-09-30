class TypesafeAi::ImportSchemaResolver
  Error = Class.new(StandardError)
  NONE = 'none'.freeze

  def initialize(client: TypesafeAi::Client.new, model: TypesafeAi::Config.model)
    @client = client
    @model = model
  end

  def resolve(candidate)
    validate_width!(candidate)
    response = @client.evaluate(
      model: @model,
      state: state_for(candidate),
      questions: questions_for(candidate)
    )
    build_resolution(candidate, response)
  rescue KeyError, TypeError, NoMethodError
    raise Error, 'typesafe_invalid_response'
  rescue TypesafeAi::Client::Error => e
    raise Error, e.code
  end

  private

  def validate_width!(candidate)
    raise Error, 'schema_too_wide' if candidate.fetch(:headers).size > 254
  end

  def state_for(candidate)
    {
      task: 'Map a recipient-list header to the email and optional name fields, then certify whether the mapping is usable.',
      header_row: candidate.fetch(:header_row_number),
      headers: candidate.fetch(:headers),
      profiles: candidate.fetch(:profiles)
    }
  end

  def questions_for(candidate)
    criteria = column_criteria(candidate)
    {
      email_column: choice_question(
        'Which column contains the recipient email address? Choose none only if there is no email column.',
        criteria.merge(NONE => 'No column contains recipient email addresses.')
      ),
      name_column: choice_question(
        'Which column contains the recipient person or contact name? Name is optional.',
        criteria.merge(NONE => 'There is no recipient-name column. Name is optional.')
      ),
      schema_valid: {
        type: 'noul',
        instructions: 'Does this header describe a usable email-recipient table with an identifiable email column?',
        criteria: {
          true => 'There is an identifiable recipient email column.',
          false => 'No recipient email column can be identified reliably.'
        }
      }
    }
  end

  def column_criteria(candidate)
    candidate.fetch(:headers).each_with_index.to_h do |header, index|
      ["column_#{index}", { header: header, profile: candidate.fetch(:profiles).fetch(index) }]
    end
  end

  def choice_question(instructions, criteria)
    { type: 'choice', instructions: instructions, criteria: criteria }
  end

  def build_resolution(candidate, response)
    answers = response.fetch('answers')
    email_answer = answers.fetch('email_column')
    name_answer = answers.fetch('name_column')
    schema_answer = answers.fetch('schema_valid')
    validate_answers!(response, email_answer, name_answer, schema_answer)
    email_index = resolved_email_index(candidate, email_answer)
    raise Error, 'schema_not_resolved' unless schema_answer.fetch('noul') > 0.5

    name_index = resolved_name_index(candidate, name_answer)
    raise Error, 'schema_not_resolved' if email_index == name_index

    {
      candidate_id: candidate.fetch(:id),
      email_index: email_index,
      name_index: name_index,
      metadata: metadata_for(response, email_answer, name_answer, schema_answer)
    }
  end

  def validate_answers!(response, email_answer, name_answer, schema_answer) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- typed provider boundary
    valid = response.fetch('model') == @model && email_answer.fetch('type') == 'choice' && name_answer.fetch('type') == 'choice' &&
            schema_answer.fetch('type') == 'noul' &&
            [email_answer.fetch('confidence'), name_answer.fetch('confidence'), schema_answer.fetch('noul')].all? do |value|
              value.is_a?(Numeric) && value.finite? && value.between?(0, 1)
            end
    raise Error, 'typesafe_invalid_response' unless valid
  end

  def resolved_email_index(candidate, answer)
    raise Error, 'missing_email_header' if answer.fetch('choice') == NONE

    index = column_index(answer.fetch('choice'), candidate.fetch(:headers).size)
    profile = candidate.fetch(:profiles).fetch(index)
    raise Error, 'schema_not_resolved' if profile.fetch(:email_like_count).zero?

    index
  end

  def resolved_name_index(candidate, answer)
    choice = answer.fetch('choice')
    choice == NONE ? nil : column_index(choice, candidate.fetch(:headers).size)
  end

  def metadata_for(response, email_answer, name_answer, schema_answer)
    {
      'model' => response.fetch('model'),
      'email_confidence' => email_answer.fetch('confidence'),
      'name_confidence' => name_answer.fetch('confidence'),
      'schema_probability' => schema_answer.fetch('noul')
    }
  end

  def column_index(choice, size)
    raise Error, 'typesafe_invalid_response' unless choice.is_a?(String)

    prefix, index = choice.split('_', 2)
    parsed = Integer(index, exception: false)
    valid = prefix == 'column' && parsed&.between?(0, size - 1) && choice == "column_#{parsed}"
    raise Error, 'typesafe_invalid_response' unless valid

    parsed
  end
end
