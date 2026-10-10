# chat#1217 — Na troca de conta, o Facebook devolveu um número diferente do número da caixa.
class Whatsapp::SwitchAccount::PhoneNumberMismatchError < StandardError
  ERROR_CODE = 'phone_number_mismatch'.freeze

  attr_reader :expected, :received

  def initialize(expected:, received:)
    @expected = expected
    @received = received
    super("Phone number mismatch. Expected #{expected}, got #{received}")
  end
end
