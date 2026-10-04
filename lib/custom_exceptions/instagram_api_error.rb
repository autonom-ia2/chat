class CustomExceptions::InstagramApiError < StandardError
  attr_reader :code, :http_status

  def initialize(code, http_status)
    @code = code
    @http_status = http_status
    super(code)
  end
end
