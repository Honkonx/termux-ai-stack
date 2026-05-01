// src/theme/typography.js
import { Platform } from 'react-native';

export const Typography = {
  size: {
    xs:   10,
    sm:   11,
    base: 13,
    md:   14,
    lg:   15,
    xl:   17,
    '2xl': 20,
    '3xl': 24,
  },
  weight: {
    normal:   '400',
    medium:   '500',
    semibold: '600',
    bold:     '700',
    heavy:    '800',
  },
  mono: Platform.OS === 'android' ? 'monospace' : 'Courier New',
  sans: undefined,
  styles: {
    h1:      { fontSize: 20, fontWeight: '700', letterSpacing: -0.5 },
    h2:      { fontSize: 17, fontWeight: '700' },
    h3:      { fontSize: 15, fontWeight: '600' },
    body:    { fontSize: 13, fontWeight: '400', lineHeight: 20 },
    caption: { fontSize: 11, fontWeight: '500', letterSpacing: 0.5 },
    label:   { fontSize: 10, fontWeight: '700', letterSpacing: 1, textTransform: 'uppercase' },
    code:    { fontSize: 11, fontFamily: Platform.OS === 'android' ? 'monospace' : 'Courier New', lineHeight: 17 },
  },
};
