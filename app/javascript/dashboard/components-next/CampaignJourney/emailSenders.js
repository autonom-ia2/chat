// Which e-mail senders the campaign engine can really use (#993, decision of 05/10):
// a verified sending domain (SES) or a connected webmail inbox accepted for direct send.
//
// This is the rule EmailCampaignDialog.vue applies to list senders. That dialog keeps the
// list in a private constant of its <script setup> and cannot be edited by this epic
// (PRD §8.0, H2), so it cannot import this module yet. The spec
// `specs/emailSenders.spec.js` reads the dialog's source and fails if the two lists
// drift; when the dialog is free to change, it should import from here instead.
// Backend counterpart: EmailCampaigns::DirectInbox::Limits::WEBMAIL_DOMAINS.
import { INBOX_TYPES } from 'dashboard/helper/inbox';

export const WEBMAIL_DOMAINS = [
  'gmail.com',
  'googlemail.com',
  'hotmail.com',
  'hotmail.com.br',
  'outlook.com',
  'outlook.com.br',
  'live.com',
  'msn.com',
  'yahoo.com',
  'yahoo.com.br',
  'ymail.com',
  'icloud.com',
  'me.com',
  'mac.com',
  'aol.com',
  'gmx.com',
  'proton.me',
  'protonmail.com',
  'bol.com.br',
  'uol.com.br',
  'terra.com.br',
];

export const isWebmail = email =>
  WEBMAIL_DOMAINS.includes((email || '').split('@').pop()?.toLowerCase());

export const isVerifiedIdentity = identity => identity?.status === 'verified';

export const isDirectSendInbox = inbox =>
  inbox?.channel_type === INBOX_TYPES.EMAIL &&
  Boolean(inbox.email) &&
  isWebmail(inbox.email);

export const hasUsableEmailSender = ({
  inboxes = [],
  senderIdentities = [],
} = {}) =>
  senderIdentities.some(isVerifiedIdentity) || inboxes.some(isDirectSendInbox);
