import {
  LOCK_REASONS,
  holdsKey,
  keyLockReason,
  memberLockReason,
  reachesKeys,
  reachesRole,
  roleLockReason,
} from '../peopleAccess';

const admin = { userId: 1, isAdmin: true, customRoleId: null, permissions: [] };
const manager = {
  userId: 2,
  isAdmin: false,
  customRoleId: 10,
  permissions: ['people_manage', 'contact_manage', 'crm_view', 'custom_role'],
};
const grantAbove = {
  ...manager,
  permissions: [...manager.permissions, 'grant_above_own'],
};

const smallRole = { id: 20, permissions: ['contact_view', 'crm_view'] };
const bigRole = { id: 21, permissions: ['contact_view', 'inbox_manage'] };
const delegatingRole = { id: 22, permissions: ['people_manage'] };
const roles = [smallRole, bigRole, delegatingRole];

describe('peopleAccess', () => {
  describe('holdsKey', () => {
    it('treats a manage key as holding the matching view key', () => {
      expect(holdsKey(manager, 'contact_view')).toBe(true);
      expect(holdsKey(manager, 'crm_manage_cards')).toBe(false);
      expect(holdsKey(manager, 'inbox_view')).toBe(false);
    });

    it('lets an administrator hold every key', () => {
      expect(holdsKey(admin, 'grant_above_own')).toBe(true);
    });
  });

  describe('reachesKeys / reachesRole (GrantGuard#reach?)', () => {
    it('reaches only keys the giver holds', () => {
      expect(reachesKeys(manager, ['contact_view', 'crm_view'])).toBe(true);
      expect(reachesKeys(manager, ['inbox_manage'])).toBe(false);
    });

    it('never reaches a delegation key, even one the giver holds', () => {
      expect(reachesKeys(manager, ['people_manage'])).toBe(false);
      expect(reachesRole(manager, delegatingRole)).toBe(false);
    });

    it('reaches everything as administrator or with grant_above_own', () => {
      [admin, grantAbove].forEach(giver => {
        expect(reachesRole(giver, bigRole)).toBe(true);
        expect(reachesRole(giver, delegatingRole)).toBe(true);
      });
    });

    // GrantGuard#reach? reads the role through CustomRole.with_implied_permissions: an editing CRM key brings
    // crm_view, so an old role saved without it is out of reach for a giver who lacks crm_view.
    it('counts crm_view implied by an editing CRM key in the role', () => {
      const noCrmView = {
        ...manager,
        permissions: ['people_manage', 'contact_manage', 'crm_manage_cards'],
      };
      const oldRole = { id: 23, permissions: ['crm_manage_cards'] };
      expect(reachesRole(noCrmView, oldRole)).toBe(false);
      expect(roleLockReason(noCrmView, oldRole)).toBe(LOCK_REASONS.ABOVE);
      expect(
        memberLockReason(noCrmView, { id: 5, custom_role_id: 23 }, [oldRole])
      ).toBe(LOCK_REASONS.ABOVE);
      expect(
        reachesRole(
          { ...noCrmView, permissions: [...noCrmView.permissions, 'crm_view'] },
          oldRole
        )
      ).toBe(true);
    });

    it('always reaches a plain agent (no custom role)', () => {
      expect(reachesRole(manager, null)).toBe(true);
    });
  });

  describe('memberLockReason', () => {
    it('locks one own row for everyone', () => {
      expect(memberLockReason(admin, { id: 1, role: 'administrator' })).toBe(
        LOCK_REASONS.SELF
      );
      expect(memberLockReason(manager, { id: 2, role: 'agent' })).toBe(
        LOCK_REASONS.SELF
      );
    });

    it('locks administrators for non-administrators only', () => {
      const target = { id: 5, role: 'administrator' };
      expect(memberLockReason(manager, target)).toBe(LOCK_REASONS.ADMIN);
      expect(memberLockReason(grantAbove, target)).toBe(LOCK_REASONS.ADMIN);
      expect(memberLockReason(admin, target)).toBeNull();
    });

    it('locks members whose current role is out of reach', () => {
      const above = { id: 6, role: 'agent', custom_role_id: bigRole.id };
      const within = { id: 7, role: 'agent', custom_role_id: smallRole.id };
      const plain = { id: 8, role: 'agent', custom_role_id: null };
      expect(memberLockReason(manager, above, roles)).toBe(LOCK_REASONS.ABOVE);
      expect(memberLockReason(manager, within, roles)).toBeNull();
      expect(memberLockReason(manager, plain, roles)).toBeNull();
      expect(memberLockReason(grantAbove, above, roles)).toBeNull();
    });

    it('does not lock a member whose role is not loaded yet (the server decides)', () => {
      const unknown = { id: 9, role: 'agent', custom_role_id: 99 };
      expect(memberLockReason(manager, unknown, roles)).toBeNull();
      expect(memberLockReason(admin, unknown, roles)).toBeNull();
    });
  });

  describe('roleLockReason', () => {
    it('locks the role I hold, unless I am an administrator', () => {
      expect(roleLockReason(manager, { id: 10, permissions: [] })).toBe(
        LOCK_REASONS.MINE
      );
      expect(roleLockReason(grantAbove, { id: 10, permissions: [] })).toBe(
        LOCK_REASONS.MINE
      );
    });

    it('locks roles out of reach and leaves the rest open', () => {
      expect(roleLockReason(manager, bigRole)).toBe(LOCK_REASONS.ABOVE);
      expect(roleLockReason(manager, smallRole)).toBeNull();
      expect(roleLockReason(admin, bigRole)).toBeNull();
    });
  });

  describe('keyLockReason', () => {
    it('explains a missing key and a delegation key apart', () => {
      expect(keyLockReason(manager, 'inbox_manage')).toBe(LOCK_REASONS.MISSING);
      expect(keyLockReason(manager, 'people_manage')).toBe(
        LOCK_REASONS.DELEGATION
      );
      expect(keyLockReason(manager, 'contact_view')).toBeNull();
    });

    // #2075: as metas do mês precisam dos valores em R$, que são chave protegida.
    it('locks a key whose dependency is out of reach, with the dependency reason', () => {
      const metas = {
        ...manager,
        permissions: ['crm_view', 'crm_metas_manage'],
      };
      expect(keyLockReason(metas, 'crm_metas_manage')).toBe(
        LOCK_REASONS.DELEGATION
      );
      expect(keyLockReason(grantAbove, 'crm_metas_manage')).toBeNull();
    });

    it('opens every key to whoever reaches everything', () => {
      expect(keyLockReason(grantAbove, 'grant_above_own')).toBeNull();
      expect(keyLockReason(admin, 'inbox_manage')).toBeNull();
    });
  });
});
