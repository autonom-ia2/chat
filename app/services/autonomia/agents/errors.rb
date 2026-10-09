module Autonomia::Agents::Errors
  class ContractError < StandardError
    attr_reader :code, :key

    def initialize(code:, key: nil)
      @code = code
      @key = key
      super(code)
    end
  end

  class ManualMode < ContractError
    def initialize
      super(code: 'manual_mode')
    end
  end

  class NoGuidedVersion < ContractError
    def initialize
      super(code: 'no_guided_version')
    end
  end

  class UnrestorableVersion < ContractError
    def initialize
      super(code: 'unrestorable_version')
    end
  end

  class ConfigKeyNotAllowed < ContractError
    def initialize(key)
      super(code: 'config_key_not_allowed', key: key)
    end
  end

  class OperationValueNotAllowed < ContractError
    def initialize(key)
      super(code: 'operation_value_not_allowed', key: key)
    end
  end

  class PublishRejected < ContractError; end
end
