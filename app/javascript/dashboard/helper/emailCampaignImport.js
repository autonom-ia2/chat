export const isRecipientImportActive = campaign =>
  ['queued', 'processing'].includes(campaign?.recipient_import?.status);

export const recipientImportError = (t, code) => {
  const codes = {
    'email_campaign.file_too_large': 'FILE_TOO_LARGE',
    unsupported_file_format: 'INVALID_FILE',
    invalid_file: 'INVALID_FILE',
    upload_failed: 'UPLOAD_FAILED',
    empty_file: 'EMPTY_FILE',
    row_limit_exceeded: 'ROW_LIMIT',
    import_in_progress: 'IN_PROGRESS',
    file_expired: 'EXPIRED',
    missing_email_header: 'HEADERS',
    schema_not_resolved: 'HEADERS',
    schema_too_wide: 'INVALID_FILE',
    typesafe_not_configured: 'FAILED',
    typesafe_invalid_key: 'FAILED',
    typesafe_rate_limited: 'FAILED',
    typesafe_overloaded: 'FAILED',
    typesafe_unavailable: 'FAILED',
    typesafe_invalid_response: 'FAILED',
  };
  const headerError = code
    ?.split(',')
    .some(item =>
      [
        'missing_name_header',
        'missing_email_header',
        'duplicated_name_header',
        'duplicated_email_header',
      ].includes(item)
    );
  const key = headerError ? 'HEADERS' : codes[code] || 'FAILED';
  return t(`CAMPAIGN.EMAIL_CAMPAIGN.IMPORT.ERRORS.${key}`);
};
