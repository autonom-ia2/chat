// Who may hand out which access (#1931). Mirrors CustomRoles::GrantGuard and AccountUsers::AccessGuard;
// the server stays the source of truth, the screen only avoids offering what it would refuse.
//
// `giver` = { userId, isAdmin, customRoleId, permissions } of the current seat.
import {
  DELEGATION_KEYS,
  GRANT_ABOVE_OWN_PERMISSION,
} from 'dashboard/constants/permissions';

const VIEW_SUFFIX = '_view';

export const LOCK_REASONS = {
  SELF: 'SELF',
  ADMIN: 'ADMIN',
  ABOVE: 'ABOVE',
  MINE: 'MINE',
  MISSING: 'MISSING',
  DELEGATION: 'DELEGATION',
};

// A `<module>_manage` key implies the matching `<module>_view`, as in Enterprise::AccountUser#permission_granted?.
export const holdsKey = (giver, key) => {
  if (giver.isAdmin) return true;
  const held = giver.permissions || [];
  if (held.includes(key)) return true;
  if (!key.endsWith(VIEW_SUFFIX)) return false;
  return held.includes(`${key.slice(0, -VIEW_SUFFIX.length)}_manage`);
};

const reachesEverything = giver =>
  giver.isAdmin || holdsKey(giver, GRANT_ABOVE_OWN_PERMISSION);

// GrantGuard#reach?: every key held by the giver and none a delegation key, unless the giver reaches everything.
export const reachesKeys = (giver, keys = []) =>
  reachesEverything(giver) ||
  keys.every(key => !DELEGATION_KEYS.includes(key) && holdsKey(giver, key));

// No role means a plain agent, always allowed.
export const reachesRole = (giver, role) =>
  !role || reachesKeys(giver, role.permissions || []);

// Why the giver cannot edit or remove this member, or null when they can.
export const memberLockReason = (giver, agent, roles = []) => {
  if (agent.id === giver.userId) return LOCK_REASONS.SELF;
  if (agent.role === 'administrator' && !giver.isAdmin)
    return LOCK_REASONS.ADMIN;
  if (!agent.custom_role_id || reachesEverything(giver)) return null;
  // Whoever manages people reads every role, so a role missing from the list is one still loading (or failed to
  // load): no lock, the server decides.
  const role = roles.find(item => item.id === agent.custom_role_id);
  return !role || reachesRole(giver, role) ? null : LOCK_REASONS.ABOVE;
};

// Why the giver cannot edit or delete this custom role, or null when they can.
export const roleLockReason = (giver, role) => {
  if (giver.isAdmin) return null;
  if (role.id === giver.customRoleId) return LOCK_REASONS.MINE;
  return reachesRole(giver, role) ? null : LOCK_REASONS.ABOVE;
};

// Why the giver cannot put this key in a role, or null when they can.
export const keyLockReason = (giver, key) => {
  if (reachesKeys(giver, [key])) return null;
  return DELEGATION_KEYS.includes(key)
    ? LOCK_REASONS.DELEGATION
    : LOCK_REASONS.MISSING;
};
