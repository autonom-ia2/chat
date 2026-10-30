// Which sentence the edit screen shows when saving someone fails (#2317). A custom role refusal carries its reason
// code (out_of_reach, as in /custom_roles); anything else keeps the generic message.
const BY_CODE = {
  out_of_reach: 'AGENT_MGMT.EDIT.API.OUT_OF_REACH',
};

export const agentUpdateErrorKey = error =>
  BY_CODE[error?.code] || 'AGENT_MGMT.EDIT.API.ERROR_MESSAGE';
