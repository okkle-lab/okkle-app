import { spacing } from '../theme';

export const HEADER_ACTION_SIZE = 40;
export const HEADER_ACTION_TOP_GAP = spacing.sm;
export const HEADER_TITLE_TOP_GAP = HEADER_ACTION_TOP_GAP + HEADER_ACTION_SIZE + spacing.md;
export const HEADER_TITLE_SIDE_CLEARANCE = HEADER_ACTION_SIZE + spacing.lg;

export function headerActionTop(insetTop: number) {
  return insetTop + HEADER_ACTION_TOP_GAP;
}

export function headerTitleTop(insetTop: number) {
  return insetTop + HEADER_TITLE_TOP_GAP;
}
