import { spacing } from '../theme';

export const HEADER_ACTION_SIZE = 40;

// Title and the top-right action (gear) sit on the SAME row, just below the safe
// area — a compact, aligned header — instead of the gear floating above the title
// with a big empty gap. Used by CollapsingHeader and the Log screen header.
// Action gap is a touch smaller than the title gap so the 40px gear sits
// vertically CENTERED on the 26px title line (not aligned to its top).
export const HEADER_ACTION_TOP_GAP = spacing.md;
export const HEADER_TITLE_TOP_GAP = spacing.lg;
export const HEADER_TITLE_SIDE_CLEARANCE = HEADER_ACTION_SIZE + spacing.lg;

// The pinned fade bar must be tall enough to cover the title/gear row as content
// scrolls up behind it.
const HEADER_BAR_EXTRA = HEADER_ACTION_SIZE + spacing.sm;

export function headerActionTop(insetTop: number) {
  return insetTop + HEADER_ACTION_TOP_GAP;
}

export function headerTitleTop(insetTop: number) {
  return insetTop + HEADER_TITLE_TOP_GAP;
}

export function headerBarHeight(insetTop: number) {
  return insetTop + HEADER_TITLE_TOP_GAP + HEADER_BAR_EXTRA;
}
