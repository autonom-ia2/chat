export const recipientImportRecovery = (t, code) => {
  const reasons = {
    missing_email_header: 'EMAIL',
    no_valid_emails: 'ADDRESSES',
    duplicated_email_header: 'AMBIGUOUS',
    duplicated_name_header: 'NAME',
    schema_not_resolved: 'AMBIGUOUS',
    invalid_header_mapping: 'AMBIGUOUS',
    unsupported_file_format: 'FILE',
    invalid_file: 'FILE',
    invalid_csv: 'FILE',
    invalid_xlsx: 'FILE',
    schema_too_wide: 'WIDTH',
    file_too_large: 'SIZE',
    'email_campaign.file_too_large': 'SIZE',
    empty_file: 'EMPTY',
    row_limit_exceeded: 'ROWS',
    file_expired: 'EXPIRED',
    upload_failed: 'UPLOAD',
    typesafe_not_configured: 'CONFIG',
    typesafe_invalid_key: 'CONFIG',
    typesafe_rate_limited: 'SERVICE',
    typesafe_overloaded: 'SERVICE',
    typesafe_unavailable: 'SERVICE',
    typesafe_invalid_response: 'SERVICE',
    typesafe_invalid_request: 'REQUEST',
  };
  const key = reasons[code] || 'UNKNOWN';
  const prefix = `EMAIL_CAMPAIGN_IMPORT_RECOVERY.CAUSES.${key}`;
  return {
    reason: t(`${prefix}.REASON`),
    correction: t(`${prefix}.CORRECTION`),
    canRetry: ['SERVICE', 'UNKNOWN'].includes(key),
  };
};
