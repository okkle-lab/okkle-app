import React from 'react';
import { View, Text, Modal, Pressable, StyleSheet, Dimensions, type View as RNView } from 'react-native';
import { buttonDepth, colors, font, spacing, radius, type } from '../theme';

type Rect = { x: number; y: number; w: number; h: number };

export type CoachStep = {
  ref?: React.RefObject<RNView | null>;
  rect?: Rect;          // explicit highlight area (e.g. a tab-bar item)
  title: string;
  body: string;
};

const PAD = 8; // breathing room around the highlighted element

// A first-run spotlight tour: dims the screen and highlights real elements one
// at a time with a tooltip. Targets are measured live, so it tracks the layout.
export function CoachMarks({ steps, visible, onDone }: { steps: CoachStep[]; visible: boolean; onDone: () => void }) {
  const [index, setIndex] = React.useState(0);
  const [rect, setRect] = React.useState<Rect | null>(null);
  const screen = Dimensions.get('window');

  React.useEffect(() => { if (visible) setIndex(0); }, [visible]);

  React.useEffect(() => {
    if (!visible) return;
    const step = steps[index];
    if (step?.rect) { setRect({ x: step.rect.x - PAD, y: step.rect.y - PAD, w: step.rect.w + PAD * 2, h: step.rect.h + PAD * 2 }); return; }
    const target = step?.ref?.current;
    if (!target) { setRect(null); return; }
    // Let layout settle, then measure absolute (window) position.
    const t = setTimeout(() => {
      try {
        // @ts-ignore measureInWindow exists on host components
        target.measureInWindow((x: number, y: number, w: number, h: number) => {
          if (w > 0 && h > 0) setRect({ x: x - PAD, y: y - PAD, w: w + PAD * 2, h: h + PAD * 2 });
          else setRect(null);
        });
      } catch { setRect(null); }
    }, 60);
    return () => clearTimeout(t);
  }, [index, visible]);

  if (!visible) return null;
  const step = steps[index];
  const isLast = index === steps.length - 1;
  const next = () => { if (isLast) onDone(); else setIndex(i => i + 1); };

  // Tooltip goes below the target if it's in the top 55% of the screen, else above.
  const below = !rect || rect.y + rect.h < screen.height * 0.55;
  const tooltipTop = rect ? (below ? rect.y + rect.h + 14 : undefined) : screen.height * 0.4;
  const tooltipBottom = rect && !below ? screen.height - rect.y + 14 : undefined;

  return (
    <Modal visible transparent animationType="fade" onRequestClose={onDone} statusBarTranslucent>
      {/* Dim overlay built from four rects around the highlighted hole. */}
      <Pressable style={StyleSheet.absoluteFill} onPress={next}>
        {rect ? (
          <>
            <View style={[s.dim, { top: 0, left: 0, right: 0, height: Math.max(0, rect.y) }]} />
            <View style={[s.dim, { top: rect.y + rect.h, left: 0, right: 0, bottom: 0 }]} />
            <View style={[s.dim, { top: rect.y, left: 0, width: Math.max(0, rect.x), height: rect.h }]} />
            <View style={[s.dim, { top: rect.y, left: rect.x + rect.w, right: 0, height: rect.h }]} />
            <View style={[s.ring, { top: rect.y, left: rect.x, width: rect.w, height: rect.h }]} pointerEvents="none" />
          </>
        ) : (
          <View style={[StyleSheet.absoluteFill, s.dim]} />
        )}

        <View style={[s.tooltip, tooltipTop != null ? { top: tooltipTop } : { bottom: tooltipBottom }]} pointerEvents="box-none">
          <View style={s.card}>
            <Text style={s.title}>{step.title}</Text>
            <Text style={s.body}>{step.body}</Text>
            <View style={s.footer}>
              <View style={s.dots}>
                {steps.map((_, i) => <View key={i} style={[s.dot, i === index && s.dotOn]} />)}
              </View>
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 16 }}>
                {!isLast && <Pressable onPress={onDone} hitSlop={8}><Text style={s.skip}>Skip</Text></Pressable>}
                <Pressable onPress={next} style={({ pressed }) => [s.btn, buttonDepth.raisedStrong, pressed && buttonDepth.pressed]}>
                  <View pointerEvents="none" style={[s.buttonGloss, buttonDepth.gloss]} />
                  <Text style={s.btnText}>{isLast ? 'Got it' : 'Next'}</Text>
                </Pressable>
              </View>
            </View>
          </View>
        </View>
      </Pressable>
    </Modal>
  );
}

const s = StyleSheet.create({
  dim: { position: 'absolute', backgroundColor: 'rgba(15,33,29,0.78)' },
  ring: { position: 'absolute', borderRadius: radius.lg, borderWidth: 2.5, borderColor: colors.brand },
  tooltip: { position: 'absolute', left: spacing.xl, right: spacing.xl },
  card: { backgroundColor: colors.bgCard, borderRadius: radius.lg, padding: spacing.lg },
  title: { ...type.heading, fontSize: 17, marginBottom: 6 },
  body: { ...type.body, fontSize: 15, color: colors.textSecondary, lineHeight: 21 },
  footer: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginTop: spacing.lg },
  dots: { flexDirection: 'row', gap: 5 },
  dot: { width: 6, height: 6, borderRadius: 3, backgroundColor: colors.border },
  dotOn: { backgroundColor: colors.brand, width: 18 },
  skip: { ...type.label, color: colors.textSecondary },
  btn: { backgroundColor: colors.brand, borderRadius: radius.full, borderWidth: 1, borderColor: 'rgba(255,255,255,0.24)', paddingVertical: 9, paddingHorizontal: 20, borderCurve: 'continuous', overflow: 'hidden' },
  btnText: { color: '#fff', fontSize: 15, fontWeight: font.semibold },
  buttonGloss: { borderRadius: radius.full, height: 1, left: 12, position: 'absolute', right: 12, top: 1 },
});
