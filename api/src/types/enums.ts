export const Role = {
  TRAINER_ADMIN: 'TRAINER_ADMIN',
  TRAINER: 'TRAINER',
  PARENT: 'PARENT',
} as const;

export type Role = (typeof Role)[keyof typeof Role];

export const AccountStatus = {
  PENDING: 'PENDING',
  APPROVED: 'APPROVED',
  BLOCKED: 'BLOCKED',
} as const;

export type AccountStatus = (typeof AccountStatus)[keyof typeof AccountStatus];

export const EventType = {
  TRAINING: 'TRAINING',
  MATCH: 'MATCH',
  EVENT: 'EVENT',
} as const;

export type EventType = (typeof EventType)[keyof typeof EventType];

export const AttendanceStatus = {
  YES: 'YES',
  NO: 'NO',
  MAYBE: 'MAYBE',
  UNKNOWN: 'UNKNOWN',
} as const;

export type AttendanceStatus = (typeof AttendanceStatus)[keyof typeof AttendanceStatus];
