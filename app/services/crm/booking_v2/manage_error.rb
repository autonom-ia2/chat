# Recusa de uma ação na página de gestão da reunião (#1192). A mensagem é o código público (`not_changeable`,
# `too_late`, `slot_unavailable`, `booking_failed`).
class Crm::BookingV2::ManageError < StandardError; end
