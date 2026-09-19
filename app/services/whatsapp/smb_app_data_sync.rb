# Fork (WhatsApp Coexistence history sync). Lives outside Whatsapp::FacebookApiClient so that
# upstream class stays as upstream ships it (and within Metrics/ClassLength); included there and
# relies on its @api_version, request_headers and handle_response.
module Whatsapp::SmbAppDataSync
  # Kicks off a WhatsApp Coexistence sync via the SMB App Data API.
  # sync_type is 'smb_app_state_sync' for the contact roster and 'history' for the
  # 6-month messaging history. Meta returns { messaging_product:, request_id: } on success.
  # https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/onboarding-business-app-users
  def start_smb_app_data_sync(phone_number_id, sync_type)
    response = HTTParty.post(
      "#{Whatsapp::FacebookApiClient::BASE_URI}/#{@api_version}/#{phone_number_id}/smb_app_data",
      headers: request_headers,
      body: { messaging_product: 'whatsapp', sync_type: sync_type }.to_json
    )

    handle_response(response, 'SMB app data sync failed')
  end
end
