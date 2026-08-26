# frozen_string_literal: true

require Rails.root.join('lib/vigia/instrumentation')

class ApplicationJob < ActiveJob::Base
  around_perform do |job, block|
    Vigia::Instrumentation.instrument_job(job) { block.call }
  end

  # https://api.rubyonrails.org/v5.2.1/classes/ActiveJob/Exceptions/ClassMethods.html
  discard_on ActiveJob::DeserializationError do |job, error|
    Rails.logger.info("Skipping #{job.class} with #{
      job.instance_variable_get(:@serialized_arguments)
    } because of ActiveJob::DeserializationError (#{error.message})")
  end
end
