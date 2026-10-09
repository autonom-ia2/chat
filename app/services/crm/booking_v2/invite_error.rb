# Recusa de negócio do link por cliente (#1190). É um ArgumentError (entrada que não fecha) com o código do erro
# como mensagem: 'no_page', 'invite_invalid', 'invite_text_invalid'. O controller responde 422
# `crm.booking_v2.<código>` só para esta classe, nunca para um ArgumentError qualquer.
class Crm::BookingV2::InviteError < ArgumentError; end
