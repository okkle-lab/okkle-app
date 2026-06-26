import { useEffect, useRef, useState } from 'react';
import { Text, TextStyle } from 'react-native';

type Props = {
  value: number;
  prefix?: string;
  decimals?: number;
  duration?: number;
  style?: TextStyle | TextStyle[];
};

// Counts up to `value` on mount/change — a small delight for the tax-saved hero.
export function CountUp({ value, prefix = '', decimals = 2, duration = 900, style }: Props) {
  const [display, setDisplay] = useState(0);
  const raf = useRef<number | null>(null);
  const fromRef = useRef(0);

  useEffect(() => {
    const from = fromRef.current;
    const start = Date.now();
    function tick() {
      const t = Math.min(1, (Date.now() - start) / duration);
      const eased = 1 - Math.pow(1 - t, 3); // ease-out cubic
      setDisplay(from + (value - from) * eased);
      if (t < 1) raf.current = requestAnimationFrame(tick);
      else fromRef.current = value;
    }
    raf.current = requestAnimationFrame(tick);
    return () => { if (raf.current) cancelAnimationFrame(raf.current); };
  }, [value, duration]);

  const formatted = prefix + display.toLocaleString('en-GB', {
    minimumFractionDigits: decimals, maximumFractionDigits: decimals,
  });
  return <Text style={style}>{formatted}</Text>;
}
